/* Test-only SIGKILL / fsync-EIO gates. Owned temporary repositories only. */
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

static int text_is(const char *path, const char *expected) {
  char data[256];
  int fd = open(path, O_RDONLY | O_NOFOLLOW);
  if (fd < 0) return 0;
  ssize_t count = read(fd, data, sizeof(data) - 1);
  close(fd);
  if (count < 0) return 0;
  data[count] = 0;
  return !strcmp(data, expected);
}

static int same_bytes(const char *first, const char *second) {
  int a = open(first, O_RDONLY | O_NOFOLLOW), b = open(second, O_RDONLY | O_NOFOLLOW);
  if (a < 0 || b < 0) { if (a >= 0) close(a); if (b >= 0) close(b); return 0; }
  char x[4096], y[4096];
  int same = 1;
  while (1) {
    ssize_t n = read(a, x, sizeof(x)), m = read(b, y, sizeof(y));
    if (n < 0 || m != n || (n > 0 && memcmp(x, y, n))) { same = 0; break; }
    if (!n) break;
  }
  close(a); close(b);
  return same;
}

int fsync(int fd) {
  int (*next)(int) = dlsym(RTLD_NEXT, "fsync");
  const char *mode = getenv("MOONVCS_SWITCH_GATE_MODE");
  const char *gate = getenv("MOONVCS_SWITCH_GATE_DIR");
  const char *metadata = getenv("MOONVCS_SWITCH_METADATA");
  if (!mode || !gate || !metadata) return next(fd);
  char link[64], actual[4096], phase[8192], phase_lock[8192], backup[8192];
  char index[8192], new_index[8192], head[8192], new_head[8192], pending[4096];
  snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t size = readlink(link, actual, sizeof(actual) - 1);
  if (size < 0) return next(fd);
  actual[size] = 0;
  snprintf(pending, sizeof(pending), "%s/switch-transaction", metadata);
  snprintf(phase, sizeof(phase), "%s/phase", pending);
  snprintf(phase_lock, sizeof(phase_lock), "%s/phase.lock", pending);
  snprintf(backup, sizeof(backup), "%s/before", pending);
  snprintf(index, sizeof(index), "%s/index", metadata);
  snprintf(new_index, sizeof(new_index), "%s/new-index", pending);
  snprintf(head, sizeof(head), "%s/HEAD", metadata);
  snprintf(new_head, sizeof(new_head), "%s/new-HEAD", pending);
  int matches =
    (!strcmp(mode, "prepared") && !strcmp(actual, phase_lock) && text_is(phase_lock, "prepared\n")) ||
    (!strcmp(mode, "backup") && !strcmp(actual, backup) && text_is(phase, "applying\n")) ||
    (!strcmp(mode, "index") && !strcmp(actual, metadata) && text_is(phase, "applying\n") && same_bytes(index, new_index)) ||
    (!strcmp(mode, "head") && !strcmp(actual, metadata) && text_is(phase, "index_published\n") && same_bytes(head, new_head)) ||
    (!strcmp(mode, "archive") && !strcmp(actual, metadata) && access(pending, F_OK) && errno == ENOENT);
  if (!matches || atomic_exchange(&stopped, 1)) return next(fd);
  char marker[8192], release[8192];
  snprintf(marker, sizeof(marker), "%s/entered", gate);
  snprintf(release, sizeof(release), "%s/release", gate);
  int signal = open(marker, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (signal < 0) _exit(91);
  close(signal);
  if (getenv("MOONVCS_SWITCH_GATE_EIO")) { errno = EIO; return -1; }
  struct timespec delay = {0, 5000000};
  for (int attempt = 0; attempt < 6000; attempt++) {
    if (!access(release, F_OK)) return next(fd);
    nanosleep(&delay, NULL);
  }
  _exit(92);
}
