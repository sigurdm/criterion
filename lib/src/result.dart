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

import "statistics.dart";
import "throughput.dart";
import "platform_info.dart" as platform_info;

/// Represents Git commit information for a benchmark run.
final class GitCommit {
  /// The full commit hash.
  final String hash;

  /// The short commit hash (e.g. 7 characters).
  final String shortHash;

  /// The commit message.
  final String message;

  /// The commit timestamp, if available.
  final DateTime? timestamp;

  /// Creates a new [GitCommit].
  GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    this.timestamp,
  });

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    "hash": hash,
    "shortHash": shortHash,
    "message": message,
    if (timestamp != null) "timestamp": timestamp!.toIso8601String(),
  };

  /// Creates a [GitCommit] from JSON.
  factory GitCommit.fromJson(Map<String, dynamic> json) => GitCommit(
    hash: json["hash"] as String,
    shortHash: json["shortHash"] as String,
    message: json["message"] as String,
    timestamp: json["timestamp"] != null
        ? DateTime.parse(json["timestamp"] as String)
        : null,
  );
}

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

  /// CPU profile results, if available.
  final CpuProfileResult? cpuProfile;

  /// The average number of CPU cycles executed per iteration, if available.
  final double? cyclesPerIteration;

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
    this.cpuProfile,
    this.cyclesPerIteration,
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
          if (memory!.classAllocations != null)
            "classAllocations": memory!.classAllocations!
                .map((c) => c.toJson())
                .toList(),
        },
      if (instructions != null)
        "instructions": {
          "instructionsPerIteration": instructions!.instructionsPerIteration,
        },
      if (cpuProfile != null) "cpuProfile": cpuProfile!.toJson(),
      if (cyclesPerIteration != null) "cyclesPerIteration": cyclesPerIteration,
    };
  }

  /// Creates a [MeasurementResult] from a JSON map.
  factory MeasurementResult.fromJson(Map<String, dynamic> json) {
    final meanCI = json["meanCI"] as Map<String, dynamic>;
    final medianCI = json["medianCI"] as Map<String, dynamic>;
    final outliers = json["outliers"] as Map<String, dynamic>;
    final memoryJson = json["memory"] as Map<String, dynamic>?;
    final instructionsJson = json["instructions"] as Map<String, dynamic>?;
    final cpuProfileJson = json["cpuProfile"] as Map<String, dynamic>?;

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
              classAllocations: (memoryJson["classAllocations"] as List?)
                  ?.map(
                    (c) => ClassAllocation.fromJson(c as Map<String, dynamic>),
                  )
                  .toList(),
            ),
      instructions: instructionsJson == null
          ? null
          : InstructionResult(
              instructionsPerIteration:
                  (instructionsJson["instructionsPerIteration"] as num)
                      .toDouble(),
            ),
      cpuProfile: cpuProfileJson == null
          ? null
          : CpuProfileResult.fromJson(cpuProfileJson),
      cyclesPerIteration: (json["cyclesPerIteration"] as num?)?.toDouble(),
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

  /// Net CPU cycles.
  final double? cycles;

  /// Creates a new [NetResult].
  NetResult({
    required this.timeNs,
    this.allocatedBytes,
    this.allocatedObjects,
    this.instructions,
    this.cycles,
  });

  /// Converts this result to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      "timeNs": timeNs,
      if (allocatedBytes != null) "allocatedBytes": allocatedBytes,
      if (allocatedObjects != null) "allocatedObjects": allocatedObjects,
      if (instructions != null) "instructions": instructions,
      if (cycles != null) "cycles": cycles,
    };
  }

  /// Creates a [NetResult] from a JSON map.
  factory NetResult.fromJson(Map<String, dynamic> json) {
    return NetResult(
      timeNs: (json["timeNs"] as num).toDouble(),
      allocatedBytes: (json["allocatedBytes"] as num?)?.toDouble(),
      allocatedObjects: (json["allocatedObjects"] as num?)?.toDouble(),
      instructions: (json["instructions"] as num?)?.toDouble(),
      cycles: (json["cycles"] as num?)?.toDouble(),
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

  /// The parameter group name, if this benchmark is part of a parameterized group.
  final String? parameterGroup;

  /// The parameter value, if this benchmark is part of a parameterized group.
  final dynamic parameterValue;

  /// The throughput configuration, if any.
  final Throughput? throughput;

  /// Git commit information, if available.
  final GitCommit? gitCommit;

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
    this.parameterGroup,
    this.parameterValue,
    this.throughput,
    GitCommit? gitCommit,
  }) : hostEnvironment = hostEnvironment ?? _defaultHostEnvironment(),
       platform =
           platform ??
           const String.fromEnvironment(
             "criterion.platform",
             defaultValue: "jit",
           ),
       timestamp = timestamp ?? DateTime.now(),
       gitCommit = gitCommit ?? platform_info.localGitCommit;

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
      if (parameterGroup != null) "parameterGroup": parameterGroup,
      if (parameterValue != null)
        "parameterValue": _serializeParameterValue(parameterValue),
      if (throughput != null) "throughput": throughput!.toJson(),
      if (gitCommit != null) "gitCommit": gitCommit!.toJson(),
    };
  }

  static dynamic _serializeParameterValue(dynamic val) {
    if (val is num || val is bool || val is String || val == null) {
      return val;
    }
    return val.toString();
  }

  /// Creates a [BenchmarkResult] from a JSON map.
  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    final throughputJson = json["throughput"] as Map<String, dynamic>?;
    final gitCommitJson = json["gitCommit"] as Map<String, dynamic>?;
    return BenchmarkResult(
      throughput: throughputJson == null
          ? null
          : Throughput.fromJson(throughputJson),
      gitCommit: gitCommitJson == null
          ? null
          : GitCommit.fromJson(gitCommitJson),
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
      parameterGroup: json["parameterGroup"] as String?,
      parameterValue: json["parameterValue"],
    );
  }
}

/// Represents memory allocations for a specific class during a benchmark.
final class ClassAllocation {
  /// The name of the class.
  final String className;

  /// The URI of the library containing the class.
  final String libraryUri;

  /// The number of bytes allocated.
  final int bytes;

  /// The number of instances allocated.
  final int instances;

  /// Creates a [ClassAllocation].
  ClassAllocation({
    required this.className,
    required this.libraryUri,
    required this.bytes,
    required this.instances,
  });

  /// Converts this to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'className': className,
    'libraryUri': libraryUri,
    'bytes': bytes,
    'instances': instances,
  };

  /// Creates a [ClassAllocation] from a JSON map.
  factory ClassAllocation.fromJson(Map<String, dynamic> json) =>
      ClassAllocation(
        className: json['className'] as String,
        libraryUri: json['libraryUri'] as String,
        bytes: json['bytes'] as int,
        instances: json['instances'] as int,
      );
}

/// Represents the result of a memory measurement phase.
final class MemoryResult {
  /// The average number of bytes allocated per iteration.
  final double? allocatedBytesPerIteration;

  /// The average number of objects allocated per iteration.
  final double? allocatedObjectsPerIteration;

  /// The total RSS delta during the measurement phase.
  final int rssDeltaBytes;

  /// Detailed allocations per class.
  final List<ClassAllocation>? classAllocations;

  /// Creates a new [MemoryResult].
  MemoryResult({
    required this.allocatedBytesPerIteration,
    required this.allocatedObjectsPerIteration,
    required this.rssDeltaBytes,
    this.classAllocations,
  });
}

/// Represents the result of a hardware CPU instruction measurement phase.
final class InstructionResult {
  /// The average number of CPU instructions executed per iteration.
  final double instructionsPerIteration;

  /// Creates an [InstructionResult].
  InstructionResult({required this.instructionsPerIteration});
}

/// Represents a function in a CPU profile.
final class CpuProfileFunction {
  /// The name of the function.
  final String name;

  /// The resolved URL of the script containing the function.
  final String resolvedUrl;

  /// The number of times the function appeared on the stack.
  final int inclusiveTicks;

  /// The number of times the function appeared on the top of the stack.
  final int exclusiveTicks;

  /// Creates a [CpuProfileFunction].
  CpuProfileFunction({
    required this.name,
    required this.resolvedUrl,
    required this.inclusiveTicks,
    required this.exclusiveTicks,
  });

  /// Converts this to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'resolvedUrl': resolvedUrl,
    'inclusiveTicks': inclusiveTicks,
    'exclusiveTicks': exclusiveTicks,
  };

  /// Creates a [CpuProfileFunction] from a JSON map.
  factory CpuProfileFunction.fromJson(Map<String, dynamic> json) =>
      CpuProfileFunction(
        name: json['name'] as String,
        resolvedUrl: json['resolvedUrl'] as String,
        inclusiveTicks: json['inclusiveTicks'] as int,
        exclusiveTicks: json['exclusiveTicks'] as int,
      );
}

/// Represents the CPU profile results.
final class CpuProfileResult {
  /// The list of functions in the profile.
  final List<CpuProfileFunction> functions;

  /// The total number of samples collected.
  final int sampleCount;

  /// The sample period in microseconds.
  final int samplePeriod;

  /// Creates a [CpuProfileResult].
  CpuProfileResult({
    required this.functions,
    required this.sampleCount,
    required this.samplePeriod,
  });

  /// Converts this to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'functions': functions.map((f) => f.toJson()).toList(),
    'sampleCount': sampleCount,
    'samplePeriod': samplePeriod,
  };

  /// Creates a [CpuProfileResult] from a JSON map.
  factory CpuProfileResult.fromJson(Map<String, dynamic> json) =>
      CpuProfileResult(
        functions: (json['functions'] as List)
            .map((f) => CpuProfileFunction.fromJson(f as Map<String, dynamic>))
            .toList(),
        sampleCount: json['sampleCount'] as int,
        samplePeriod: json['samplePeriod'] as int,
      );
}
