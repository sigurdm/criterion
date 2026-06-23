// Copyright 2026 Sigurd Meldgaard
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
}

/// A zero-cost compiler-safe live sink to prevent dead-code elimination.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
@pragma('wasm:prefer-inline')
void blackhole(Object? value) {
  Blackhole._sink = value;
}
