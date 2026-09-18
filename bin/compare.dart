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

import "dart:io";
import "package:args/args.dart";
import "package:criterion/criterion.dart";

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'noise-threshold',
      defaultsTo: '0.01',
      help:
          'Relative noise threshold for regression detection (e.g. 0.01 for 1%).',
    )
    ..addFlag(
      'fail-on-regression',
      defaultsTo: false,
      negatable: false,
      help: 'Exit with non-zero exit code if a regression is detected.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Usage: compare [options] <before.json> <after.json>');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (parsed['help'] as bool) {
    stdout.writeln('Usage: compare [options] <before.json> <after.json>');
    stdout.writeln(parser.usage);
    return;
  }

  if (parsed.rest.length != 2) {
    stderr.writeln('Usage: compare [options] <before.json> <after.json>');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final noiseThreshold = double.tryParse(parsed['noise-threshold'] as String);
  if (noiseThreshold == null || noiseThreshold < 0 || noiseThreshold.isNaN) {
    stderr.writeln(
      'Error: Invalid --noise-threshold value: ${parsed['noise-threshold']}',
    );
    exitCode = 64;
    return;
  }
  final failOnRegression = parsed['fail-on-regression'] as bool;

  final beforeFile = File(parsed.rest[0]);
  final afterFile = File(parsed.rest[1]);

  if (!await beforeFile.exists()) {
    stderr.writeln('Error: File not found: ${beforeFile.path}');
    exitCode = 1;
    return;
  }
  if (!await afterFile.exists()) {
    stderr.writeln('Error: File not found: ${afterFile.path}');
    exitCode = 1;
    return;
  }

  List<BenchmarkResult> beforeResults;
  List<BenchmarkResult> afterResults;

  try {
    beforeResults = loadResults(await beforeFile.readAsString());
  } catch (e) {
    stderr.writeln('Error parsing ${beforeFile.path}: $e');
    exitCode = 1;
    return;
  }

  try {
    afterResults = loadResults(await afterFile.readAsString());
  } catch (e) {
    stderr.writeln('Error parsing ${afterFile.path}: $e');
    exitCode = 1;
    return;
  }

  final comparison = compareResults(
    beforeResults,
    afterResults,
    noiseThreshold: noiseThreshold,
  );
  stdout.write(comparison.toMarkdownTable());

  if (failOnRegression && comparison.regressions.isNotEmpty) {
    stderr.writeln(
      "Error: Regressions detected in ${comparison.regressions.length} benchmark(s).",
    );
    exitCode = 1;
  }
}
