// Copyright 2026 Sigurd Meldgaard
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
        print('Skipping JS runner test: node is not available');
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

    test('runs benchmark in WASM flavor if node is available', () async {
      if (!await _isNodeAvailable()) {
        print('Skipping WASM runner test: node is not available');
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
}
