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

/// A compiler-recognized zero-cost live sink to prevent dead-code elimination.
///
/// Passing a value to [blackhole] ensures that the compiler treats the value's
/// computation as live, preventing tree-shaking and dead-code elimination,
/// while introducing virtually zero runtime execution overhead.
final class Blackhole {
  static dynamic _sink;

  /// A public static setter to allow the harness runner to implicitly consume
  /// benchmark returned values in the timing loops.
  static set sink(Object? value) => _sink = value;

  /// The last value consumed by [sink].
  static Object? get sink => _sink;

  /// Consumes the given [value] to prevent dead-code elimination.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  @pragma('wasm:prefer-inline')
  void consume(Object? value) {
    _sink = value;
  }

  /// An opaque guard that convinces compiler static analyses (such as TFA)
  /// that [_sink] is read, preventing it from being tree-shaken as write-only.
  ///
  /// Automatically invoked inside `Criterion.run` to ensure the sink is live.
  @pragma('vm:never-inline')
  @pragma('dart2js:never-inline')
  @pragma('wasm:never-inline')
  static void preventDCE() {
    // Opaque condition that is always false at runtime but unresolvable
    // at compile-time.
    if (int.tryParse('0') == 1) {
      print(_sink);
    }
  }

  /// A value that is always `0` at runtime, but that no compiler can fold to a
  /// constant because it is produced by a non-const call in a lazily
  /// initialized static field.
  ///
  /// Reading it costs a static field load (plus an initialization check), which
  /// is what makes [blackbox] cheap.
  static final int _opaqueZero = int.parse('0');

  /// Passes [value] through an opaque runtime barrier that prevents the compiler
  /// from performing constant-folding, dead-code elimination, or loop-invariant
  /// code motion on inputs to benchmarked code.
  ///
  /// Unlike [consume] (which discards the value into a sink), [blackbox]
  /// returns [value] unmodified while forcing the optimizing compiler (AOT/JIT/dart2js)
  /// to treat both the input value and its origin as opaque and dynamic.
  ///
  /// Performance considerations:
  /// * The barrier is a non-inlinable call, a store to a static field and a
  ///   comparison against [_opaqueZero]; it costs a few nanoseconds per call.
  ///   It is deliberately cheap, but it is not free, so prefer [consume] or
  ///   [blackhole] when only the *result* needs to be kept alive.
  ///
  /// Example:
  /// ```dart
  /// c.bench('calculate', () {
  ///   // Prevents the compiler from hoisting `blackbox(42)` out of the loop
  ///   // or pre-computing `myFunction(42)` at compile-time.
  ///   final input = blackbox(42);
  ///   myFunction(input);
  /// });
  /// ```
  @pragma('vm:never-inline')
  @pragma('dart2js:noInline')
  static T blackbox<T>(T value) {
    _sink = value;
    if (_opaqueZero != 0) {
      return _sink as T;
    }
    return value;
  }
}

/// Passes [value] through an opaque runtime barrier that prevents the compiler
/// from performing constant-folding, dead-code elimination, or loop-invariant
/// code motion on inputs to benchmarked code.
///
/// Unlike [blackhole] (which discards the value into a sink), [blackbox]
/// returns [value] unmodified while forcing the optimizing compiler (AOT/JIT/dart2js)
/// to treat both the input value and its origin as opaque and dynamic.
///
/// Example:
/// ```dart
/// c.bench('calculate', () {
///   // Prevents the compiler from hoisting `blackbox(42)` out of the loop
///   // or pre-computing `myFunction(42)` at compile-time.
///   final input = blackbox(42);
///   myFunction(input);
/// });
/// ```
@pragma('vm:never-inline')
@pragma('dart2js:noInline')
T blackbox<T>(T value) => Blackhole.blackbox<T>(value);

/// A zero-cost compiler-safe live sink to prevent dead-code elimination.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
@pragma('wasm:prefer-inline')
void blackhole(Object? value) {
  Blackhole._sink = value;
}
