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

/// Represents a collection of benchmark measurements and provides
/// statistical analysis tools.
final class Sample {
  /// The raw measurements (e.g. execution times in nanoseconds).
  final List<double> values;

  /// The values sorted in ascending order, cached for quantile calculation.
  late final List<double> sortedValues;

  /// Creates a [Sample] from a list of values.
  Sample(List<double> values) : values = List<double>.unmodifiable(values) {
    sortedValues = List<double>.from(values)..sort();
  }

  /// The number of values in this sample.
  int get length => values.length;

  /// The arithmetic mean of the sample.
  double get mean {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// The sample variance (divided by N - 1).
  double get variance {
    if (values.length < 2) return 0.0;
    final m = mean;
    return values.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
        (values.length - 1);
  }

  /// The sample standard deviation.
  double get stdDev => math.sqrt(variance);

  /// Calculates the [p]-th quantile (where 0.0 <= [p] <= 1.0)
  /// using linear interpolation (Type 7).
  ///
  /// It is an error if [p] is not between 0.0 and 1.0 (inclusive).
  double quantile(double p) {
    if (p < 0.0 || p > 1.0) {
      throw ArgumentError.value(p, 'p', 'Must be between 0.0 and 1.0');
    }
    if (sortedValues.isEmpty) return 0.0;
    if (sortedValues.length == 1) return sortedValues.first;

    final pos = p * (sortedValues.length - 1);
    final idx = pos.floor();
    final fraction = pos - idx;

    if (idx >= sortedValues.length - 1) {
      return sortedValues.last;
    }
    return sortedValues[idx] +
        fraction * (sortedValues[idx + 1] - sortedValues[idx]);
  }

  /// The median of the sample.
  double get median => quantile(0.5);

  /// Performs bootstrapping (Monte Carlo resampling with replacement)
  /// to estimate the 95% confidence intervals for the mean and median.
  ///
  /// The [resamples] parameter controls the number of bootstrap iterations (default: 10000).
  /// An optional [random] generator can be provided for reproducibility.
  ///
  /// Returns a [BootstrapResult] containing the bootstrapped distributions
  /// and confidence intervals.
  ///
  /// It is an error if the sample is empty.
  /// It is an error if [resamples] is less than 1.
  BootstrapResult bootstrap({int resamples = 10000, math.Random? random}) {
    if (values.isEmpty) {
      throw StateError('Cannot bootstrap an empty sample');
    }
    if (resamples < 1) {
      throw ArgumentError.value(resamples, 'resamples', 'Must be at least 1');
    }
    final r = random ?? math.Random();
    final N = values.length;

    final bootstrappedMeans = List<double>.filled(resamples, 0.0);
    final bootstrappedMedians = List<double>.filled(resamples, 0.0);

    // Reuse a buffer for the resampled values to avoid allocations
    final resampleBuffer = List<double>.filled(N, 0.0);

    for (var i = 0; i < resamples; i++) {
      for (var j = 0; j < N; j++) {
        resampleBuffer[j] = values[r.nextInt(N)];
      }

      // Calculate mean
      var sum = 0.0;
      for (var j = 0; j < N; j++) {
        sum += resampleBuffer[j];
      }
      bootstrappedMeans[i] = sum / N;

      // Calculate median: needs a sorted copy of the resample
      final sortedResample = List<double>.from(resampleBuffer)..sort();
      // Median is quantile(0.5) of the resample
      final pos = 0.5 * (N - 1);
      final idx = pos.floor();
      final fraction = pos - idx;
      if (idx >= N - 1) {
        bootstrappedMedians[i] = sortedResample.last;
      } else {
        bootstrappedMedians[i] =
            sortedResample[idx] +
            fraction * (sortedResample[idx + 1] - sortedResample[idx]);
      }
    }

    final meansSample = Sample(bootstrappedMeans);
    final mediansSample = Sample(bootstrappedMedians);

    return BootstrapResult(
      meanConfidenceInterval: ConfidenceInterval(
        lowerBound: meansSample.quantile(0.025),
        upperBound: meansSample.quantile(0.975),
      ),
      medianConfidenceInterval: ConfidenceInterval(
        lowerBound: mediansSample.quantile(0.025),
        upperBound: mediansSample.quantile(0.975),
      ),
      bootstrappedMeans: bootstrappedMeans,
      bootstrappedMedians: bootstrappedMedians,
    );
  }

  /// Analyzes the sample for outliers using Tukey's Fences.
  OutlierAnalysis analyzeOutliers() {
    if (values.length < 4) {
      return OutlierAnalysis(
        lowSevere: 0,
        lowMild: 0,
        highMild: 0,
        highSevere: 0,
        outlierVariancePercentage: 0.0,
      );
    }

    final q1 = quantile(0.25);
    final q3 = quantile(0.75);
    final iqr = q3 - q1;

    final loS = q1 - 3.0 * iqr;
    final loM = q1 - 1.5 * iqr;
    final hiM = q3 + 1.5 * iqr;
    final hiS = q3 + 3.0 * iqr;

    var lowSevereCount = 0;
    var lowMildCount = 0;
    var highMildCount = 0;
    var highSevereCount = 0;

    final cleanValues = <double>[];

    for (final x in values) {
      if (x < loS) {
        lowSevereCount++;
      } else if (x < loM) {
        lowMildCount++;
      } else if (x > hiS) {
        highSevereCount++;
      } else if (x > hiM) {
        highMildCount++;
      } else {
        cleanValues.add(x);
      }
    }

    double outlierVarPct = 0.0;
    if (variance > 0.0 && cleanValues.length >= 2) {
      final cleanSample = Sample(cleanValues);
      final cleanVar = cleanSample.variance;
      outlierVarPct = math.max(0.0, (variance - cleanVar) / variance) * 100.0;
    }

    return OutlierAnalysis(
      lowSevere: lowSevereCount,
      lowMild: lowMildCount,
      highMild: highMildCount,
      highSevere: highSevereCount,
      outlierVariancePercentage: outlierVarPct,
    );
  }
}

/// Represents a 95% confidence interval.
final class ConfidenceInterval {
  /// The lower bound of the interval.
  final double lowerBound;

  /// The upper bound of the interval.
  final double upperBound;

  /// Creates a [ConfidenceInterval].
  ConfidenceInterval({required this.lowerBound, required this.upperBound});

  /// Creates a [ConfidenceInterval] from a JSON map.
  factory ConfidenceInterval.fromJson(Map<String, dynamic> json) {
    return ConfidenceInterval(
      lowerBound: (json["lowerBound"] as num).toDouble(),
      upperBound: (json["upperBound"] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      '[${lowerBound.toStringAsFixed(2)}, ${upperBound.toStringAsFixed(2)}]';
}

/// The result of the bootstrapping process.
final class BootstrapResult {
  /// The estimated confidence interval for the mean.
  final ConfidenceInterval meanConfidenceInterval;

  /// The estimated confidence interval for the median.
  final ConfidenceInterval medianConfidenceInterval;

  /// The raw bootstrapped mean values.
  final List<double> bootstrappedMeans;

  /// The raw bootstrapped median values.
  final List<double> bootstrappedMedians;

  /// Creates a [BootstrapResult].
  BootstrapResult({
    required this.meanConfidenceInterval,
    required this.medianConfidenceInterval,
    required this.bootstrappedMeans,
    required this.bootstrappedMedians,
  });
}

/// The result of the outlier analysis.
final class OutlierAnalysis {
  /// The number of low severe outliers (below Q1 - 3.0 * IQR).
  final int lowSevere;

  /// The number of low mild outliers (between Q1 - 3.0 * IQR and Q1 - 1.5 * IQR).
  final int lowMild;

  /// The number of high mild outliers (between Q3 + 1.5 * IQR and Q3 + 3.0 * IQR).
  final int highMild;

  /// The number of high severe outliers (above Q3 + 3.0 * IQR).
  final int highSevere;

  /// The percentage of variance attributable to outliers.
  final double outlierVariancePercentage;

  /// Creates an [OutlierAnalysis].
  OutlierAnalysis({
    required this.lowSevere,
    required this.lowMild,
    required this.highMild,
    required this.highSevere,
    required this.outlierVariancePercentage,
  });

  /// Creates an [OutlierAnalysis] from a JSON map.
  factory OutlierAnalysis.fromJson(Map<String, dynamic> json) {
    return OutlierAnalysis(
      lowSevere: json["lowSevere"] as int,
      lowMild: json["lowMild"] as int,
      highMild: json["highMild"] as int,
      highSevere: json["highSevere"] as int,
      outlierVariancePercentage: (json["outlierVariancePercentage"] as num)
          .toDouble(),
    );
  }

  /// The total number of detected outliers.
  int get totalOutliers => lowSevere + lowMild + highMild + highSevere;
}
