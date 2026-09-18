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

/// Manages saving and loading historical benchmark results.
final class HistoryManager {
  /// The path to the history JSON file.
  final String filePath;

  /// Creates a [HistoryManager].
  HistoryManager(this.filePath);

  /// Loads the history from disk.
  ///
  /// Returns an empty list if the file does not exist or fails to load.
  Future<List<BenchmarkResult>> load() async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return [];
    }
    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      stderr.writeln('Warning: Failed to load history from $filePath: $e');
      return [];
    }
  }

  /// Saves the [history] to disk.
  Future<void> save(List<BenchmarkResult> history) async {
    final file = File(filePath);
    try {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(history.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString);
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

  /// Saves [results] as a named baseline.
  ///
  /// It is an error if [name] contains characters other than `[a-zA-Z0-9_-]`.
  Future<void> saveNamedBaseline(
    String name,
    List<BenchmarkResult> results,
  ) async {
    final file = _baselineFile(name);
    try {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(results.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      stderr.writeln(
        'Warning: Failed to save baseline $name to ${file.path}: $e',
      );
    }
  }

  /// Loads the named baseline with [name].
  ///
  /// Returns an empty list if the baseline does not exist or fails to load.
  /// It is an error if [name] contains characters other than `[a-zA-Z0-9_-]`.
  Future<List<BenchmarkResult>> loadNamedBaseline(String name) async {
    final file = _baselineFile(name);
    if (!file.existsSync()) {
      return [];
    }
    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      stderr.writeln(
        'Warning: Failed to load baseline $name from ${file.path}: $e',
      );
      return [];
    }
  }
}

/// Checks for regressions between [current] results and [history].
///
/// Prints warnings to stdout if a regression is detected.
/// Returns `true` if any regressions are detected, `false` otherwise.
bool checkRegressions({
  required List<BenchmarkResult> current,
  required List<BenchmarkResult> history,
  double noiseThreshold = 0.01,
  String? baselineLabel,
}) {
  if (history.isEmpty) return false;

  // Group history by benchmark key (name + platform + parameterValue)
  // and find the latest result for each key.
  final latestHistory = <String, BenchmarkResult>{};
  for (final r in history) {
    final key = _historyKey(r);
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

  return comparison.regressions.isNotEmpty;
}

String _historyKey(BenchmarkResult r) {
  final parts = [r.name];
  if (r.platform.isNotEmpty) parts.add(r.platform);
  if (r.parameterValue != null) parts.add(r.parameterValue.toString());
  return parts.join('::');
}
