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

import 'dart:ffi';
import 'compiler.dart';

typedef GetCyclesFunc = Uint64 Function();
typedef GetCycles = int Function();

/// Provides access to hardware cycle counter.
final class CycleCounter {
  static GetCycles? _getCycles;
  static bool _initialized = false;
  static bool _supported = false;

  /// Initializes the cycle counter by compiling and loading the helper.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final libPath = await CycleCounterCompiler.compile();
      if (libPath == null) return;

      final dylib = DynamicLibrary.open(libPath);
      _getCycles = dylib
          .lookup<NativeFunction<GetCyclesFunc>>('get_cycles')
          .asFunction<GetCycles>();

      if (_getCycles != null && _getCycles!() != 0) {
        _supported = true;
      }
    } catch (e) {
      // Fail silently
    }
  }

  /// Whether cycle counting is supported on this platform.
  static bool get isSupported => _supported;

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
  }) async {
    if (!_supported || _getCycles == null) return null;

    final states = <dynamic>[];
    if (setup != null) {
      for (var i = 0; i < iterations; i++) {
        final state = setup();
        states.add(state is Future ? await state : state);
      }
    }

    final start = _getCycles!();
    if (setup != null) {
      for (var i = 0; i < iterations; i++) {
        final r = fn(states[i]);
        if (r is Future) await r;
      }
    } else {
      for (var i = 0; i < iterations; i++) {
        final r = fn();
        if (r is Future) await r;
      }
    }
    final end = _getCycles!();

    final diff = end - start;
    // Handle rare negative diff due to signed representation if it wrapped.
    // (Though 64-bit wrap is extremely rare).
    final actualDiff = diff < 0
        ? (BigInt.from(end) - BigInt.from(start)).toUnsigned(64).toDouble()
        : diff.toDouble();

    return actualDiff / iterations;
  }
}
