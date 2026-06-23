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

import 'statistics.dart';
import 'memory_measurement.dart';
import 'instruction_measurement.dart';

/// Represents the results of a single measurement run (either primary or no-op).
final class MeasurementResult {
  /// The raw sample times in nanoseconds.
  final List<double> sampleTimes;

  /// The mean execution time in nanoseconds.
  final double mean;

  /// The median execution time in nanoseconds.
  final double median;

  /// The standard deviation in nanoseconds.
  final double stdDev;

  /// The 95% confidence interval for the mean.
  final ConfidenceInterval meanCI;

  /// The 95% confidence interval for the median.
  final ConfidenceInterval medianCI;

  /// Outlier analysis results.
  final OutlierAnalysis outliers;

  /// Memory measurement results, if available.
  final MemoryResult? memory;

  /// Instruction measurement results, if available.
  final InstructionResult? instructions;

  /// Creates a new [MeasurementResult].
  MeasurementResult({
    required this.sampleTimes,
    required this.mean,
    required this.median,
    required this.stdDev,
    required this.meanCI,
    required this.medianCI,
    required this.outliers,
    this.memory,
    this.instructions,
  });

  /// Creates a [MeasurementResult] from a JSON map.
  factory MeasurementResult.fromJson(Map<String, dynamic> json) {
    return MeasurementResult(
      sampleTimes: (json["sampleTimes"] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      mean: (json["mean"] as num).toDouble(),
      median: (json["median"] as num).toDouble(),
      stdDev: (json["stdDev"] as num).toDouble(),
      meanCI: ConfidenceInterval.fromJson(
        json["meanCI"] as Map<String, dynamic>,
      ),
      medianCI: ConfidenceInterval.fromJson(
        json["medianCI"] as Map<String, dynamic>,
      ),
      outliers: OutlierAnalysis.fromJson(
        json["outliers"] as Map<String, dynamic>,
      ),
      memory: json["memory"] != null
          ? MemoryResult.fromJson(json["memory"] as Map<String, dynamic>)
          : null,
      instructions: json["instructions"] != null
          ? InstructionResult.fromJson(
              json["instructions"] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      'sampleTimes': sampleTimes,
      'mean': mean,
      'median': median,
      'stdDev': stdDev,
      'meanCI': {
        'lowerBound': meanCI.lowerBound,
        'upperBound': meanCI.upperBound,
      },
      'medianCI': {
        'lowerBound': medianCI.lowerBound,
        'upperBound': medianCI.upperBound,
      },
      'outliers': {
        'lowSevere': outliers.lowSevere,
        'lowMild': outliers.lowMild,
        'highMild': outliers.highMild,
        'highSevere': outliers.highSevere,
        'outlierVariancePercentage': outliers.outlierVariancePercentage,
      },
      if (memory != null)
        'memory': {
          'allocatedBytesPerIteration': memory!.allocatedBytesPerIteration,
          'allocatedObjectsPerIteration': memory!.allocatedObjectsPerIteration,
          'rssDeltaBytes': memory!.rssDeltaBytes,
        },
      if (instructions != null)
        'instructions': {
          'instructionsPerIteration': instructions!.instructionsPerIteration,
        },
    };
  }
}

/// Represents the net results after subtracting no-op overhead.
final class NetResult {
  /// Net execution time in nanoseconds.
  final double timeNs;

  /// Net allocated bytes.
  final double? allocatedBytes;

  /// Net allocated objects.
  final double? allocatedObjects;

  /// Net instructions.
  final double? instructions;

  /// Creates a new [NetResult].
  NetResult({
    required this.timeNs,
    this.allocatedBytes,
    this.allocatedObjects,
    this.instructions,
  });

  /// Creates a [NetResult] from a JSON map.
  factory NetResult.fromJson(Map<String, dynamic> json) {
    return NetResult(
      timeNs: (json["timeNs"] as num).toDouble(),
      allocatedBytes: (json["allocatedBytes"] as num?)?.toDouble(),
      allocatedObjects: (json["allocatedObjects"] as num?)?.toDouble(),
      instructions: (json["instructions"] as num?)?.toDouble(),
    );
  }

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      'timeNs': timeNs,
      if (allocatedBytes != null) 'allocatedBytes': allocatedBytes,
      if (allocatedObjects != null) 'allocatedObjects': allocatedObjects,
      if (instructions != null) 'instructions': instructions,
    };
  }
}

/// Represents the complete results of a benchmark.
final class BenchmarkResult {
  /// The name of the benchmark.
  final String name;

  /// The number of iterations per sample.
  final int iterations;

  /// The primary measurement results.
  final MeasurementResult primary;

  /// The no-op measurement results, if FFI calibration was used.
  final MeasurementResult? noOp;

  /// The net results, if FFI calibration was used.
  final NetResult? net;

  /// Creates a new [BenchmarkResult].
  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.primary,
    this.noOp,
    this.net,
  });

  /// Creates a [BenchmarkResult] from a JSON map.
  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      name: json["name"] as String,
      iterations: json["iterations"] as int,
      primary: MeasurementResult.fromJson(
        json["primary"] as Map<String, dynamic>,
      ),
      noOp: json["noOp"] != null
          ? MeasurementResult.fromJson(json["noOp"] as Map<String, dynamic>)
          : null,
      net: json["net"] != null
          ? NetResult.fromJson(json["net"] as Map<String, dynamic>)
          : null,
    );
  }

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'iterations': iterations,
      'primary': primary.toJson(),
      if (noOp != null) 'noOp': noOp!.toJson(),
      if (net != null) 'net': net!.toJson(),
    };
  }
}
