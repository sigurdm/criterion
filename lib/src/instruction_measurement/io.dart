// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../result.dart';

// Linux x86_64 syscall number for perf_event_open
const int _sysPerfEventOpen = 298;

// ioctl constants
const int _perfEventIocEnable = 0x20002400;
const int _perfEventIocDisable = 0x20002401;
const int _perfEventIocReset = 0x20002403;

// libc mapping
final DynamicLibrary _libc = DynamicLibrary.process();

typedef _SyscallNative =
    Int32 Function(
      Int64 number,
      Pointer<Void> attr,
      Int32 pid,
      Int32 cpu,
      Int32 groupFd,
      Uint64 flags,
    );
typedef _SyscallDart =
    int Function(
      int number,
      Pointer<Void> attr,
      int pid,
      int cpu,
      int groupFd,
      int flags,
    );

final _SyscallDart? _syscall = () {
  try {
    return _libc.lookupFunction<_SyscallNative, _SyscallDart>('syscall');
  } catch (_) {
    return null;
  }
}();

typedef _IoctlNative = Int32 Function(Int32 fd, Uint64 request, Int64 arg);
typedef _IoctlDart = int Function(int fd, int request, int arg);
final _IoctlDart? _ioctl = () {
  try {
    return _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
  } catch (_) {
    return null;
  }
}();

typedef _ReadNative = Int64 Function(Int32 fd, Pointer<Void> buf, Uint64 count);
typedef _ReadDart = int Function(int fd, Pointer<Void> buf, int count);
final _ReadDart? _read = () {
  try {
    return _libc.lookupFunction<_ReadNative, _ReadDart>('read');
  } catch (_) {
    return null;
  }
}();

typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);
final _CloseDart? _close = () {
  try {
    return _libc.lookupFunction<_CloseNative, _CloseDart>('close');
  } catch (_) {
    return null;
  }
}();

/// Helper to perform hardware CPU instruction measurements using Linux perf events.
final class InstructionMeasurer {
  /// Whether hardware instruction counting is supported on this platform.
  static bool get isSupported {
    if (!Platform.isLinux) return false;
    if (_syscall == null || _ioctl == null || _read == null || _close == null) {
      return false;
    }

    final syscallFn = _syscall!;
    final closeFn = _close!;

    final attrSize = 120;
    final attr = calloc<Uint8>(attrSize);

    // Set fields:
    // type (uint32) at offset 0 -> 0 (PERF_TYPE_HARDWARE)
    attr.cast<Uint32>().value = 0;
    // size (uint32) at offset 4 -> attrSize (120)
    (attr + 4).cast<Uint32>().value = attrSize;
    // config (uint64) at offset 8 -> 0 (PERF_COUNT_HW_INSTRUCTIONS)
    (attr + 8).cast<Uint64>().value = 0;
    // flags (uint64) at offset 40 -> 97 (disabled=1, exclude_kernel=1, exclude_hv=1)
    (attr + 40).cast<Uint64>().value = 97;

    // Open the event (pid = 0 for calling process, cpu = -1 for any CPU)
    final fd = syscallFn(_sysPerfEventOpen, attr.cast<Void>(), 0, -1, -1, 0);
    calloc.free(attr);

    if (fd >= 0) {
      closeFn(fd);
      return true;
    }
    return false;
  }

  /// Measures CPU instructions for [fn] over [iterations] runs.
  ///
  /// Returns `null` if instruction counting is not supported or fails.
  static Future<InstructionResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
  }) async {
    if (!isSupported) return null;

    final syscallFn = _syscall!;
    final ioctlFn = _ioctl!;
    final readFn = _read!;
    final closeFn = _close!;

    final attrSize = 120;
    final attr = calloc<Uint8>(attrSize);

    // Set fields:
    // type (uint32) at offset 0 -> 0 (PERF_TYPE_HARDWARE)
    attr.cast<Uint32>().value = 0;
    // size (uint32) at offset 4 -> attrSize (120)
    (attr + 4).cast<Uint32>().value = attrSize;
    // config (uint64) at offset 8 -> 0 (PERF_COUNT_HW_INSTRUCTIONS)
    (attr + 8).cast<Uint64>().value = 0;
    // flags (uint64) at offset 40 -> 97 (disabled=1, exclude_kernel=1, exclude_hv=1)
    (attr + 40).cast<Uint64>().value = 97;

    // Open the event (pid = 0 for calling process, cpu = -1 for any CPU)
    final fd = syscallFn(_sysPerfEventOpen, attr.cast<Void>(), 0, -1, -1, 0);
    calloc.free(attr);

    if (fd < 0) {
      return null;
    }

    try {
      final states = <dynamic>[];
      if (setup != null) {
        for (var i = 0; i < iterations; i++) {
          final state = setup();
          states.add(state is Future ? await state : state);
        }
      }

      // Reset and Enable the counter
      ioctlFn(fd, _perfEventIocReset, 0);
      ioctlFn(fd, _perfEventIocEnable, 0);

      // Run workload
      for (var i = 0; i < iterations; i++) {
        if (setup != null) {
          final r = fn(states[i]);
          if (r is Future) {
            await r;
          }
        } else {
          final r = fn();
          if (r is Future) {
            await r;
          }
        }
      }

      // Disable
      ioctlFn(fd, _perfEventIocDisable, 0);

      // Read counter
      final counterBuf = calloc<Uint64>();
      final bytesRead = readFn(fd, counterBuf.cast<Void>(), 8);
      final instructions = bytesRead == 8 ? counterBuf.value : null;
      calloc.free(counterBuf);

      if (instructions == null) {
        return null;
      }

      return InstructionResult(
        instructionsPerIteration: instructions / iterations,
      );
    } catch (_) {
      return null;
    } finally {
      closeFn(fd);
    }
  }
}
