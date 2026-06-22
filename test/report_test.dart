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
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Criterion Reporting', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('criterion_report_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('generates JSON and HTML reports', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: true,
        exportJson: true,
      );

      final results = await criterion('Test Suite', (c) {
        c.bench(
          'bench1',
          () {
            var sum = 0;
            for (var i = 0; i < 100; i++) {
              sum += i;
            }
            if (sum == 0) throw StateError('invalid sum');
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
        c.bench(
          'bench2',
          () {
            var sum = 0;
            for (var i = 0; i < 200; i++) {
              sum += i;
            }
            if (sum == 0) throw StateError('invalid sum');
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      expect(results.length, equals(2));

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isTrue);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isTrue);

      // Verify JSON content
      final jsonContent = jsonFile.readAsStringSync();
      final decoded = jsonDecode(jsonContent) as List;
      expect(decoded.length, equals(2));

      final firstResult = decoded[0] as Map<String, dynamic>;
      expect(firstResult['name'], equals('bench1'));
      expect(firstResult['iterations'], isNotNull);
      expect(firstResult['primary'], isNotNull);

      final primary = firstResult['primary'] as Map<String, dynamic>;
      expect(primary['sampleTimes'], isList);
      expect((primary['sampleTimes'] as List).length, equals(5));
      expect(primary['mean'], isNotNull);
      expect(primary['median'], isNotNull);
      expect(primary['stdDev'], isNotNull);
      expect(primary['meanCI'], isNotNull);
      expect(primary['medianCI'], isNotNull);
      expect(primary['outliers'], isNotNull);

      // Verify HTML content contains the data
      final htmlContent = htmlFile.readAsStringSync();
      expect(htmlContent, contains('const data = ['));
      expect(htmlContent, contains('"name":"bench1"'));
      expect(htmlContent, contains('"name":"bench2"'));
      expect(htmlContent, contains('https://cdn.jsdelivr.net/npm/chart.js'));
    });

    test('respects config to disable reports', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: false,
      );

      await criterion('Test Suite Disabled', (c) {
        c.bench(
          'bench1',
          () {},
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isFalse);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isFalse);
    });
  });
}
