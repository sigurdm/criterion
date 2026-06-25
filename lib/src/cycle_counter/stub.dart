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

/// Stub implementation of CycleCounter when VM/FFI is not available.
final class CycleCounter {
  /// No-op.
  static Future<void> init() async {}

  /// Always returns false.
  static bool get isSupported => false;

  /// Always returns 0.
  static int read() => 0;

  /// Always returns null.
  static Future<double?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
  }) async => null;
}
