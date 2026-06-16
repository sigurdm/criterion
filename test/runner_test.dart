import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('AOT Runner', () {
    late File dummyFile;
    late Directory reportDir;

    setUp(() {
      // Write the dummy benchmark in the project's 'test' folder so it can resolve package imports.
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

        print('stdout: ${result.stdout}');
        print('stderr: ${result.stderr}');
        expect(result.exitCode, equals(0));

        // Verify that the JSON output exists and has no allocatedBytesPerIteration
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
        // In AOT mode, heap allocations should be null
        expect(memory!['allocatedBytesPerIteration'], isNull);
        expect(memory['allocatedObjectsPerIteration'], isNull);
        expect(memory['rssDeltaBytes'], isNotNull);

        // Verify that the temporary _aot.exe executable was deleted.
        final aotExeFile = File('test/temp_aot_dummy_bench_aot.exe');
        expect(aotExeFile.existsSync(), isFalse);
      },
    );
  });
}
