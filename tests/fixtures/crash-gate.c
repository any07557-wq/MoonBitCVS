/* Test-only fsync gate/observer. It never changes the production executable. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static atomic_int stopped;

int fsync(int fd) {
  int (*next)(int) = dlsym(RTLD_NEXT, "fsync");
  char link[64], path[4096], marker[8192], release[8192];
  snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t size = readlink(link, path, sizeof(path) - 1);
  if (size < 0) return next(fd);
  path[size] = 0;
  const char *trace = getenv("MOONVCS_SYNC_TRACE");
  if (trace) {
    int out = open(trace, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out >= 0) { dprintf(out, "%s\n", path); close(out); }
  }
  const char *mode = getenv("MOONVCS_CRASH_GATE_MODE");
  const char *directory = getenv("MOONVCS_CRASH_GATE_DIR");
  const char *metadata = getenv("MOONVCS_CRASH_METADATA");
  const char *fail_directory = getenv("MOONVCS_FAIL_DIR_SYNC");
  if (fail_directory && !strcmp(path, fail_directory)) { errno = EIO; return -1; }
  int matches = mode && directory && (
    (!strcmp(mode, "index-before-publish") && strstr(path, "/.moonvcs/index.lock")) ||
    (!strcmp(mode, "index-after-rename") && metadata && !strcmp(path, metadata)) ||
    (!strcmp(mode, "quarantine-before-validation") && strstr(path, "/.moonvcs/quarantine/rx-") && strstr(path, "/.moonvcs/objects/"))
  );
  if (matches && !atomic_exchange(&stopped, 1)) {
    /* index-before gate follows file fsync; after-rename gate precedes directory fsync. */
    if (!strcmp(mode, "index-before-publish")) {
      if (next(fd)) return -1;
    }
    snprintf(marker, sizeof(marker), "%s/entered", directory);
    snprintf(release, sizeof(release), "%s/release", directory);
    int signal = open(marker, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (signal < 0) _exit(91);
    close(signal);
    struct timespec delay = {0, 5000000};
    for (int attempt = 0; attempt < 6000; attempt++) {
      if (!access(release, F_OK)) return next(fd);
      nanosleep(&delay, NULL);
    }
    _exit(92);
  }
  return next(fd);
}
