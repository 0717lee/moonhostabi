#ifndef _WIN32
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <stdio.h>
#include <wchar.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif
#endif
#endif

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

MOONBIT_FFI_EXPORT int moonhostabi_rename_directory_noreplace(
    moonhostabi_path_t source,
    moonhostabi_path_t destination) {
#ifdef _WIN32
  if (MoveFileExW(
          (const wchar_t *)source,
          (const wchar_t *)destination,
          MOVEFILE_WRITE_THROUGH)) {
    return 0;
  }
  DWORD error = GetLastError();
  return error == ERROR_ALREADY_EXISTS || error == ERROR_FILE_EXISTS ? 1 : -1;
#elif defined(__linux__) && defined(SYS_renameat2)
  int result = (int)syscall(
      SYS_renameat2,
      AT_FDCWD,
      (const char *)source,
      AT_FDCWD,
      (const char *)destination,
      RENAME_NOREPLACE);
  if (result == 0) {
    return 0;
  }
  return errno == EEXIST || errno == ENOTEMPTY ? 1 : -1;
#else
  (void)source;
  (void)destination;
  errno = ENOTSUP;
  return -1;
#endif
}

#ifdef __cplusplus
}
#endif
