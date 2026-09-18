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
import '../batch_size.dart';
import 'compiler.dart';

typedef GetCyclesFunc = Uint64 Function();
typedef GetCycles = int Function();

@Native<Uint64 Function()>(symbol: 'get_cycles')
external int _nativeGetCycles();

/// Native CPU cycle counter for x86_64 and ARM64.
final class CycleCounter {
  static DynamicLibrary? _dylib;
  static GetCycles? _getCycles;
  static bool _supported = false;
  static Future<void>? _initFuture;

  /// Initializes the CPU cycle counter if native compiler toolchains exist.
  static Future<void> init() => _initFuture ??= _doInit();

  static Future<void> _doInit() async {
    try {
      final c = _nativeGetCycles();
      if (c > 0) {
        _getCycles = _nativeGetCycles;
        _supported = true;
        return;
      }
    } catch (_) {
      // Fall back to runtime compilation.
    }

    final libPath = await CycleCounterCompiler.compile();
    if (libPath != null) {
      try {
        _dylib = DynamicLibrary.open(libPath);
        _getCycles = _dylib!
            .lookup<NativeFunction<GetCyclesFunc>>('get_cycles')
            .asFunction<GetCycles>();
        // Test read
        final c = _getCycles!();
        _supported = c > 0;
      } catch (_) {
        _supported = false;
      }
    }
  }

  /// Whether the CPU cycle counter is supported on this machine.
  static bool get isSupported => _supported && _getCycles != null;

  /// Reads the current value of the cycle counter.
  ///
  /// Returns 0 if not supported or not initialized.
  static int read() {
    if (!_supported || _getCycles == null) return 0;
    return _getCycles!();
  }

  /// Measures the average cycles per iteration for [fn].
  static Future<double?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    FutureOr<void> Function(dynamic)? teardown,
    BatchSize? batchSize,
  }) async {
    await init();
    if (!_supported || _getCycles == null) return null;

    final mode =
        batchSize ??
        (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
    double totalDiff = 0.0;
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
        final start = _getCycles!();
        if (setup != null) {
          for (var i = 0; i < batch; i++) {
            final r = fn(states[i]);
            if (r is Future) await r;
          }
        } else {
          for (var i = 0; i < batch; i++) {
            final r = fn();
            if (r is Future) await r;
          }
        }
        final end = _getCycles!();

        final diff = end - start;
        final actualDiff = diff < 0 ? 0.0 : diff.toDouble();

        totalDiff += actualDiff;
      } finally {
        if (teardown != null) {
          for (var i = 0; i < states.length; i++) {
            final res = teardown(states[i]);
            if (res is Future) await res;
          }
        }
      }
      remaining -= batch;
    }

    return totalDiff / iterations;
  }
}
