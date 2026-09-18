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

/// Calculates the Median Absolute Deviation (MAD) of [data] given its [median].
///
/// The MAD is defined as the median of the absolute deviations from the data's median.
///
/// It is an error if [data] is empty.
double calculateMAD(List<double> data, double median) {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'Must not be empty');
  }
  final deviations = data.map((x) => (x - median).abs()).toList();
  return _median(deviations);
}

/// Helper to calculate the median of a list of values.
double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length % 2 == 1) {
    return sorted[middle];
  } else {
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}

/// Trims extreme values from the top and bottom of [window].
///
/// [trimPercentage] specifies the fraction of elements to trim from each end.
/// The number of elements trimmed from each end is `(window.length * trimPercentage).round()`.
///
/// Returns a new sorted list with the extreme values removed.
///
/// It is an error if [trimPercentage] is not between 0.0 and 0.5 (exclusive).
List<double> trimWindow(List<double> window, double trimPercentage) {
  if (trimPercentage < 0.0 || trimPercentage >= 0.5) {
    throw ArgumentError.value(
      trimPercentage,
      'trimPercentage',
      'Must be between 0.0 (inclusive) and 0.5 (exclusive)',
    );
  }
  if (window.isEmpty) return [];
  final sorted = List<double>.from(window)..sort();
  final k = (sorted.length * trimPercentage).round();
  if (k * 2 >= sorted.length) {
    return [];
  }
  return sorted.sublist(k, sorted.length - k);
}

/// Calculates the population standard deviation of [values].
///
/// It is an error if [values] is empty.
double populationStandardDeviation(List<double> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'Must not be empty');
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) /
      values.length;
  return math.sqrt(variance);
}

/// Calculates the standard error of the mean (SEM) of [values].
///
/// The SEM is calculated as the population standard deviation divided by the
/// square root of the number of samples.
///
/// It is an error if [values] is empty.
double standardErrorOfTheMean(List<double> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'Must not be empty');
  }
  final sigma = populationStandardDeviation(values);
  return sigma / math.sqrt(values.length);
}

/// Calculates the Maximum Mean Discrepancy (MMD) between [X] and [Y]
/// using a Gaussian kernel with bandwidth [sigma].
///
/// It is an error if [X] or [Y] is empty, or if [sigma] is not positive.
double calculateMMD(List<double> X, List<double> Y, double sigma) {
  if (X.isEmpty) throw ArgumentError.value(X, 'X', 'Must not be empty');
  if (Y.isEmpty) throw ArgumentError.value(Y, 'Y', 'Must not be empty');
  if (sigma <= 0.0) {
    throw ArgumentError.value(sigma, 'sigma', 'Must be positive');
  }

  final m = X.length;
  final n = Y.length;

  double kernel(double x, double y) {
    final diff = x - y;
    return math.exp(-(diff * diff) / (2.0 * sigma * sigma));
  }

  double sumXX = 0.0;
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < m; j++) {
      sumXX += kernel(X[i], X[j]);
    }
  }

  double sumXY = 0.0;
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      sumXY += kernel(X[i], Y[j]);
    }
  }

  double sumYY = 0.0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      sumYY += kernel(Y[i], Y[j]);
    }
  }

  final mmdSquared = sumXX / (m * m) - 2.0 * sumXY / (m * n) + sumYY / (n * n);
  return math.sqrt(math.max(0.0, mmdSquared));
}

/// Estimates the Maximum Mean Discrepancy expected between two halves of
/// [values] when the underlying distribution does *not* change.
///
/// [values] is repeatedly shuffled and split in half, and the MMD between the
/// two halves is computed with bandwidth [sigma] for each permutation. Because
/// shuffling destroys the time ordering, the two halves are exchangeable, so
/// the resulting statistic captures only the MMD attributable to sampling
/// noise — an estimate of the null distribution.
///
/// The [quantile]-th quantile of the permuted MMDs is returned (default:
/// 0.9), using linear interpolation.
///
/// Use this to calibrate a convergence threshold: a raw dispersion measure
/// such as a relative MAD is not comparable to an MMD, whereas this value is
/// computed by the same kernel with the same [sigma] and therefore is. It also
/// self-corrects for a degenerate bandwidth: when [sigma] is tiny the kernel
/// collapses towards a delta function and *both* the null estimate and the
/// live statistic saturate together.
///
/// An optional [random] generator can be provided; the default is seeded
/// deterministically so that convergence decisions are reproducible.
///
/// Performance considerations:
/// * Runs in $O(permutations \times n^2)$ time and $O(n)$ space.
///
/// It is an error if [values] contains fewer than two elements, if [sigma] is
/// not positive, if [permutations] is less than 1, or if [quantile] is not
/// between 0.0 and 1.0 (inclusive).
double estimateNullMmd(
  List<double> values,
  double sigma, {
  int permutations = 20,
  double quantile = 0.9,
  math.Random? random,
}) {
  if (values.length < 2) {
    throw ArgumentError.value(
      values,
      'values',
      'Must contain at least two elements',
    );
  }
  if (sigma <= 0.0) {
    throw ArgumentError.value(sigma, 'sigma', 'Must be positive');
  }
  if (permutations < 1) {
    throw ArgumentError.value(
      permutations,
      'permutations',
      'Must be at least 1',
    );
  }
  if (quantile < 0.0 || quantile > 1.0) {
    throw ArgumentError.value(
      quantile,
      'quantile',
      'Must be between 0.0 and 1.0',
    );
  }

  final rnd = random ?? math.Random(0x63726974);
  final shuffled = List<double>.from(values);
  final half = shuffled.length ~/ 2;

  final mmds = <double>[];
  for (var i = 0; i < permutations; i++) {
    shuffled.shuffle(rnd);
    mmds.add(
      calculateMMD(
        shuffled.sublist(0, half),
        shuffled.sublist(half, half * 2),
        sigma,
      ),
    );
  }
  mmds.sort();

  if (mmds.length == 1) return mmds.first;
  final pos = quantile * (mmds.length - 1);
  final idx = pos.floor();
  if (idx >= mmds.length - 1) return mmds.last;
  final fraction = pos - idx;
  return mmds[idx] + fraction * (mmds[idx + 1] - mmds[idx]);
}

/// Checks if the Standard Error of the Mean (SEM) of [window] is within
/// [tolerance] of the mean of [window].
///
/// Returns true if `SEM / mean <= tolerance`.
///
/// It is an error if [window] is empty.
bool checkSEM(List<double> window, {double tolerance = 0.03}) {
  if (window.isEmpty) {
    throw ArgumentError.value(window, 'window', 'Must not be empty');
  }
  final mean = window.reduce((a, b) => a + b) / window.length;
  if (mean == 0.0) {
    // If mean is 0, SEM must also be 0 to be within tolerance.
    // Or maybe we should check if SEM is 0.
    final sem = standardErrorOfTheMean(window);
    return sem == 0.0;
  }
  final sem = standardErrorOfTheMean(window);
  return (sem / mean.abs()) <= tolerance;
}
