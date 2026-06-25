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

import 'dart:math' as math;
import 'package:criterion/src/statistics.dart';
import 'package:test/test.dart';

void main() {
  group('Sample Statistics', () {
    test('calculates correct mean', () {
      final sample = Sample([1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(sample.mean, closeTo(3.0, 0.0001));
    });

    test('calculates correct median (odd length)', () {
      final sample = Sample([5.0, 1.0, 3.0, 2.0, 4.0]);
      expect(sample.median, closeTo(3.0, 0.0001));
    });

    test('calculates correct median (even length)', () {
      final sample = Sample([1.0, 2.0, 3.0, 4.0]);
      expect(sample.median, closeTo(2.5, 0.0001));
    });

    test('calculates correct variance and stdDev', () {
      // For [1, 2, 3, 4], mean = 2.5
      // Differences: -1.5, -0.5, 0.5, 1.5
      // Squared: 2.25, 0.25, 0.25, 2.25
      // Sum = 5.0
      // Variance = 5.0 / (4 - 1) = 1.6666...
      // StdDev = sqrt(1.6666...) = 1.29099...
      final sample = Sample([1.0, 2.0, 3.0, 4.0]);
      expect(sample.variance, closeTo(5.0 / 3.0, 0.0001));
      expect(sample.stdDev, closeTo(math.sqrt(5.0 / 3.0), 0.0001));
    });

    test('calculates correct quantiles', () {
      final sample = Sample([1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(sample.quantile(0.0), closeTo(1.0, 0.0001));
      expect(sample.quantile(0.25), closeTo(2.0, 0.0001));
      expect(sample.quantile(0.5), closeTo(3.0, 0.0001));
      expect(sample.quantile(0.75), closeTo(4.0, 0.0001));
      expect(sample.quantile(1.0), closeTo(5.0, 0.0001));
    });

    test('outlier detection (Tukey)', () {
      // Q1 = 10, Q3 = 14
      // IQR = 4
      // loM = Q1 - 1.5 * IQR = 10 - 6 = 4
      // loS = Q1 - 3.0 * IQR = 10 - 12 = -2
      // hiM = Q3 + 1.5 * IQR = 14 + 6 = 20
      // hiS = Q3 + 3.0 * IQR = 14 + 12 = 26
      // Data: 3 (low mild), 9 (normal), 10 (normal), 11 (normal), 13 (normal), 14 (normal), 15 (normal), 21 (high mild), 30 (high severe)
      // Note: we need enough points so quantiles match nicely.
      // Let's create a dataset where we can control Q1 and Q3 precisely.
      // Let's check with a list: [10.0, 11.0, 12.0, 13.0, 14.0]
      // sorted: 10, 11, 12, 13, 14
      // N = 5.
      // Q1 (0.25) -> pos = 0.25 * 4 = 1.0 -> 11.0
      // Q3 (0.75) -> pos = 0.75 * 4 = 3.0 -> 13.0
      // IQR = 2.0
      // loM = 11.0 - 3.0 = 8.0
      // loS = 11.0 - 6.0 = 5.0
      // hiM = 13.0 + 3.0 = 16.0
      // hiS = 13.0 + 6.0 = 19.0
      // Let's add outliers:
      // 3.0 (low severe)
      // 7.0 (low mild)
      // 17.0 (high mild)
      // 20.0 (high severe)
      // Values: [3.0, 7.0, 10.0, 11.0, 12.0, 13.0, 14.0, 17.0, 20.0]
      // Let's calculate quantiles of this sorted array:
      // idx: 0=3, 1=7, 2=10, 3=11, 4=12, 5=13, 6=14, 7=17, 8=20. N = 9.
      // Q1 (p=0.25) -> pos = 0.25 * 8 = 2.0 -> 10.0
      // Q3 (p=0.75) -> pos = 0.75 * 8 = 6.0 -> 14.0
      // IQR = 4.0
      // loM = 10.0 - 6.0 = 4.0
      // loS = 10.0 - 12.0 = -2.0
      // hiM = 14.0 + 6.0 = 20.0
      // hiS = 14.0 + 12.0 = 26.0
      // Outliers check:
      // 3.0: >= -2.0 (loS) and < 4.0 (loM) -> low mild! (Wait, loS is -2.0, so 3.0 > -2.0, so yes, low mild)
      // 7.0: >= 4.0 -> not an outlier.
      // 17.0: > 14.0, < 20.0 (hiM) -> not an outlier.
      // 20.0: >= 20.0 (hiM) and < 26.0 (hiS) -> high mild!
      // Let's construct a cleaner test case.
      // Let's just define the data and verify that our calculations match the output.
      final sample = Sample([
        3.0,
        7.0,
        10.0,
        11.0,
        12.0,
        13.0,
        14.0,
        17.0,
        21.0,
      ]);
      final analysis = sample.analyzeOutliers();
      expect(analysis.lowSevere, equals(0));
      expect(analysis.lowMild, equals(1)); // 3.0 is between -2.0 and 4.0
      expect(
        analysis.highMild,
        equals(1),
      ); // 20.0 is exactly hiM (20.0) -> wait, highMild is when x > hiM and x <= hiS?
      // Our logic:
      // if (x < loS) lowSevere
      // else if (x < loM) lowMild
      // else if (x > hiS) highSevere
      // else if (x > hiM) highMild
      // For 20.0: is 20.0 > hiM (20.0)? No, it's equal to 20.0.
      // So 20.0 is in clean values.
      // Let's add -15.0 (lowSevere) and 40.0 (highSevere)
      final sample4 = Sample([
        -15.0,
        -3.0,
        3.0,
        7.0,
        10.0,
        11.0,
        12.0,
        13.0,
        14.0,
        17.0,
        21.0,
        27.0,
        40.0,
      ]);
      // N = 13.
      // Q1 (0.25) -> pos = 0.25 * 12 = 3.0 -> 7.0
      // Q3 (0.75) -> pos = 0.75 * 12 = 9.0 -> 17.0
      // IQR = 10.0
      // loM = 7.0 - 15.0 = -8.0
      // loS = 7.0 - 30.0 = -23.0
      // hiM = 17.0 + 15.0 = 32.0
      // hiS = 17.0 + 30.0 = 47.0
      // Data check:
      // -15.0: > -23.0, < -8.0 -> lowMild.
      // -3.0: > -8.0 -> normal.
      // 27.0: < 32.0 -> normal.
      // 40.0: > 32.0, < 47.0 -> highMild.
      // Let's test with these:
      final analysis4 = sample4.analyzeOutliers();
      expect(analysis4.lowSevere, equals(0));
      expect(analysis4.lowMild, equals(1)); // -15.0
      expect(analysis4.highMild, equals(1)); // 40.0
      expect(analysis4.highSevere, equals(0));
    });

    test('bootstrapping runs and produces plausible confidence intervals', () {
      // Use a fixed random generator
      final random = math.Random(12345);
      final sample = Sample(List.generate(100, (i) => i.toDouble()));
      final result = sample.bootstrap(resamples: 1000, random: random);

      // Mean is 49.5
      // Bootstrapped mean confidence interval should contain 49.5 and be relatively tight
      expect(result.meanConfidenceInterval.lowerBound, lessThan(49.5));
      expect(result.meanConfidenceInterval.upperBound, greaterThan(49.5));
      expect(result.meanConfidenceInterval.lowerBound, greaterThan(40.0));
      expect(result.meanConfidenceInterval.upperBound, lessThan(60.0));

      // Median is 49.5
      expect(result.medianConfidenceInterval.lowerBound, lessThan(52.0));
      expect(result.medianConfidenceInterval.upperBound, greaterThan(47.0));
    });
  });
}
