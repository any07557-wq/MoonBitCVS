/* Test-only LD_PRELOAD barrier. Never linked into MoonVCS. Harmless owned fixtures only. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static atomic_int stopped;

ssize_t pread(int fd, void *buffer, size_t count, off_t offset) {
  static ssize_t (*real_pread)(int, void *, size_t, off_t);
  if (!real_pread) real_pread = dlsym(RTLD_NEXT, "pread");
  ssize_t result = real_pread(fd, buffer, count, offset);
  const char *directory = getenv("MOONVCS_STAGE_TEST_DIR");
  const char *index = getenv("MOONVCS_STAGE_TEST_INDEX");
  const char *role = getenv("MOONVCS_STAGE_TEST_ROLE");
  if (!directory || !index || !role || offset || result <= 0) return result;
  char link[64], actual[4096], marker[8192], release[8192];
  snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t size = readlink(link, actual, sizeof(actual) - 1);
  if (size < 0) return result;
  actual[size] = 0;
  if (strcmp(actual, index) || atomic_exchange(&stopped, 1)) return result;
  snprintf(marker, sizeof(marker), "%s/%s.read", directory, role);
  snprintf(release, sizeof(release), "%s/%s.release", directory, role);
  int signal = open(marker, O_CREAT | O_EXCL | O_WRONLY, 0600);
  if (signal < 0) _exit(91);
  close(signal);
  struct timespec delay = {0, 5000000};
  for (int attempt = 0; attempt < 4000; attempt++) {
    if (access(release, F_OK) == 0) return result;
    nanosleep(&delay, NULL);
  }
  _exit(92);
}
