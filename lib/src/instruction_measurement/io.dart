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
import '../batch_size.dart';
import '../result.dart';

// Architecture-specific syscall number for perf_event_open (64-bit Linux only).
final int? _sysPerfEventOpen = switch (Abi.current()) {
  Abi.linuxX64 => 298,
  Abi.linuxArm64 || Abi.linuxRiscv64 => 241,
  _ => null,
};

// ioctl constants
const int _perfEventIocEnable = 0x2400;
const int _perfEventIocDisable = 0x2401;
const int _perfEventIocReset = 0x2403;

// read_format: PERF_FORMAT_TOTAL_TIME_ENABLED (1) | PERF_FORMAT_TOTAL_TIME_RUNNING (2)
const int _perfFormatTotalTimeEnabledAndRunning = 3;

// libc mapping
final DynamicLibrary _libc = DynamicLibrary.process();

typedef _SyscallNative =
    Long Function(
      Long number,
      VarArgs<(Pointer<Void>, Int32, Int32, Int32, UnsignedLong)>,
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

typedef _IoctlNative =
    Int32 Function(Int32 fd, UnsignedLong request, VarArgs<(Long,)>);
typedef _IoctlDart = int Function(int fd, int request, int arg);
final _IoctlDart? _ioctl = () {
  try {
    return _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
  } catch (_) {
    return null;
  }
}();

typedef _ReadNative = Long Function(Int32 fd, Pointer<Void> buf, Size count);
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
  static final bool isSupported = _checkSupported();

  static Pointer<Uint8> _allocatePerfAttr() {
    const attrSize = 120;
    final attr = calloc<Uint8>(attrSize);
    // type (uint32) at offset 0 -> 0 (PERF_TYPE_HARDWARE)
    attr.cast<Uint32>().value = 0;
    // size (uint32) at offset 4 -> attrSize (120)
    (attr + 4).cast<Uint32>().value = attrSize;
    // config (uint64) at offset 8 -> 0 (PERF_COUNT_HW_INSTRUCTIONS)
    (attr + 8).cast<Uint64>().value = 0;
    // read_format (uint64) at offset 32 -> PERF_FORMAT_TOTAL_TIME_ENABLED|RUNNING
    (attr + 32).cast<Uint64>().value = _perfFormatTotalTimeEnabledAndRunning;
    // flags (uint64) at offset 40 -> 97 (disabled=1, exclude_kernel=1, exclude_hv=1)
    (attr + 40).cast<Uint64>().value = 97;
    return attr;
  }

  static bool _checkSupported() {
    if (!Platform.isLinux) return false;
    final sysOpen = _sysPerfEventOpen;
    if (sysOpen == null) return false;
    if (_syscall == null || _ioctl == null || _read == null || _close == null) {
      return false;
    }

    final syscallFn = _syscall!;
    final ioctlFn = _ioctl!;
    final readFn = _read!;
    final closeFn = _close!;

    final attr = _allocatePerfAttr();
    // Open the event (pid = 0 for calling thread, cpu = -1 for any CPU)
    final fd = syscallFn(sysOpen, attr.cast<Void>(), 0, -1, -1, 0);
    calloc.free(attr);

    if (fd < 0) {
      return false;
    }

    try {
      if (ioctlFn(fd, _perfEventIocReset, 0) != 0) return false;
      if (ioctlFn(fd, _perfEventIocEnable, 0) != 0) return false;

      var s = 0;
      for (var i = 0; i < 1000; i++) {
        s += i;
      }
      if (s == 0) return false;

      ioctlFn(fd, _perfEventIocDisable, 0);

      final counterBuf = calloc<Uint64>(3);
      final bytesRead = readFn(fd, counterBuf.cast<Void>(), 24);
      final instructions = bytesRead == 24 ? counterBuf[0] : null;
      calloc.free(counterBuf);

      return instructions != null && instructions > 0;
    } catch (_) {
      return false;
    } finally {
      closeFn(fd);
    }
  }

  /// Measures CPU instructions for [fn] over [iterations] runs.
  ///
  /// Returns `null` if instruction counting is not supported or fails.
  static Future<InstructionResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    FutureOr<void> Function(dynamic)? teardown,
    BatchSize? batchSize,
  }) async {
    if (!isSupported) return null;

    final syscallFn = _syscall!;
    final ioctlFn = _ioctl!;
    final readFn = _read!;
    final closeFn = _close!;

    final attr = _allocatePerfAttr();
    // Open the event (pid = 0 for calling thread, cpu = -1 for any CPU)
    final fd = syscallFn(_sysPerfEventOpen!, attr.cast<Void>(), 0, -1, -1, 0);
    calloc.free(attr);

    if (fd < 0) {
      return null;
    }

    try {
      final mode =
          batchSize ??
          (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
      ioctlFn(fd, _perfEventIocReset, 0);

      var remaining = iterations;
      while (remaining > 0) {
        final batch = mode.batchSizeFor(remaining);
        final states = <dynamic>[];
        if (setup != null) {
          for (var i = 0; i < batch; i++) {
            final state = setup();
            states.add(state is Future ? await state : state);
          }
        }

        try {
          // Enable counter during function execution
          ioctlFn(fd, _perfEventIocEnable, 0);

          // Run workload
          for (var i = 0; i < batch; i++) {
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
        } finally {
          // Disable counter while preparing next batch
          ioctlFn(fd, _perfEventIocDisable, 0);

          if (teardown != null) {
            for (var i = 0; i < states.length; i++) {
              final res = teardown(states[i]);
              if (res is Future) await res;
            }
          }
        }

        remaining -= batch;
      }

      // Read counter: [value, time_enabled, time_running]
      final counterBuf = calloc<Uint64>(3);
      final bytesRead = readFn(fd, counterBuf.cast<Void>(), 24);
      int? rawCount;
      int timeEnabled = 0;
      int timeRunning = 0;
      if (bytesRead == 24) {
        rawCount = counterBuf[0];
        timeEnabled = counterBuf[1];
        timeRunning = counterBuf[2];
      }
      calloc.free(counterBuf);

      if (rawCount == null || timeRunning <= 0) {
        return null;
      }

      var scaledInstructions = rawCount.toDouble();
      if (timeRunning < timeEnabled) {
        final ratio = timeEnabled / timeRunning;
        scaledInstructions *= ratio;
        stderr.writeln(
          'Warning: perf hardware instruction counter was multiplexed '
          '(running ${timeRunning}ns / enabled ${timeEnabled}ns); '
          'scaled count by ${ratio.toStringAsFixed(2)}x.',
        );
      }

      return InstructionResult(
        instructionsPerIteration: scaledInstructions / iterations,
      );
    } catch (_) {
      return null;
    } finally {
      closeFn(fd);
    }
  }
}
