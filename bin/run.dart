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

import 'package:args/args.dart';
import 'package:criterion/criterion.dart';
import 'package:criterion/src/dart_environment.dart' as env_helpers;
import 'package:criterion/src/report_generator.dart';
import 'package:node_preamble/preamble.dart' as node_preamble;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addMultiOption(
      'flavor',
      abbr: 'f',
      allowed: ['jit', 'aot', 'js', 'wasm'],
      defaultsTo: ['aot'],
      help: 'The flavor(s) to run the benchmark in.',
    )
    ..addFlag('json', help: 'Output aggregated JSON results to stdout.')
    ..addMultiOption('compiler-flag', help: 'Extra compiler flags.')
    ..addMultiOption('vm-flag', help: 'Extra VM/Node flags.')
    ..addOption(
      'filter',
      abbr: 'k',
      help: 'Run only benchmarks matching the given regular expression.',
    )
    ..addFlag(
      'quick',
      abbr: 'q',
      negatable: false,
      help: 'Run a fast timing-only pass with reduced warmup and sample count.',
    )
    ..addOption('samples', help: 'Override number of samples per benchmark.')
    ..addOption(
      'warmup-time',
      help: 'Override warmup duration in milliseconds.',
    )
    ..addFlag(
      'no-html',
      negatable: false,
      help: 'Disable HTML report generation.',
    )
    ..addFlag(
      'timing-only',
      negatable: false,
      help: 'Skip memory, instruction, and CPU cycle measurement passes.',
    )
    ..addFlag(
      'all-metrics',
      negatable: false,
      help:
          'Enable memory, instruction, and CPU cycle measurement. Each adds an '
          'extra run of every benchmark function.',
    )
    ..addFlag(
      'memory',
      negatable: false,
      help: 'Enable memory allocation measurement.',
    )
    ..addFlag(
      'instructions',
      negatable: false,
      help: 'Enable hardware instruction measurement.',
    )
    ..addFlag('cycles', negatable: false, help: 'Enable CPU cycle measurement.')
    ..addFlag(
      'no-memory',
      negatable: false,
      help: 'Skip memory allocation measurement.',
    )
    ..addFlag(
      'no-instructions',
      negatable: false,
      help: 'Skip hardware instruction measurement.',
    )
    ..addFlag(
      'no-cycles',
      negatable: false,
      help: 'Skip CPU cycle measurement.',
    )
    ..addOption(
      'save-baseline',
      help: 'Save results as a named baseline for future comparisons.',
    )
    ..addOption(
      'baseline',
      help: 'Compare results against a previously saved named baseline.',
    )
    ..addFlag(
      'fail-on-regression',
      negatable: false,
      help: 'Exit with non-zero exit code if a regression is detected.',
    )
    ..addOption(
      'noise-threshold',
      help: 'Relative noise threshold for regression detection (e.g. 0.01).',
    );

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print(e);
    print(parser.usage);
    exitCode = 1;
    return;
  }

  final targetFiles = <File>[];
  if (results.rest.isEmpty) {
    final benchDir = Directory('benchmark');
    if (benchDir.existsSync()) {
      for (final entity in benchDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          try {
            if (entity.readAsStringSync().contains('main(')) {
              targetFiles.add(entity);
            }
          } catch (_) {}
        }
      }
      targetFiles.sort((a, b) => a.path.compareTo(b.path));
    }
    if (targetFiles.isEmpty) {
      print('Usage: dart run criterion:run [options] <benchmark_file.dart>');
      print(parser.usage);
      exitCode = 1;
      return;
    }
  } else if (FileSystemEntity.isDirectorySync(results.rest.first)) {
    final dir = Directory(results.rest.first);
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        try {
          if (entity.readAsStringSync().contains('main(')) {
            targetFiles.add(entity);
          }
        } catch (_) {}
      }
    }
    targetFiles.sort((a, b) => a.path.compareTo(b.path));
    if (targetFiles.isEmpty) {
      print(
        'Error: No runnable benchmark files found in directory: ${results.rest.first}',
      );
      exitCode = 1;
      return;
    }
  } else {
    for (final targetPath in results.rest) {
      final targetFile = File(targetPath);
      if (!targetFile.existsSync()) {
        print('Error: Target file does not exist: $targetPath');
        exitCode = 1;
        return;
      }
      targetFiles.add(targetFile);
    }
  }

  final flavors = results['flavor'] as List<String>;
  final isJson = results['json'] as bool;
  final compilerFlags = results['compiler-flag'] as List<String>;
  final vmFlags = results['vm-flag'] as List<String>;
  final filter = results['filter'] as String?;
  final quick = results['quick'] as bool;
  final samples = results['samples'] != null
      ? int.tryParse(results['samples'] as String)
      : null;
  final warmupTime = results['warmup-time'] != null
      ? int.tryParse(results['warmup-time'] as String)
      : null;
  final noHtml = results['no-html'] as bool;
  final timingOnly = results['timing-only'] as bool;
  final allMetrics = results['all-metrics'] as bool;
  final memory = results['memory'] as bool;
  final instructions = results['instructions'] as bool;
  final cycles = results['cycles'] as bool;
  final noMemory = results['no-memory'] as bool;
  final noInstructions = results['no-instructions'] as bool;
  final noCycles = results['no-cycles'] as bool;
  final saveBaseline = results['save-baseline'] as String?;
  final baseline = results['baseline'] as String?;
  final failOnRegression = results['fail-on-regression'] as bool;
  final noiseThreshold = results['noise-threshold'] != null
      ? double.tryParse(results['noise-threshold'] as String)
      : null;

  final dartPath = Platform.resolvedExecutable;
  final os = Platform.operatingSystem;
  final sdkVersion = Platform.version.split(' ').first;

  final tempDir = Directory.systemTemp.createTempSync('criterion_run_');

  final aggregatedJsonResults = <dynamic>[];
  final collectedFlavorResults = <BenchmarkResult>[];
  final defaultResultsFile = File('benchmark/report/results.json');

  final hasMultipleRuns =
      flavors.length > 1 ||
      targetFiles.length > 1 ||
      flavors.contains('js') ||
      flavors.contains('wasm');

  try {
    var runCounter = 0;
    for (final targetFile in targetFiles) {
      final targetPath = targetFile.path;

      for (final flavor in flavors) {
        runCounter++;
        if (!isJson && hasMultipleRuns && defaultResultsFile.existsSync()) {
          defaultResultsFile.deleteSync();
        }

        final countBeforeFlavor = collectedFlavorResults.length;

        if (!isJson) {
          if (targetFiles.length > 1) {
            print('=== Running $targetPath [$flavor] ===');
          } else {
            print('=== Running flavor: $flavor ===');
          }
        }

        final defines = env_helpers.dartDefineFlags(
          platform: flavor,
          os: os,
          dartSdkVersion: sdkVersion,
          json: isJson,
          filter: filter,
          quick: quick,
          samples: samples,
          warmupMs: warmupTime,
          noHtml: noHtml,
          timingOnly: timingOnly,
          allMetrics: allMetrics,
          memory: memory,
          instructions: instructions,
          cycles: cycles,
          noMemory: noMemory,
          noInstructions: noInstructions,
          noCycles: noCycles,
          saveBaseline: saveBaseline,
          baseline: baseline,
          failOnRegression: failOnRegression,
          noiseThreshold: noiseThreshold,
        );

        final defineFlags = [
          ...defines,
          if (!isJson && hasMultipleRuns)
            '--define=CRITERION_EMIT_RESULTS_MARKER=true',
        ];

        if (flavor == 'jit') {
          final processArgs = [...vmFlags, ...defineFlags, targetPath];
          if (!await _runProcess(
            dartPath,
            processArgs,
            isJson,
            aggregatedJsonResults,
            collectedFlavorResults,
          )) {
            return;
          }
        } else if (flavor == 'aot') {
          final tempExePath = '${tempDir.path}/temp_aot_$runCounter.exe';
          if (!isJson) {
            print('Compiling to AOT...');
          }
          final compileArgs = [
            'compile',
            'exe',
            ...compilerFlags,
            ...defineFlags,
            targetPath,
            '-o',
            tempExePath,
          ];
          final compileResult = await Process.run(dartPath, compileArgs);
          if (compileResult.exitCode != 0) {
            _printCompileError(compileResult);
            exitCode = compileResult.exitCode;
            return;
          }
          if (!await _runProcess(
            tempExePath,
            [],
            isJson,
            aggregatedJsonResults,
            collectedFlavorResults,
          )) {
            return;
          }
        } else if (flavor == 'js') {
          final tempJsPath = '${tempDir.path}/temp_js_$runCounter.js';
          if (!isJson) {
            print('Compiling to JS...');
          }
          final compileArgs = [
            'compile',
            'js',
            ...compilerFlags,
            ...defineFlags,
            targetPath,
            '-o',
            tempJsPath,
          ];
          final compileResult = await Process.run(dartPath, compileArgs);
          if (compileResult.exitCode != 0) {
            _printCompileError(compileResult);
            exitCode = compileResult.exitCode;
            return;
          }

          // Prepend preamble
          final jsFile = File(tempJsPath);
          final jsContent = jsFile.readAsStringSync();
          final preamble = node_preamble.getPreamble();
          jsFile.writeAsStringSync('$preamble\n$jsContent');

          if (!await _runProcess(
            'node',
            [...vmFlags, tempJsPath],
            isJson,
            aggregatedJsonResults,
            collectedFlavorResults,
          )) {
            return;
          }
        } else if (flavor == 'wasm') {
          final tempWasmPath = '${tempDir.path}/temp_wasm_$runCounter.wasm';
          final tempMjsPath = '${tempDir.path}/temp_wasm_$runCounter.mjs';
          final tempRunnerPath =
              '${tempDir.path}/temp_wasm_runner_$runCounter.mjs';

          if (!isJson) {
            print('Compiling to WASM...');
          }
          final compileArgs = [
            'compile',
            'wasm',
            ...compilerFlags,
            ...defineFlags,
            targetPath,
            '-o',
            tempWasmPath,
          ];
          final compileResult = await Process.run(dartPath, compileArgs);
          if (compileResult.exitCode != 0) {
            _printCompileError(compileResult);
            exitCode = compileResult.exitCode;
            return;
          }

          // Create the WASM runner script
          final runnerContent =
              '''
import { compile } from ${jsonEncode(Uri.file(tempMjsPath).toString())};
import { readFileSync } from 'fs';
import { argv } from 'process';

const bytes = readFileSync(${jsonEncode(tempWasmPath)});
const compiled = await compile(bytes);
const instance = await compiled.instantiate();
const dartArgs = argv.slice(2);
instance.invokeMain(...dartArgs);
''';
          File(tempRunnerPath).writeAsStringSync(runnerContent);

          if (!await _runProcess(
            'node',
            [...vmFlags, tempRunnerPath],
            isJson,
            aggregatedJsonResults,
            collectedFlavorResults,
          )) {
            return;
          }
        }

        if (!isJson && hasMultipleRuns && defaultResultsFile.existsSync()) {
          if (collectedFlavorResults.length == countBeforeFlavor) {
            final jsonContent = defaultResultsFile.readAsStringSync();
            collectedFlavorResults.addAll(loadResults(jsonContent));
          }
          defaultResultsFile.deleteSync();
        }
      }
    }

    if (!isJson && hasMultipleRuns && collectedFlavorResults.isNotEmpty) {
      final generator = ReportGenerator(
        CriterionConfig(
          reportDir: 'benchmark/report',
          exportJson: true,
          generateHtmlReport: !noHtml,
        ),
      );
      await generator.generate(collectedFlavorResults);
    }

    if (isJson) {
      print(jsonEncode(aggregatedJsonResults));
    }
  } finally {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (e) {
      if (!isJson) {
        print('Warning: Failed to clean up temp directory ${tempDir.path}: $e');
      }
    }
  }
}

void _printCompileError(ProcessResult result) {
  print('Compilation failed:');
  print(result.stdout);
  print(result.stderr);
}

Future<bool> _runProcess(
  String executable,
  List<String> arguments,
  bool isJson,
  List<dynamic> aggregatedResults, [
  List<BenchmarkResult>? collectedFlavorResults,
]) async {
  if (isJson) {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      print('Execution failed with exit code ${result.exitCode}');
      print(result.stdout);
      print(result.stderr);
      exitCode = result.exitCode;
      return false;
    }
    try {
      final lines = (result.stdout as String).split('\n');
      var foundAny = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          try {
            final parsed = jsonDecode(trimmed);
            if (parsed is List &&
                parsed.every(
                  (e) =>
                      e is Map<String, dynamic> &&
                      e.containsKey('name') &&
                      e.containsKey('primary'),
                )) {
              aggregatedResults.addAll(parsed);
              foundAny = true;
            }
          } catch (_) {
            // Not valid JSON, continue
          }
        }
      }
      if (!foundAny) {
        throw FormatException('Could not find JSON array in output');
      }
      return true;
    } catch (e) {
      print('Failed to parse JSON output from process: $e');
      print('Output was:');
      print(result.stdout);
      exitCode = 1;
      return false;
    }
  } else {
    final process = await Process.start(executable, arguments);
    final stderrFuture = process.stderr.listen(stderr.add).asFuture<void>();
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('__CRITERION_RESULTS_JSON__:')) {
        final jsonSuffix = line.substring('__CRITERION_RESULTS_JSON__:'.length);
        collectedFlavorResults?.addAll(loadResults(jsonSuffix));
      } else {
        stdout.writeln(line);
      }
    }
    await stderrFuture;
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
      return false;
    }
    return true;
  }
}
