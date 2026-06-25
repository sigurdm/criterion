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
import 'package:test/test.dart';

void main() {
  group('Criterion Variants Integration', () {
    late File dummyFile;
    late Directory reportDir;

    setUp(() {
      dummyFile = File('test/temp_variants_dummy_bench.dart');
      reportDir = Directory('test/temp_variants_report');
      if (reportDir.existsSync()) {
        reportDir.deleteSync(recursive: true);
      }

      dummyFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'VariantsSuite',
    (c) {
      c.variants('Fibonacci', {
        'recursive': () {
          fib(10);
        },
        'iterative': () {
          fibIter(10);
        },
      }, samples: 5, warmupDuration: Duration(milliseconds: 5));
    },
    config: CriterionConfig(
      reportDir: '${reportDir.path}',
      generateHtmlReport: true,
      exportJson: true,
    ),
  );
}

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

int fibIter(int n) {
  if (n <= 1) return n;
  var a = 0;
  var b = 1;
  for (var i = 2; i <= n; i++) {
    final temp = a + b;
    a = b;
    b = temp;
  }
  return b;
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
        final aotExe = File('test/temp_variants_dummy_bench_aot.exe');
        if (aotExe.existsSync()) {
          aotExe.deleteSync();
        }
      } catch (e) {
        print('Warning: cleanup failed: $e');
      }
    });

    test(
      'runs benchmark with variants, prints table, and generates report',
      () async {
        final runDart = Platform.resolvedExecutable;
        final runScriptPath = 'bin/run.dart';

        // Run via bin/run.dart (which compiles to AOT)
        final result = await Process.run(runDart, [
          runScriptPath,
          dummyFile.path,
        ]);

        print('stdout:\n${result.stdout}');
        print('stderr:\n${result.stderr}');
        expect(result.exitCode, equals(0));

        // 1. Verify stdout contains comparison table
        expect(
          result.stdout,
          contains('=== Variant Comparison: Fibonacci ==='),
        );
        expect(
          result.stdout,
          contains('| Variant | Time | Relative Speed | Significant? |'),
        );
        expect(result.stdout, contains('recursive (baseline)'));
        expect(result.stdout, contains('iterative'));

        // 2. Verify JSON report
        final resultsJsonFile = File('${reportDir.path}/results.json');
        expect(resultsJsonFile.existsSync(), isTrue);

        final jsonContent =
            jsonDecode(resultsJsonFile.readAsStringSync()) as List;
        expect(jsonContent.length, equals(2));

        final r1 = jsonContent[0] as Map<String, dynamic>;
        expect(r1['name'], equals('Fibonacci / recursive'));
        expect(r1['variantGroup'], equals('Fibonacci'));
        expect(r1['variantName'], equals('recursive'));

        final r2 = jsonContent[1] as Map<String, dynamic>;
        expect(r2['name'], equals('Fibonacci / iterative'));
        expect(r2['variantGroup'], equals('Fibonacci'));
        expect(r2['variantName'], equals('iterative'));

        // 3. Verify HTML report contains variant data and elements
        final htmlFile = File('${reportDir.path}/index.html');
        expect(htmlFile.existsSync(), isTrue);

        final htmlContent = htmlFile.readAsStringSync();
        expect(htmlContent, contains('"variantGroup":"Fibonacci"'));
        expect(htmlContent, contains('"variantName":"recursive"'));
        expect(htmlContent, contains('"variantName":"iterative"'));

        // Verify new HTML elements are present
        expect(htmlContent, contains('id="variants-mode"'));
        expect(htmlContent, contains('id="variants-view"'));
        expect(htmlContent, contains('generateVariantCharts'));
      },
    );
  });
}
