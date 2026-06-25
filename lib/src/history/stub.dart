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

import '../result.dart';

/// Stub implementation of HistoryManager when VM/IO is not available.
final class HistoryManager {
  /// The path to the history file (ignored).
  final String filePath;

  /// Creates a [HistoryManager].
  HistoryManager(this.filePath);

  /// Always returns an empty list.
  Future<List<BenchmarkResult>> load() async => [];

  /// No-op.
  Future<void> save(List<BenchmarkResult> history) async {}
}

/// No-op.
void checkRegressions({
  required List<BenchmarkResult> current,
  required List<BenchmarkResult> history,
}) {}
