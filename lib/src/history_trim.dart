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

/// Pure helpers for reasoning about benchmark history.
///
/// This library deliberately has no `dart:io` dependency, so that both the
/// VM and stub implementations of the history store can share it.
library;

import 'result.dart';

/// Identifies the benchmark that [r] is a measurement of.
///
/// Two results share a key when they measure the same benchmark on the same
/// platform with the same parameter value, which is what makes them
/// comparable over time.
String historyKey(BenchmarkResult r) {
  final parts = [r.name];
  if (r.platform.isNotEmpty) parts.add(r.platform);
  if (r.parameterValue != null) parts.add(r.parameterValue.toString());
  return parts.join('|');
}

/// Returns [history] with at most [maxEntriesPerBenchmark] entries for each
/// benchmark, keeping the most recent by timestamp.
///
/// Benchmarks are capped independently of each other, keyed by [historyKey],
/// so a suite that runs one benchmark far more often than the others cannot
/// evict their trend data.
///
/// The relative order of the surviving entries is preserved, and [history] is
/// returned unchanged when nothing needs trimming.
///
/// Runs in O(n log n) in the size of the largest benchmark's history.
///
/// It is an error if [maxEntriesPerBenchmark] is less than 1.
List<BenchmarkResult> trimHistory(
  List<BenchmarkResult> history, {
  int maxEntriesPerBenchmark = 100,
}) {
  if (maxEntriesPerBenchmark < 1) {
    throw ArgumentError.value(
      maxEntriesPerBenchmark,
      'maxEntriesPerBenchmark',
      'Must be >= 1',
    );
  }

  final byKey = <String, List<BenchmarkResult>>{};
  for (final r in history) {
    byKey.putIfAbsent(historyKey(r), () => <BenchmarkResult>[]).add(r);
  }
  if (byKey.values.every((v) => v.length <= maxEntriesPerBenchmark)) {
    return history;
  }

  // Identity set: two results with equal field values are still distinct
  // entries and must be kept or dropped independently.
  final keep = Set<BenchmarkResult>.identity();
  for (final entries in byKey.values) {
    if (entries.length <= maxEntriesPerBenchmark) {
      keep.addAll(entries);
      continue;
    }
    final sorted = [...entries]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    keep.addAll(sorted.sublist(sorted.length - maxEntriesPerBenchmark));
  }
  return history.where(keep.contains).toList();
}
