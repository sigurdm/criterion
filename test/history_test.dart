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
import 'package:criterion/src/history.dart';
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

    test('GitCommit serialization and BenchmarkResult integration', () {
      final commit = GitCommit(
        hash: 'd189963ad11a35a348de84d309b66a5678d990b9',
        shortHash: 'd189963',
        message: 'Fix compare_git',
        timestamp: DateTime.parse('2026-06-25T15:02:25Z'),
      );

      final json = commit.toJson();
      expect(json['hash'], 'd189963ad11a35a348de84d309b66a5678d990b9');
      expect(json['shortHash'], 'd189963');
      expect(json['message'], 'Fix compare_git');

      final deserialized = GitCommit.fromJson(json);
      expect(deserialized.hash, commit.hash);
      expect(deserialized.shortHash, commit.shortHash);
      expect(deserialized.message, commit.message);
    });

    test('HistoryManager gracefully handles corrupted/invalid JSON', () async {
      final file = File(historyFilePath);
      file.writeAsStringSync('invalid json content');
      final manager = HistoryManager(historyFilePath);
      final list = await manager.load();
      expect(list, isEmpty);
    });

    test(
      'checkRegressions uses latest timestamp when duplicates exist and handles empty history',
      () {
        final now = DateTime.now();
        final older = BenchmarkResult(
          name: 'bench',
          iterations: 100,
          platform: 'jit',
          timestamp: now.subtract(const Duration(hours: 1)),
          primary: MeasurementResult(
            sampleTimes: [10.0],
            mean: 10.0,
            median: 10.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 9.0, upperBound: 11.0),
            medianCI: ConfidenceInterval(lowerBound: 9.0, upperBound: 11.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
        );
        final newer = BenchmarkResult(
          name: 'bench',
          iterations: 100,
          platform: 'jit',
          timestamp: now,
          primary: MeasurementResult(
            sampleTimes: [20.0],
            mean: 20.0,
            median: 20.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 19.0, upperBound: 21.0),
            medianCI: ConfidenceInterval(lowerBound: 19.0, upperBound: 21.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
        );
        final printsDedup = <String>[];
        runZoned(
          () => checkRegressions(current: [newer], history: [older, newer]),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printsDedup.add(line),
          ),
        );
        expect(
          printsDedup.any((l) => l.contains('WARNING: Regression detected')),
          isFalse,
        );

        final printsRegressed = <String>[];
        runZoned(
          () => checkRegressions(current: [newer], history: [older]),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printsRegressed.add(line),
          ),
        );
        expect(
          printsRegressed.any(
            (l) => l.contains('WARNING: Regression detected in bench'),
          ),
          isTrue,
        );

        final printsEmpty = <String>[];
        runZoned(
          () => checkRegressions(current: [newer], history: []),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printsEmpty.add(line),
          ),
        );
        expect(printsEmpty, isEmpty);
      },
    );
  });
}
