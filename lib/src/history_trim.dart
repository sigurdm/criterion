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

/// Returns a copy of [r] with bulky diagnostic fields stripped for history
/// storage.
///
/// Historical trend charts only need summary statistics (`mean`, `meanCI`,
/// `timestamp`, `gitCommit`), while [`checkRegressions`] only needs
/// `sampleTimes` (and `noOp`) on the single most recent historical entry for
/// each benchmark.
///
/// When [keepSamples] is `true`, `sampleTimes` and `noOp` are preserved so the
/// entry can serve as a bootstrap regression baseline, while `cpuProfile` and
/// `memory.classAllocations` are stripped. When [keepSamples] is `false`,
/// `sampleTimes` and `noOp` are also stripped.
///
/// Returns [r] unchanged when it already has none of the stripped fields.
BenchmarkResult slimHistoryEntry(
  BenchmarkResult r, {
  required bool keepSamples,
}) {
  final slimPrimary = _slimMeasurement(r.primary, keepSamples: keepSamples);
  final MeasurementResult? slimNoOp;
  if (!keepSamples || r.noOp == null) {
    slimNoOp = null;
  } else {
    slimNoOp = _slimMeasurement(r.noOp!, keepSamples: true);
  }

  if (identical(slimPrimary, r.primary) && identical(slimNoOp, r.noOp)) {
    return r;
  }

  return BenchmarkResult(
    name: r.name,
    iterations: r.iterations,
    primary: slimPrimary,
    noOp: slimNoOp,
    net: r.net,
    hostEnvironment: r.hostEnvironment,
    platform: r.platform,
    timestamp: r.timestamp,
    variantGroup: r.variantGroup,
    variantName: r.variantName,
    parameterGroup: r.parameterGroup,
    parameterValue: r.parameterValue,
    throughput: r.throughput,
    gitCommit: r.gitCommit,
  );
}

MeasurementResult _slimMeasurement(
  MeasurementResult m, {
  required bool keepSamples,
}) {
  final needDropSamples = !keepSamples && m.sampleTimes.isNotEmpty;
  final needDropProfile = m.cpuProfile != null;
  final needDropClassAllocations = m.memory?.classAllocations != null;

  if (!needDropSamples && !needDropProfile && !needDropClassAllocations) {
    return m;
  }

  final slimMemory = m.memory == null
      ? null
      : (needDropClassAllocations
            ? MemoryResult(
                allocatedBytesPerIteration:
                    m.memory!.allocatedBytesPerIteration,
                allocatedObjectsPerIteration:
                    m.memory!.allocatedObjectsPerIteration,
                rssDeltaBytes: m.memory!.rssDeltaBytes,
              )
            : m.memory);

  return MeasurementResult(
    sampleTimes: keepSamples ? m.sampleTimes : const [],
    mean: m.mean,
    median: m.median,
    stdDev: m.stdDev,
    meanCI: m.meanCI,
    medianCI: m.medianCI,
    outliers: m.outliers,
    memory: slimMemory,
    instructions: m.instructions,
    cpuProfile: null,
    cyclesPerIteration: m.cyclesPerIteration,
  );
}

/// Returns [history] with at most [maxEntriesPerBenchmark] entries for each
/// benchmark, keeping the most recent by timestamp, and slims entries via
/// [slimHistoryEntry].
///
/// Only the single most recent entry per benchmark retains its raw
/// `sampleTimes` (for two-sample bootstrap regression checks); all older
/// entries have `sampleTimes` and `noOp` stripped, and all entries have
/// `cpuProfile` and `memory.classAllocations` stripped.
///
/// Benchmarks are capped independently of each other, keyed by [historyKey],
/// so a suite that runs one benchmark far more often than the others cannot
/// evict their trend data.
///
/// The relative order of the surviving entries is preserved, and [history] is
/// returned unchanged when nothing needs trimming or slimming.
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

  // Identity sets: two results with equal field values are still distinct
  // entries and must be kept, slimmed, or dropped independently.
  final keep = Set<BenchmarkResult>.identity();
  final newestPerKey = Set<BenchmarkResult>.identity();

  for (final entries in byKey.values) {
    final sorted = [...entries]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (sorted.isNotEmpty) {
      newestPerKey.add(sorted.last);
    }
    if (sorted.length <= maxEntriesPerBenchmark) {
      keep.addAll(entries);
    } else {
      keep.addAll(sorted.sublist(sorted.length - maxEntriesPerBenchmark));
    }
  }

  var changed = keep.length != history.length;
  final result = <BenchmarkResult>[];
  for (final r in history) {
    if (!keep.contains(r)) continue;
    final slimmed = slimHistoryEntry(r, keepSamples: newestPerKey.contains(r));
    if (!identical(slimmed, r)) {
      changed = true;
    }
    result.add(slimmed);
  }

  return changed ? result : history;
}
