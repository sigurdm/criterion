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

import "statistics.dart";
import "platform_info.dart" as platform_info;

/// Represents the host environment where the benchmark was run.
final class HostEnvironment {
  /// The operating system of the host.
  final String os;

  /// The Dart SDK version of the host.
  final String dartSdkVersion;

  /// Creates a new [HostEnvironment].
  HostEnvironment({required this.os, required this.dartSdkVersion});

  /// Converts this environment to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {"os": os, "dartSdkVersion": dartSdkVersion};
  }

  /// Creates a [HostEnvironment] from a JSON map.
  factory HostEnvironment.fromJson(Map<String, dynamic> json) {
    return HostEnvironment(
      os: json["os"] as String,
      dartSdkVersion: json["dartSdkVersion"] as String,
    );
  }
}

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

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      "sampleTimes": sampleTimes,
      "mean": mean,
      "median": median,
      "stdDev": stdDev,
      "meanCI": {
        "lowerBound": meanCI.lowerBound,
        "upperBound": meanCI.upperBound,
      },
      "medianCI": {
        "lowerBound": medianCI.lowerBound,
        "upperBound": medianCI.upperBound,
      },
      "outliers": {
        "lowSevere": outliers.lowSevere,
        "lowMild": outliers.lowMild,
        "highMild": outliers.highMild,
        "highSevere": outliers.highSevere,
        "outlierVariancePercentage": outliers.outlierVariancePercentage,
      },
      if (memory != null)
        "memory": {
          "allocatedBytesPerIteration": memory!.allocatedBytesPerIteration,
          "allocatedObjectsPerIteration": memory!.allocatedObjectsPerIteration,
          "rssDeltaBytes": memory!.rssDeltaBytes,
        },
      if (instructions != null)
        "instructions": {
          "instructionsPerIteration": instructions!.instructionsPerIteration,
        },
    };
  }

  /// Creates a [MeasurementResult] from a JSON map.
  factory MeasurementResult.fromJson(Map<String, dynamic> json) {
    final meanCI = json["meanCI"] as Map<String, dynamic>;
    final medianCI = json["medianCI"] as Map<String, dynamic>;
    final outliers = json["outliers"] as Map<String, dynamic>;
    final memoryJson = json["memory"] as Map<String, dynamic>?;
    final instructionsJson = json["instructions"] as Map<String, dynamic>?;

    return MeasurementResult(
      sampleTimes: (json["sampleTimes"] as List).cast<double>(),
      mean: (json["mean"] as num).toDouble(),
      median: (json["median"] as num).toDouble(),
      stdDev: (json["stdDev"] as num).toDouble(),
      meanCI: ConfidenceInterval(
        lowerBound: (meanCI["lowerBound"] as num).toDouble(),
        upperBound: (meanCI["upperBound"] as num).toDouble(),
      ),
      medianCI: ConfidenceInterval(
        lowerBound: (medianCI["lowerBound"] as num).toDouble(),
        upperBound: (medianCI["upperBound"] as num).toDouble(),
      ),
      outliers: OutlierAnalysis(
        lowSevere: outliers["lowSevere"] as int,
        lowMild: outliers["lowMild"] as int,
        highMild: outliers["highMild"] as int,
        highSevere: outliers["highSevere"] as int,
        outlierVariancePercentage:
            (outliers["outlierVariancePercentage"] as num).toDouble(),
      ),
      memory: memoryJson == null
          ? null
          : MemoryResult(
              allocatedBytesPerIteration:
                  (memoryJson["allocatedBytesPerIteration"] as num?)
                      ?.toDouble(),
              allocatedObjectsPerIteration:
                  (memoryJson["allocatedObjectsPerIteration"] as num?)
                      ?.toDouble(),
              rssDeltaBytes: memoryJson["rssDeltaBytes"] as int,
            ),
      instructions: instructionsJson == null
          ? null
          : InstructionResult(
              instructionsPerIteration:
                  (instructionsJson["instructionsPerIteration"] as num)
                      .toDouble(),
            ),
    );
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

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      "timeNs": timeNs,
      if (allocatedBytes != null) "allocatedBytes": allocatedBytes,
      if (allocatedObjects != null) "allocatedObjects": allocatedObjects,
      if (instructions != null) "instructions": instructions,
    };
  }

  /// Creates a [NetResult] from a JSON map.
  factory NetResult.fromJson(Map<String, dynamic> json) {
    return NetResult(
      timeNs: (json["timeNs"] as num).toDouble(),
      allocatedBytes: (json["allocatedBytes"] as num?)?.toDouble(),
      allocatedObjects: (json["allocatedObjects"] as num?)?.toDouble(),
      instructions: (json["instructions"] as num?)?.toDouble(),
    );
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

  /// The host environment where the benchmark was run.
  final HostEnvironment hostEnvironment;

  /// The platform flavor.
  final String platform;

  /// The timestamp of the benchmark run.
  final DateTime timestamp;

  /// The variant group name, if this benchmark is part of a variant group.
  final String? variantGroup;

  /// The variant name, if this benchmark is part of a variant group.
  final String? variantName;

  /// Creates a new [BenchmarkResult].
  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.primary,
    this.noOp,
    this.net,
    HostEnvironment? hostEnvironment,
    String? platform,
    DateTime? timestamp,
    this.variantGroup,
    this.variantName,
  }) : hostEnvironment = hostEnvironment ?? _defaultHostEnvironment(),
       platform =
           platform ??
           const String.fromEnvironment(
             "criterion.platform",
             defaultValue: "jit",
           ),
       timestamp = timestamp ?? DateTime.now();

  static HostEnvironment _defaultHostEnvironment() {
    const envOs = String.fromEnvironment(
      "criterion.os",
      defaultValue: "unknown",
    );
    const envSdk = String.fromEnvironment(
      "criterion.dart_sdk_version",
      defaultValue: "unknown",
    );
    return HostEnvironment(
      os: envOs != "unknown" ? envOs : platform_info.localOs,
      dartSdkVersion: envSdk != "unknown"
          ? envSdk
          : platform_info.localDartSdkVersion,
    );
  }

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "iterations": iterations,
      "primary": primary.toJson(),
      if (noOp != null) "noOp": noOp!.toJson(),
      if (net != null) "net": net!.toJson(),
      "hostEnvironment": hostEnvironment.toJson(),
      "platform": platform,
      "timestamp": timestamp.toIso8601String(),
      if (variantGroup != null) "variantGroup": variantGroup,
      if (variantName != null) "variantName": variantName,
    };
  }

  /// Creates a [BenchmarkResult] from a JSON map.
  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      name: json["name"] as String,
      iterations: json["iterations"] as int,
      primary: MeasurementResult.fromJson(
        json["primary"] as Map<String, dynamic>,
      ),
      noOp: json["noOp"] == null
          ? null
          : MeasurementResult.fromJson(json["noOp"] as Map<String, dynamic>),
      net: json["net"] == null
          ? null
          : NetResult.fromJson(json["net"] as Map<String, dynamic>),
      hostEnvironment: HostEnvironment.fromJson(
        json["hostEnvironment"] as Map<String, dynamic>,
      ),
      platform: json["platform"] as String,
      timestamp: DateTime.parse(json["timestamp"] as String),
      variantGroup: json["variantGroup"] as String?,
      variantName: json["variantName"] as String?,
    );
  }
}

/// Represents the result of a memory measurement phase.
final class MemoryResult {
  /// The average number of bytes allocated per iteration.
  final double? allocatedBytesPerIteration;

  /// The average number of objects allocated per iteration.
  final double? allocatedObjectsPerIteration;

  /// The total RSS delta during the measurement phase.
  final int rssDeltaBytes;

  /// Creates a new [MemoryResult].
  MemoryResult({
    required this.allocatedBytesPerIteration,
    required this.allocatedObjectsPerIteration,
    required this.rssDeltaBytes,
  });
}

/// Represents the result of a hardware CPU instruction measurement phase.
final class InstructionResult {
  /// The average number of CPU instructions executed per iteration.
  final double instructionsPerIteration;

  /// Creates an [InstructionResult].
  InstructionResult({required this.instructionsPerIteration});
}
