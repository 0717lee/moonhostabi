#include <errno.h>
#include <stdio.h>
#include <wchar.h>

#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

MOONBIT_FFI_EXPORT int moonhostabi_write_stderr(
    moonbit_bytes_t bytes,
    int length) {
  size_t written = fwrite(bytes, 1, (size_t)length, stderr);
  int flushed = fflush(stderr);
  return written == (size_t)length && flushed == 0 ? 0 : -1;
}

#ifdef _WIN32
typedef moonbit_string_t moonhostabi_path_t;
#else
typedef moonbit_bytes_t moonhostabi_path_t;
#endif

MOONBIT_FFI_EXPORT int moonhostabi_write_new_file(
    moonhostabi_path_t path,
    moonbit_bytes_t bytes,
    int length) {
#ifdef _WIN32
  FILE *file = _wfopen((const wchar_t *)path, L"wbx");
#else
  FILE *file = fopen((const char *)path, "wbx");
#endif
  if (file == NULL) {
    return errno == EEXIST ? 1 : -1;
  }
  size_t written = fwrite(bytes, 1, (size_t)length, file);
  int flushed = fflush(file);
  int closed = fclose(file);
  if (written == (size_t)length && flushed == 0 && closed == 0) {
    return 0;
  }
#ifdef _WIN32
  _wremove((const wchar_t *)path);
#else
  remove((const char *)path);
#endif
  return -1;
}

#ifdef __cplusplus
}
#endif
