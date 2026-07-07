import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Free bytes available to the current user on the volume containing [path], or
/// null if it can't be determined.
///
/// Windows calls the Win32 `GetDiskFreeSpaceExW` directly via `dart:ffi` — no
/// platform channel or native runner code. Linux (and macOS, best-effort) shell
/// out to `df`. Throwing is left to the caller to catch/log.
Future<int?> freeDiskSpaceBytes(String path) async {
  if (Platform.isWindows) return _windowsFreeBytes(path);
  return _dfFreeBytes(path);
}

// ── Windows: kernel32!GetDiskFreeSpaceExW ────────────────────────────────────
// BOOL GetDiskFreeSpaceExW(LPCWSTR lpDirectoryName,
//   PULARGE_INTEGER lpFreeBytesAvailableToCaller,  // <- what we want
//   PULARGE_INTEGER lpTotalNumberOfBytes,
//   PULARGE_INTEGER lpTotalNumberOfFreeBytes);
typedef _GetDiskFreeSpaceExNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _GetDiskFreeSpaceExDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);

int? _windowsFreeBytes(String path) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getDiskFreeSpaceEx = kernel32.lookupFunction<
      _GetDiskFreeSpaceExNative,
      _GetDiskFreeSpaceExDart>('GetDiskFreeSpaceExW');

  final pathPtr = path.toNativeUtf16();
  final freeAvailable = calloc<Uint64>();
  final totalBytes = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    final ok =
        getDiskFreeSpaceEx(pathPtr, freeAvailable, totalBytes, totalFree);
    if (ok == 0) return null; // API returned FALSE
    return freeAvailable.value;
  } finally {
    calloc.free(pathPtr);
    calloc.free(freeAvailable);
    calloc.free(totalBytes);
    calloc.free(totalFree);
  }
}

// ── Linux / macOS: df ────────────────────────────────────────────────────────
// `df -B1 --output=avail <path>` prints a header line then the available bytes
// for the volume holding <path>.
Future<int?> _dfFreeBytes(String path) async {
  final res = await Process.run('df', ['-B1', '--output=avail', path]);
  if (res.exitCode != 0) return null;
  final lines = (res.stdout as String).trim().split('\n');
  if (lines.length < 2) return null;
  return int.tryParse(lines.last.trim());
}
