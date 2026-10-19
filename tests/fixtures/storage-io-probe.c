/* Profiling-only interposer. Counts logical pread calls/bytes, never payloads. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static atomic_ulong objects, object_bytes, promises, promise_bytes, source_reads, source_bytes, read_ns;

ssize_t pread(int fd, void *buffer, size_t count, off_t offset) {
  ssize_t (*next)(int, void *, size_t, off_t) = dlsym(RTLD_NEXT, "pread");
  struct timespec before, after;
  clock_gettime(CLOCK_MONOTONIC, &before);
  ssize_t result = next(fd, buffer, count, offset);
  clock_gettime(CLOCK_MONOTONIC, &after);
  if (result <= 0) return result;
  atomic_fetch_add(&read_ns, (after.tv_sec - before.tv_sec) * 1000000000UL + after.tv_nsec - before.tv_nsec);
  char link[64], path[4096];
  snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t size = readlink(link, path, sizeof(path) - 1);
  if (size < 0) return result;
  path[size] = 0;
  if (strstr(path, "/.moonvcs/objects/")) {
    atomic_fetch_add(&objects, 1);
    atomic_fetch_add(&object_bytes, result);
  }
  if (strstr(path, "/.moonvcs/promises/")) {
    atomic_fetch_add(&promises, 1);
    atomic_fetch_add(&promise_bytes, result);
  }
  const char *source = getenv("MOONVCS_PROFILE_SOURCE_OBJECT");
  if (source && !strcmp(source, path)) {
    atomic_fetch_add(&source_reads, 1);
    atomic_fetch_add(&source_bytes, result);
  }
  return result;
}

__attribute__((destructor)) static void report(void) {
  const char *path = getenv("MOONVCS_PROFILE_IO_REPORT");
  if (!path) return;
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (fd < 0) return;
  dprintf(fd, "{\"object_read_calls\":%lu,\"object_logical_bytes\":%lu,\"promise_read_calls\":%lu,\"promise_logical_bytes\":%lu,\"same_tree_reads\":%lu,\"same_tree_logical_bytes\":%lu,\"pread_wall_ns\":%lu}\n",
          (unsigned long)objects, (unsigned long)object_bytes, (unsigned long)promises, (unsigned long)promise_bytes,
          (unsigned long)source_reads, (unsigned long)source_bytes, (unsigned long)read_ns);
  close(fd);
}
