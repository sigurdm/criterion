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

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

Future<bool> _isNodeAvailable() async {
  try {
    final result = await Process.run('node', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  group('AOT Runner (Original)', () {
    late File dummyFile;
    late Directory reportDir;

    setUp(() {
      dummyFile = File('test/temp_aot_dummy_bench.dart');
      reportDir = Directory('test/temp_aot_report');
      if (reportDir.existsSync()) {
        reportDir.deleteSync(recursive: true);
      }

      dummyFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'DummySuite',
    (c) {
      c.bench(
        'dummy_bench',
        () {
          var a = 0;
          for (var i = 0; i < 1000; i++) {
            a += i;
          }
        },
        samples: 5,
        warmupDuration: Duration(milliseconds: 10),
      );
    },
    config: CriterionConfig(
      reportDir: '${reportDir.path}',
      generateHtmlReport: true,
      exportJson: true,
      exportHistory: false,
    ),
  );
}
''');
    });

    tearDown(() {
      try {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
        if (reportDir.existsSync()) {
          reportDir.deleteSync(recursive: true);
        }
      } catch (e) {
        print('Warning: cleanup failed: $e');
      }
    });

    test(
      'compiles and runs benchmark in AOT, and report only contains RSS delta',
      () async {
        final runDart = Platform.resolvedExecutable;
        final runScriptPath = 'bin/run.dart';

        final result = await Process.run(runDart, [
          runScriptPath,
          '--memory',
          dummyFile.path,
        ]);

        expect(result.exitCode, equals(0));

        final resultsJsonFile = File('${reportDir.path}/results.json');
        expect(resultsJsonFile.existsSync(), isTrue);

        final jsonContent =
            jsonDecode(resultsJsonFile.readAsStringSync()) as List;
        expect(jsonContent.length, equals(1));

        final benchmarkResult = jsonContent[0] as Map<String, dynamic>;
        expect(benchmarkResult['name'], equals('dummy_bench'));

        final primary = benchmarkResult['primary'] as Map<String, dynamic>;
        final memory = primary['memory'] as Map<String, dynamic>?;

        expect(memory, isNotNull);
        expect(memory!['allocatedBytesPerIteration'], isNull);
        expect(memory['allocatedObjectsPerIteration'], isNull);
        expect(memory['rssDeltaBytes'], isNotNull);

        final aotExeFile = File('test/temp_aot_dummy_bench_aot.exe');
        expect(aotExeFile.existsSync(), isFalse);
      },
    );
  });

  group('Multi-Runtime Runner', () {
    late File dummyFile;
    late Directory reportDir;

    setUp(() {
      dummyFile = File('test/temp_multi_dummy_bench.dart');
      reportDir = Directory('test/temp_multi_report');
      if (reportDir.existsSync()) {
        reportDir.deleteSync(recursive: true);
      }

      dummyFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'DummySuite',
    (c) {
      c.bench(
        'dummy_bench',
        () {
          var a = 0;
          for (var i = 0; i < 1000; i++) {
            a += i;
          }
        },
        samples: 5,
        warmupDuration: Duration(milliseconds: 10),
      );
    },
    config: CriterionConfig(
      reportDir: '${reportDir.path}',
      generateHtmlReport: true,
      exportJson: true,
      exportHistory: false,
    ),
  );
}
''');
    });

    tearDown(() {
      try {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
        if (reportDir.existsSync()) {
          reportDir.deleteSync(recursive: true);
        }
      } catch (e) {
        print('Warning: cleanup failed: $e');
      }
    });

    test('runs benchmark in JIT flavor', () async {
      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'jit',
        dummyFile.path,
      ]);

      expect(result.exitCode, equals(0));
      final resultsJsonFile = File('${reportDir.path}/results.json');
      expect(resultsJsonFile.existsSync(), isTrue);

      final jsonContent =
          jsonDecode(resultsJsonFile.readAsStringSync()) as List;
      expect(jsonContent.length, equals(1));
      final benchmarkResult = jsonContent[0] as Map<String, dynamic>;
      expect(benchmarkResult['platform'], equals('jit'));
      expect(benchmarkResult['hostEnvironment'], isNotNull);
      expect(benchmarkResult['hostEnvironment']['os'], isNot('unknown'));
      expect(
        benchmarkResult['hostEnvironment']['dartSdkVersion'],
        isNot('unknown'),
      );
      expect(benchmarkResult['timestamp'], isNotNull);
    });

    test('runs benchmark with --json flag and outputs to stdout', () async {
      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'jit',
        '--json',
        dummyFile.path,
      ]);

      expect(result.exitCode, equals(0));
      final resultsJsonFile = File('${reportDir.path}/results.json');
      expect(resultsJsonFile.existsSync(), isFalse);

      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonStr = stdoutStr.substring(jsonStart).trim();
      final jsonContent = jsonDecode(jsonStr) as List;
      expect(jsonContent.length, equals(1));

      final benchmarkResult = jsonContent[0] as Map<String, dynamic>;
      expect(benchmarkResult['name'], equals('dummy_bench'));
      expect(benchmarkResult['platform'], equals('jit'));
      expect(benchmarkResult['hostEnvironment'], isNotNull);
      expect(benchmarkResult['timestamp'], isNotNull);
    });

    test('runs benchmark in JS flavor if node is available', () async {
      if (!await _isNodeAvailable()) {
        markTestSkipped('node is not available');
        return;
      }

      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'js',
        '--json',
        dummyFile.path,
      ]);

      expect(result.exitCode, equals(0));
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonStr = stdoutStr.substring(jsonStart).trim();
      final jsonContent = jsonDecode(jsonStr) as List;
      expect(jsonContent.length, equals(1));
      final benchmarkResult = jsonContent[0] as Map<String, dynamic>;
      expect(benchmarkResult['platform'], equals('js'));
    });

    test(
      'runs multi-suite benchmark with --json flag and outputs all results',
      () async {
        final multiSuiteFile = File('test/temp_multi_suite_bench.dart');
        try {
          multiSuiteFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'Suite1',
    (c) {
      c.bench('bench1', () {}, samples: 5, warmupDuration: Duration(milliseconds: 10));
    },
    config: CriterionConfig(exportJson: false, generateHtmlReport: false, exportHistory: false),
  );
  await criterion(
    'Suite2',
    (c) {
      c.bench('bench2', () {}, samples: 5, warmupDuration: Duration(milliseconds: 10));
    },
    config: CriterionConfig(exportJson: false, generateHtmlReport: false, exportHistory: false),
  );
}
''');

          final runDart = Platform.resolvedExecutable;
          final runScriptPath = 'bin/run.dart';

          final result = await Process.run(runDart, [
            runScriptPath,
            '-f',
            'jit',
            '--json',
            multiSuiteFile.path,
          ]);

          expect(
            result.exitCode,
            equals(0),
            reason: 'Stdout: ${result.stdout}\nStderr: ${result.stderr}',
          );

          final stdoutStr = result.stdout as String;
          final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
          expect(jsonStart, isNot(-1));

          final jsonStr = stdoutStr.substring(jsonStart).trim();
          final jsonContent = jsonDecode(jsonStr) as List;
          expect(jsonContent.length, equals(2));

          final names = jsonContent.map((r) => r['name']).toList();
          expect(names, containsAll(['bench1', 'bench2']));
        } finally {
          if (multiSuiteFile.existsSync()) {
            multiSuiteFile.deleteSync();
          }
        }
      },
    );

    test(
      'aggregates results across multiple flavors when not in json mode',
      () async {
        final multiFlavorBenchFile = File('test/temp_multi_flavor_bench.dart');
        final defaultReportDir = Directory('benchmark/report');
        if (defaultReportDir.existsSync()) {
          defaultReportDir.deleteSync(recursive: true);
        }

        try {
          multiFlavorBenchFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'FlavorSuite',
    (c) {
      c.bench('flavor_bench', () {}, samples: 5, warmupDuration: Duration(milliseconds: 10));
    },
    config: CriterionConfig(
      reportDir: 'benchmark/report',
      exportJson: true,
      generateHtmlReport: true,
      exportHistory: false,
    ),
  );
}
''');

          final runDart = Platform.resolvedExecutable;
          final runScriptPath = 'bin/run.dart';

          final result = await Process.run(runDart, [
            runScriptPath,
            '-f',
            'jit',
            '-f',
            'aot',
            multiFlavorBenchFile.path,
          ]);

          expect(
            result.exitCode,
            equals(0),
            reason: 'Stdout: ${result.stdout}\nStderr: ${result.stderr}',
          );

          final resultsJsonFile = File('benchmark/report/results.json');
          final indexHtmlFile = File('benchmark/report/index.html');
          expect(resultsJsonFile.existsSync(), isTrue);
          expect(indexHtmlFile.existsSync(), isTrue);

          final jsonContent =
              jsonDecode(resultsJsonFile.readAsStringSync()) as List;
          expect(jsonContent.length, equals(2));

          final platforms = jsonContent.map((r) => r['platform']).toList();
          expect(platforms, containsAll(['jit', 'aot']));
        } finally {
          if (multiFlavorBenchFile.existsSync()) {
            multiFlavorBenchFile.deleteSync();
          }
          if (defaultReportDir.existsSync()) {
            defaultReportDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test('runs benchmark in WASM flavor if node is available', () async {
      if (!await _isNodeAvailable()) {
        markTestSkipped('node is not available');
        return;
      }

      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'wasm',
        '--json',
        dummyFile.path,
      ]);

      expect(result.exitCode, equals(0));
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonStr = stdoutStr.substring(jsonStart).trim();
      final jsonContent = jsonDecode(jsonStr) as List;
      expect(jsonContent.length, equals(1));
      final benchmarkResult = jsonContent[0] as Map<String, dynamic>;
      expect(benchmarkResult['platform'], equals('wasm'));
    });
  });
  group('CLI Filtering, Quick Mode, Timing Only, and Suite Discovery', () {
    late File dummyFile;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory('test/temp_runner_feature_dir');
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      tempDir.createSync(recursive: true);
      dummyFile = File('${tempDir.path}/test_benchmarks.dart');
      dummyFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'FeatureSuite',
    (c) {
      c.bench('apple_bench', () {}, samples: 5, warmupDuration: Duration(milliseconds: 5));
      c.bench('banana_bench', () {}, samples: 5, warmupDuration: Duration(milliseconds: 5));
      c.bench('cherry_bench', () {}, samples: 5, warmupDuration: Duration(milliseconds: 5));
    },
    config: CriterionConfig(exportJson: false, generateHtmlReport: false, exportHistory: false),
  );
}
''');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (e) {
        print('Warning: cleanup failed: $e');
      }
    });

    test('CLI --filter (-k) filters executed benchmarks', () async {
      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'jit',
        '--json',
        '--filter=banana',
        dummyFile.path,
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: '${result.stdout}\n${result.stderr}',
      );
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonContent =
          jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
      expect(jsonContent.length, equals(1));
      expect(jsonContent.first['name'], equals('banana_bench'));
    });

    test(
      'CLI --quick (-q) runs fast timing-only pass with profilers skipped',
      () async {
        final runDart = Platform.resolvedExecutable;
        final runScriptPath = 'bin/run.dart';

        final result = await Process.run(runDart, [
          runScriptPath,
          '-f',
          'jit',
          '--json',
          '-q',
          dummyFile.path,
        ]);

        expect(
          result.exitCode,
          equals(0),
          reason: '${result.stdout}\n${result.stderr}',
        );
        final stdoutStr = result.stdout as String;
        final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
        expect(jsonStart, isNot(-1));

        final jsonContent =
            jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
        expect(jsonContent.length, equals(3));
        for (final item in jsonContent) {
          final primary = item['primary'] as Map<String, dynamic>;
          expect(primary['memory'], isNull);
          expect(primary['instructions'], isNull);
          expect(primary['cyclesPerIteration'], isNull);
        }
      },
    );

    test('CLI --timing-only skips secondary profilers', () async {
      final runDart = Platform.resolvedExecutable;
      final runScriptPath = 'bin/run.dart';

      final result = await Process.run(runDart, [
        runScriptPath,
        '-f',
        'jit',
        '--json',
        '--timing-only',
        dummyFile.path,
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: '${result.stdout}\n${result.stderr}',
      );
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonContent =
          jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
      expect(jsonContent.length, equals(3));
      for (final item in jsonContent) {
        final primary = item['primary'] as Map<String, dynamic>;
        expect(primary['memory'], isNull);
        expect(primary['instructions'], isNull);
        expect(primary['cyclesPerIteration'], isNull);
      }
    });

    test('CLI measures time only unless asked for more', () async {
      final runDart = Platform.resolvedExecutable;

      final result = await Process.run(runDart, [
        'bin/run.dart',
        '-f',
        'jit',
        '--json',
        dummyFile.path,
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: '${result.stdout}\n${result.stderr}',
      );
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonContent =
          jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
      expect(jsonContent, isNotEmpty);
      for (final item in jsonContent) {
        final primary = item['primary'] as Map<String, dynamic>;
        expect(primary['memory'], isNull);
        expect(primary['instructions'], isNull);
        expect(primary['cyclesPerIteration'], isNull);
      }
    });

    test('CLI --memory enables only the memory pass', () async {
      final runDart = Platform.resolvedExecutable;

      final result = await Process.run(runDart, [
        'bin/run.dart',
        '-f',
        'jit',
        '--json',
        '--memory',
        dummyFile.path,
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: '${result.stdout}\n${result.stderr}',
      );
      final stdoutStr = result.stdout as String;
      final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
      expect(jsonStart, isNot(-1));

      final jsonContent =
          jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
      expect(jsonContent, isNotEmpty);
      for (final item in jsonContent) {
        final primary = item['primary'] as Map<String, dynamic>;
        expect(primary['memory'], isNotNull);
        expect(primary['instructions'], isNull);
        expect(primary['cyclesPerIteration'], isNull);
      }
    });

    test(
      'CLI benchmark discovery when no arguments provided defaults to benchmark/ directory',
      () async {
        final runDart = Platform.resolvedExecutable;
        final runScriptPath = 'bin/run.dart';

        final result = await Process.run(runDart, [
          runScriptPath,
          '-f',
          'jit',
          '--json',
          '--quick',
          '--filter=Integer',
        ]);

        expect(
          result.exitCode,
          equals(0),
          reason: '${result.stdout}\n${result.stderr}',
        );
        final stdoutStr = result.stdout as String;
        final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
        expect(jsonStart, isNot(-1));

        final jsonContent =
            jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
        expect(jsonContent, isNotEmpty);
        expect(jsonContent.first['name'], contains('Integer'));
      },
    );

    test(
      'CLI benchmark discovery when directory is supplied as argument',
      () async {
        final subDir = Directory('${tempDir.path}/suite_dir')..createSync();
        final file1 = File('${subDir.path}/bench_one.dart');
        final file2 = File('${subDir.path}/bench_two.dart');

        file1.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'SuiteA',
    (c) {
      c.bench('bench_from_one', () {}, samples: 5, warmupDuration: Duration(milliseconds: 5));
    },
    config: CriterionConfig(exportJson: false, generateHtmlReport: false, exportHistory: false),
  );
}
''');

        file2.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'SuiteB',
    (c) {
      c.bench('bench_from_two', () {}, samples: 5, warmupDuration: Duration(milliseconds: 5));
    },
    config: CriterionConfig(exportJson: false, generateHtmlReport: false, exportHistory: false),
  );
}
''');

        final runDart = Platform.resolvedExecutable;
        final runScriptPath = 'bin/run.dart';

        final result = await Process.run(runDart, [
          runScriptPath,
          '-f',
          'jit',
          '--json',
          subDir.path,
        ]);

        expect(
          result.exitCode,
          equals(0),
          reason: '${result.stdout}\n${result.stderr}',
        );
        final stdoutStr = result.stdout as String;
        final jsonStart = stdoutStr.indexOf(RegExp(r'[\[\{]'));
        expect(jsonStart, isNot(-1));

        final jsonContent =
            jsonDecode(stdoutStr.substring(jsonStart).trim()) as List;
        expect(jsonContent.length, equals(2));
        final names = jsonContent.map((r) => r['name']).toList();
        expect(names, containsAll(['bench_from_one', 'bench_from_two']));
      },
    );
  });
}
