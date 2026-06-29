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

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'history',
      abbr: 'h',
      defaultsTo: 'benchmark/criterion_history.json',
      help: 'Path to history JSON file.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'benchmark/report',
      help: 'Output directory for HTML trend report.',
    )
    ..addFlag('help', negatable: false, help: 'Show usage instructions.');

  final ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: $e\n');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (argResults['help'] as bool) {
    stdout.writeln('Usage: dart run criterion:graph [options]\n');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final historyPath = argResults['history'] as String;
  final historyFile = File(historyPath);
  if (!await historyFile.exists()) {
    stderr.writeln('Error: History file not found at $historyPath');
    exit(1);
  }

  final history = loadResults(await historyFile.readAsString());
  if (history.isEmpty) {
    stdout.writeln('No historical benchmark results found in $historyPath');
    exit(0);
  }

  // Group by benchmark name and platform
  final groups = <String, List<BenchmarkResult>>{};
  for (final r in history) {
    final key = r.platform.isNotEmpty ? '${r.name} (${r.platform})' : r.name;
    groups.putIfAbsent(key, () => []).add(r);
  }

  // Output Markdown Trend Table to stdout
  final sb = StringBuffer();
  sb.writeln('# Historical Benchmark Trends\n');
  for (final entry in groups.entries) {
    final key = entry.key;
    final runs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    sb.writeln('## $key\n');
    sb.writeln('| Commit | Date | Mean Time | Delta vs Prev |');
    sb.writeln('| --- | --- | --- | --- |');

    double? prevMean;
    for (final r in runs) {
      final commitStr = r.gitCommit != null ? r.gitCommit!.shortHash : 'N/A';
      final dateStr = r.timestamp.toIso8601String().split('T').first;
      final meanStr = Benchmark.formatDuration(r.primary.mean);
      String deltaStr = '-';
      if (prevMean != null && prevMean > 0) {
        final diff = r.primary.mean - prevMean;
        final pct = (diff / prevMean) * 100;
        final sign = diff > 0 ? '+' : '';
        deltaStr = '$sign${pct.toStringAsFixed(2)}%';
      }
      prevMean = r.primary.mean;
      sb.writeln('| $commitStr | $dateStr | $meanStr | $deltaStr |');
    }
    sb.writeln('');
  }

  stdout.write(sb.toString());

  // Generate HTML Report with historical timeline trends
  final outputDir = argResults['output'] as String;
  final config = CriterionConfig(
    reportDir: outputDir,
    generateHtmlReport: true,
    exportJson: false,
  );

  // Take latest run per key as representative current results
  final latestResults = <BenchmarkResult>[];
  for (final runs in groups.values) {
    if (runs.isNotEmpty) {
      latestResults.add(runs.last);
    }
  }

  await ReportGenerator(config).generate(latestResults, history: history);
}
