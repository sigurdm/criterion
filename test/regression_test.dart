import 'dart:io';
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

import 'package:criterion/criterion.dart';
import 'package:criterion/src/history.dart';
import 'package:test/test.dart';

void main() {
  group('Programmatic Regression Testing', () {
    test('can detect regressions from results list', () {
      // 1. Define baseline (golden) results
      final baseline = <BenchmarkResult>[
        BenchmarkResult(
          name: 'fast_op',
          iterations: 10000,
          primary: MeasurementResult(
            mean: 100.0, // 100ns
            meanCI: ConfidenceInterval(lowerBound: 98.0, upperBound: 102.0),
            median: 100.0,
            medianCI: ConfidenceInterval(lowerBound: 98.0, upperBound: 102.0),
            stdDev: 2.0,
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [100.0],
          ),
          timestamp: DateTime.now(),
          platform: 'vm',
        ),
        BenchmarkResult(
          name: 'stable_op',
          iterations: 10000,
          primary: MeasurementResult(
            mean: 500.0,
            meanCI: ConfidenceInterval(lowerBound: 490.0, upperBound: 510.0),
            median: 500.0,
            medianCI: ConfidenceInterval(lowerBound: 490.0, upperBound: 510.0),
            stdDev: 10.0,
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [500.0],
          ),
          timestamp: DateTime.now(),
          platform: 'vm',
        ),
      ];

      // 2. Define current results (fast_op regressed, stable_op is fine)
      final current = <BenchmarkResult>[
        BenchmarkResult(
          name: 'fast_op',
          iterations: 10000,
          primary: MeasurementResult(
            mean: 120.0, // 120ns (regression!)
            meanCI: ConfidenceInterval(
              lowerBound: 118.0,
              upperBound: 122.0,
            ), // No overlap with [98, 102]
            median: 120.0,
            medianCI: ConfidenceInterval(lowerBound: 118.0, upperBound: 122.0),
            stdDev: 2.0,
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [120.0],
          ),
          timestamp: DateTime.now(),
          platform: 'vm',
        ),
        BenchmarkResult(
          name: 'stable_op',
          iterations: 10000,
          primary: MeasurementResult(
            mean: 502.0, // Slight increase, but overlaps with [490, 510]
            meanCI: ConfidenceInterval(
              lowerBound: 492.0,
              upperBound: 512.0,
            ), // Overlaps!
            median: 502.0,
            medianCI: ConfidenceInterval(lowerBound: 492.0, upperBound: 512.0),
            stdDev: 10.0,
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [502.0],
          ),
          timestamp: DateTime.now(),
          platform: 'vm',
        ),
      ];

      // 3. Compare
      final comparison = compareResults(baseline, current);

      // 4. Assert
      expect(comparison.regressions, hasLength(1));
      expect(comparison.regressions.first.name, equals('fast_op'));
      expect(
        comparison.regressions.first.time.percentDiff,
        closeTo(20.0, 0.01),
      );
    });

    test('loadResults and formatResults roundtrip', () {
      final results = <BenchmarkResult>[
        BenchmarkResult(
          name: 'test',
          iterations: 10000,
          primary: MeasurementResult(
            mean: 100.0,
            meanCI: ConfidenceInterval(lowerBound: 98.0, upperBound: 102.0),
            median: 100.0,
            medianCI: ConfidenceInterval(lowerBound: 98.0, upperBound: 102.0),
            stdDev: 2.0,
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [100.0],
          ),
          timestamp: DateTime.now(),
          platform: 'vm',
        ),
      ];

      final jsonString = formatResults(results);
      final decoded = loadResults(jsonString);

      expect(decoded, hasLength(1));
      expect(decoded.first.name, equals('test'));
      expect(decoded.first.primary.mean, equals(100.0));
    });

    test('named baselines save and load via HistoryManager', () async {
      final tempDir = Directory.systemTemp.createTempSync('baseline_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final historyPath = '${tempDir.path}/history.json';
      final mgr = HistoryManager(historyPath);

      // Loading non-existent baseline returns empty list
      final nonExistent = await mgr.loadNamedBaseline('release-1_0');
      expect(nonExistent, isEmpty);

      final dummyResults = [
        BenchmarkResult(
          name: 'baseline_bench',
          iterations: 100,
          primary: MeasurementResult(
            mean: 50.0,
            median: 50.0,
            stdDev: 1.0,
            meanCI: ConfidenceInterval(lowerBound: 49.0, upperBound: 51.0),
            medianCI: ConfidenceInterval(lowerBound: 49.0, upperBound: 51.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            sampleTimes: [50.0],
          ),
          platform: 'vm',
        ),
      ];

      await mgr.saveNamedBaseline('v1_baseline', dummyResults);

      final loaded = await mgr.loadNamedBaseline('v1_baseline');
      expect(loaded, hasLength(1));
      expect(loaded.first.name, equals('baseline_bench'));
      expect(loaded.first.primary.mean, equals(50.0));

      // Invalid baseline names throw ArgumentError
      expect(
        () => mgr.saveNamedBaseline('../escape', dummyResults),
        throwsArgumentError,
      );
      expect(
        () => mgr.loadNamedBaseline('invalid name with spaces'),
        throwsArgumentError,
      );
    });

    test(
      'failOnRegression in Criterion.run throws StateError when regression occurs',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'criterion_fail_reg_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final historyPath = '${tempDir.path}/history.json';
        final mgr = HistoryManager(historyPath);

        // Save a fast baseline named 'golden'
        final baseline = [
          BenchmarkResult(
            name: 'regression_target',
            iterations: 100,
            primary: MeasurementResult(
              mean: 1.0,
              median: 1.0,
              stdDev: 0.01,
              meanCI: ConfidenceInterval(lowerBound: 0.9, upperBound: 1.1),
              medianCI: ConfidenceInterval(lowerBound: 0.9, upperBound: 1.1),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
              sampleTimes: [1.0, 1.0],
            ),
          ),
        ];
        await mgr.saveNamedBaseline('golden', baseline);

        // Run Criterion with baseline 'golden' and failOnRegression = true.
        // The bench function sleeps / takes much longer than 1.0 ns.
        final c = Criterion(
          suiteName: 'FailSuite',
          config: CriterionConfig(
            historyFile: historyPath,
            baseline: 'golden',
            failOnRegression: true,
            generateHtmlReport: false,
            exportJson: false,
            exportHistory: false,
          ),
        );

        c.bench(
          'regression_target',
          () {
            // do some work so it takes > 10 ns
            var x = 0;
            for (var i = 0; i < 500; i++) {
              x += i;
            }
            Blackhole.sink = x;
          },
          samples: 5,
          warmupDuration: Duration(milliseconds: 10),
        );

        expect(c.run(), throwsA(isA<StateError>()));
      },
    );

    test(
      'bin/compare CLI supports --noise-threshold and --fail-on-regression',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'cli_compare_test_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final beforeFile = File('${tempDir.path}/before.json');
        final afterFile = File('${tempDir.path}/after.json');

        final beforeResult = [
          BenchmarkResult(
            name: 'bench',
            iterations: 100,
            primary: MeasurementResult(
              mean: 100.0,
              median: 100.0,
              stdDev: 0.1,
              meanCI: ConfidenceInterval(lowerBound: 99.0, upperBound: 101.0),
              medianCI: ConfidenceInterval(lowerBound: 99.0, upperBound: 101.0),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
              sampleTimes: [100.0],
            ),
          ),
        ];

        // 5% regression: 100 -> 105 (no CI overlap with [104, 106])
        final afterResult = [
          BenchmarkResult(
            name: 'bench',
            iterations: 100,
            primary: MeasurementResult(
              mean: 105.0,
              median: 105.0,
              stdDev: 0.1,
              meanCI: ConfidenceInterval(lowerBound: 104.0, upperBound: 106.0),
              medianCI: ConfidenceInterval(
                lowerBound: 104.0,
                upperBound: 106.0,
              ),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
              sampleTimes: [105.0],
            ),
          ),
        ];

        beforeFile.writeAsStringSync(formatResults(beforeResult));
        afterFile.writeAsStringSync(formatResults(afterResult));

        final dartExe = Platform.resolvedExecutable;

        // 1. Run without --fail-on-regression -> exitCode 0
        final res1 = await Process.run(dartExe, [
          'bin/compare.dart',
          beforeFile.path,
          afterFile.path,
        ]);
        expect(res1.exitCode, equals(0));

        // 2. Run with --fail-on-regression and default noise-threshold (0.01 = 1%) -> exitCode 1
        final res2 = await Process.run(dartExe, [
          'bin/compare.dart',
          '--fail-on-regression',
          beforeFile.path,
          afterFile.path,
        ]);
        expect(res2.exitCode, equals(1));
        expect(res2.stderr, contains('Regressions detected'));

        // 3. Run with --fail-on-regression and --noise-threshold 0.10 (10%) -> 5% regression is noise -> exitCode 0
        final res3 = await Process.run(dartExe, [
          'bin/compare.dart',
          '--fail-on-regression',
          '--noise-threshold',
          '0.10',
          beforeFile.path,
          afterFile.path,
        ]);
        expect(res3.exitCode, equals(0));
        expect(res3.stdout, contains('No change (noise)'));
      },
    );
  });
}
