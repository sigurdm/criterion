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

import 'dart:async';
import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('History & Regression Detection', () {
    late Directory tempDir;
    late String historyFilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('criterion_history_test');
      historyFilePath = '${tempDir.path}/history.json';
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves results to history and appends in subsequent runs', () async {
      final config = CriterionConfig(
        generateHtmlReport: false,
        exportJson: false,
        exportHistory: true,
        historyFile: historyFilePath,
        useKbssd: false,
      );

      // Run 1
      await criterion('Suite', (c) {
        c.bench('bench1', () {}, samples: 5, warmupDuration: Duration.zero);
      }, config: config);

      final file = File(historyFilePath);
      expect(file.existsSync(), isTrue);

      final content1 = file.readAsStringSync();
      expect(content1, contains('"name": "bench1"'));

      // Run 2
      await criterion('Suite', (c) {
        c.bench('bench2', () {}, samples: 5, warmupDuration: Duration.zero);
      }, config: config);

      final content2 = file.readAsStringSync();
      expect(content2, contains('"name": "bench1"'));
      expect(content2, contains('"name": "bench2"'));
    });

    test('detects regression and prints warning', () async {
      final configCheck = CriterionConfig(
        generateHtmlReport: false,
        exportJson: false,
        exportHistory: true,
        checkRegressions: true,
        historyFile: historyFilePath,
        useKbssd: false,
      );

      // 1. Run fast baseline
      await criterion('Suite', (c) {
        c.bench(
          'bench',
          () {
            // Fast
          },
          samples: 5,
          warmupDuration: Duration.zero,
        );
      }, config: configCheck);

      // 2. Run slow variant, capture stdout
      final prints = <String>[];
      await runZoned(
        () async {
          await criterion('Suite', (c) {
            c.bench(
              'bench',
              () {
                // Slow
                sleep(const Duration(milliseconds: 1));
              },
              samples: 5,
              warmupDuration: Duration.zero,
            );
          }, config: configCheck);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            prints.add(line);
          },
        ),
      );

      final hasWarning = prints.any(
        (p) => p.contains('WARNING: Regression detected in bench'),
      );
      expect(
        hasWarning,
        isTrue,
        reason: 'Expected regression warning in: $prints',
      );
    });
  });
}
