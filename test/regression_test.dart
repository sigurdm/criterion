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
  });
}
