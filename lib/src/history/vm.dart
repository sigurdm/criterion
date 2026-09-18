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

import 'dart:convert';
import 'dart:io';
import '../result.dart';
import '../criterion.dart';
import '../comparison.dart';
import '../history_trim.dart';

/// Manages saving and loading historical benchmark results.
///
/// Writes are atomic: the new contents are written to a sibling temporary file
/// which is then renamed over the target. An interrupted run therefore leaves
/// either the old file or the new one, never a truncated mixture.
///
/// A file that exists but cannot be parsed is treated as precious rather than
/// disposable: it is moved aside to `<path>.corrupt-<timestamp>` and the run
/// continues with no history, so the next save cannot overwrite it.
final class HistoryManager {
  /// The path to the history JSON file.
  final String filePath;

  /// Creates a [HistoryManager].
  HistoryManager(this.filePath);

  /// Loads the history from disk.
  ///
  /// Returns an empty list if the file does not exist.
  ///
  /// If the file exists but cannot be read or parsed, it is renamed to
  /// `<path>.corrupt-<timestamp>`, a warning naming that path is written to
  /// stderr, and an empty list is returned. Benchmarking is worth continuing
  /// without history; silently deleting the history is not.
  Future<List<BenchmarkResult>> load() async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return [];
    }
    try {
      return _decode(await file.readAsString());
    } catch (e) {
      final quarantined = _quarantine(file);
      stderr.writeln('Warning: Failed to load history from $filePath: $e');
      if (quarantined != null) {
        stderr.writeln(
          '         The file has been moved to $quarantined and a fresh '
          'history will be started.',
        );
      }
      return [];
    }
  }

  /// Saves the [history] to disk, atomically.
  ///
  /// At most [maxEntriesPerBenchmark] entries are kept for each benchmark;
  /// the oldest are dropped first. Without a cap the file grows without bound
  /// across runs, and every entry carries its full sample times, class
  /// allocations and CPU profile.
  ///
  /// Failures are reported on stderr rather than thrown, since losing a
  /// history update should not fail an otherwise successful benchmark run.
  Future<void> save(
    List<BenchmarkResult> history, {
    int maxEntriesPerBenchmark = 100,
  }) async {
    final file = File(filePath);
    try {
      await _writeAtomically(
        file,
        _encode(
          trimHistory(history, maxEntriesPerBenchmark: maxEntriesPerBenchmark),
        ),
      );
    } catch (e) {
      stderr.writeln('Warning: Failed to save history to $filePath: $e');
    }
  }

  File _baselineFile(String name) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Baseline name must contain only alphanumeric characters, underscores, or hyphens.',
      );
    }
    final parentDir = File(filePath).parent.path;
    return File('$parentDir/baselines/$name.json');
  }

  /// Saves [results] as a named baseline, atomically.
  ///
  /// It is an error if [name] contains characters other than `[a-zA-Z0-9_-]`.
  Future<void> saveNamedBaseline(
    String name,
    List<BenchmarkResult> results,
  ) async {
    final file = _baselineFile(name);
    try {
      await _writeAtomically(file, _encode(results));
    } catch (e) {
      stderr.writeln(
        'Warning: Failed to save baseline $name to ${file.path}: $e',
      );
    }
  }

  /// Loads the named baseline with [name].
  ///
  /// Returns an empty list if the baseline does not exist.
  ///
  /// If it exists but cannot be parsed it is moved aside as described on
  /// [load], and an empty list is returned.
  ///
  /// It is an error if [name] contains characters other than `[a-zA-Z0-9_-]`.
  Future<List<BenchmarkResult>> loadNamedBaseline(String name) async {
    final file = _baselineFile(name);
    if (!file.existsSync()) {
      return [];
    }
    try {
      return _decode(await file.readAsString());
    } catch (e) {
      final quarantined = _quarantine(file);
      stderr.writeln(
        'Warning: Failed to load baseline $name from ${file.path}: $e',
      );
      if (quarantined != null) {
        stderr.writeln('         The file has been moved to $quarantined.');
      }
      return [];
    }
  }

  static List<BenchmarkResult> _decode(String content) {
    final List<dynamic> jsonList = jsonDecode(content);
    return jsonList
        .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static String _encode(List<BenchmarkResult> results) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(results.map((r) => r.toJson()).toList());

  /// Writes [contents] to [file] via a temporary sibling and a rename.
  ///
  /// The temporary file is created next to [file] so that the rename stays
  /// within one filesystem, which is what makes it atomic. A failed write
  /// leaves the previous contents of [file] untouched.
  static Future<void> _writeAtomically(File file, String contents) async {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final temp = File('${file.path}.tmp-$pid');
    try {
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {
          // Best effort; the original write error is the one worth reporting.
        }
      }
      rethrow;
    }
  }

  /// Moves [file] aside so a later save cannot overwrite it.
  ///
  /// Returns the new path, or `null` if the file could not be moved.
  static String? _quarantine(File file) {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final target = '${file.path}.corrupt-$stamp';
    try {
      file.renameSync(target);
      return target;
    } catch (_) {
      return null;
    }
  }
}

/// Checks for regressions between [current] results and [history].
///
/// Only the most recent historical result for each benchmark is used as the
/// baseline. A benchmark counts as regressed when it got slower by a
/// statistically significant margin that also exceeds [noiseThreshold]; see
/// [compareResults].
///
/// Prints a warning to stdout for each regression, naming [baselineLabel] if
/// one was given.
///
/// Returns the regressing comparisons, newest baseline versus current. The
/// list is empty when [history] is empty or nothing regressed.
List<BenchmarkComparison> checkRegressions({
  required List<BenchmarkResult> current,
  required List<BenchmarkResult> history,
  double noiseThreshold = 0.01,
  String? baselineLabel,
}) {
  if (history.isEmpty) return const [];

  // Group history by benchmark key (name + platform + parameterValue)
  // and find the latest result for each key.
  final latestHistory = <String, BenchmarkResult>{};
  for (final r in history) {
    final key = historyKey(r);
    final existing = latestHistory[key];
    if (existing == null || r.timestamp.isAfter(existing.timestamp)) {
      latestHistory[key] = r;
    }
  }

  final baselineList = latestHistory.values.toList();
  final comparison = compareResults(
    baselineList,
    current,
    noiseThreshold: noiseThreshold,
  );

  for (final r in comparison.regressions) {
    final platStr = r.platform.isNotEmpty ? ' (${r.platform})' : '';
    final paramStr = r.parameterValue != null ? ' [${r.parameterValue}]' : '';
    final baseStr = baselineLabel != null
        ? ' against baseline "$baselineLabel"'
        : '';
    print(
      'WARNING: Regression detected in ${r.name}$platStr$paramStr$baseStr: '
      '${Benchmark.formatDuration(r.time.before)} -> ${Benchmark.formatDuration(r.time.after)} '
      '(+${r.time.percentDiff.toStringAsFixed(2)}%)',
    );
  }

  return comparison.regressions;
}
