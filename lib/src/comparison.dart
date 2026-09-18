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

import "dart:convert";
import "dart:math" as math;
import "result.dart";
import "statistics.dart";

/// Represents the comparison of a single metric.
final class MetricComparison {
  /// The value before.
  final double before;

  /// The value after.
  final double after;

  /// The absolute difference (after - before).
  double get diff => after - before;

  /// The percentage difference relative to before.
  double get percentDiff {
    if (before == 0) {
      if (diff == 0) return 0.0;
      return diff > 0 ? double.infinity : double.negativeInfinity;
    }
    return (diff / before) * 100;
  }

  /// Creates a [MetricComparison].
  MetricComparison(this.before, this.after);
}

/// Represents the comparison of a single benchmark.
final class BenchmarkComparison {
  /// The name of the benchmark.
  final String name;

  /// The platform flavor.
  final String platform;

  /// The parameter value, if any.
  final dynamic parameterValue;

  /// The time comparison.
  final MetricComparison time;

  /// Whether the time difference is statistically significant (95% CI overlap).
  final bool timeSignificant;

  /// The p-value calculated via two-sample bootstrap hypothesis testing, if available.
  final double? pValue;

  /// Whether the difference was within the configured noise threshold.
  final bool withinNoiseThreshold;

  /// The allocated bytes comparison, if available.
  final MetricComparison? allocatedBytes;

  /// The allocated objects comparison, if available.
  final MetricComparison? allocatedObjects;

  /// The instructions comparison, if available.
  final MetricComparison? instructions;

  /// The CPU cycles comparison, if available.
  final MetricComparison? cycles;

  /// Creates a [BenchmarkComparison].
  BenchmarkComparison({
    required this.name,
    required this.platform,
    required this.parameterValue,
    required this.time,
    required this.timeSignificant,
    this.pValue,
    this.withinNoiseThreshold = false,
    this.allocatedBytes,
    this.allocatedObjects,
    this.instructions,
    this.cycles,
  });

  /// Converts this [BenchmarkComparison] to a JSON-encodable map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'platform': platform,
    if (parameterValue != null) 'parameterValue': parameterValue,
    'time': {'before': time.before, 'after': time.after},
    'timeSignificant': timeSignificant,
    if (pValue != null) 'pValue': pValue,
    'withinNoiseThreshold': withinNoiseThreshold,
    if (allocatedBytes != null)
      'allocatedBytes': {
        'before': allocatedBytes!.before,
        'after': allocatedBytes!.after,
      },
    if (allocatedObjects != null)
      'allocatedObjects': {
        'before': allocatedObjects!.before,
        'after': allocatedObjects!.after,
      },
    if (instructions != null)
      'instructions': {
        'before': instructions!.before,
        'after': instructions!.after,
      },
    if (cycles != null)
      'cycles': {'before': cycles!.before, 'after': cycles!.after},
  };

  /// Creates a [BenchmarkComparison] from a JSON map.
  factory BenchmarkComparison.fromJson(Map<String, dynamic> json) {
    final timeMap = json['time'] as Map<String, dynamic>;
    final bytesMap = json['allocatedBytes'] as Map<String, dynamic>?;
    final objectsMap = json['allocatedObjects'] as Map<String, dynamic>?;
    final instMap = json['instructions'] as Map<String, dynamic>?;
    final cyclesMap = json['cycles'] as Map<String, dynamic>?;

    return BenchmarkComparison(
      name: json['name'] as String,
      platform: (json['platform'] as String?) ?? '',
      parameterValue: json['parameterValue'],
      time: MetricComparison(
        (timeMap['before'] as num).toDouble(),
        (timeMap['after'] as num).toDouble(),
      ),
      timeSignificant: (json['timeSignificant'] as bool?) ?? false,
      pValue: (json['pValue'] as num?)?.toDouble(),
      withinNoiseThreshold: (json['withinNoiseThreshold'] as bool?) ?? false,
      allocatedBytes: bytesMap != null
          ? MetricComparison(
              (bytesMap['before'] as num).toDouble(),
              (bytesMap['after'] as num).toDouble(),
            )
          : null,
      allocatedObjects: objectsMap != null
          ? MetricComparison(
              (objectsMap['before'] as num).toDouble(),
              (objectsMap['after'] as num).toDouble(),
            )
          : null,
      instructions: instMap != null
          ? MetricComparison(
              (instMap['before'] as num).toDouble(),
              (instMap['after'] as num).toDouble(),
            )
          : null,
      cycles: cyclesMap != null
          ? MetricComparison(
              (cyclesMap['before'] as num).toDouble(),
              (cyclesMap['after'] as num).toDouble(),
            )
          : null,
    );
  }
}

/// Represents the comparison of two benchmark suites.
final class SuiteComparison {
  /// The compared benchmarks that are present in both suites.
  final List<BenchmarkComparison> compared;

  /// The names of benchmarks that were removed (only in before).
  final List<String> removed;

  /// The names of benchmarks that were added (only in after).
  final List<String> added;

  /// Creates a [SuiteComparison].
  SuiteComparison({
    required this.compared,
    required this.removed,
    required this.added,
  });

  /// Returns the list of benchmarks that showed a statistically significant regression.
  List<BenchmarkComparison> get regressions =>
      compared.where((c) => c.timeSignificant && c.time.diff > 0).toList();

  /// Formats the comparison as a Markdown table.
  String toMarkdownTable() {
    if (compared.isEmpty && added.isEmpty && removed.isEmpty) {
      return "No results to compare.";
    }

    final hasPlatform = compared.any((c) => c.platform.isNotEmpty);
    final hasParameter = compared.any((c) => c.parameterValue != null);
    final hasMemory = compared.any(
      (c) => c.allocatedBytes != null || c.allocatedObjects != null,
    );
    final hasInstructions = compared.any((c) => c.instructions != null);
    final hasCycles = compared.any((c) => c.cycles != null);

    final headers = [
      "Benchmark",
      if (hasPlatform) "Platform",
      if (hasParameter) "Parameter",
      "Time (before)",
      "Time (after)",
      "Delta (%)",
      "Significant?",
      if (hasMemory) ...[
        "Memory (before)",
        "Memory (after)",
        "Delta (%)",
        "Objects (before)",
        "Objects (after)",
        "Delta (%)",
      ],
      if (hasInstructions) ...[
        "Instructions (before)",
        "Instructions (after)",
        "Delta (%)",
      ],
      if (hasCycles) ...["Cycles (before)", "Cycles (after)", "Delta (%)"],
    ];

    final sb = StringBuffer();
    sb.writeln("| ${headers.join(" | ")} |");
    sb.writeln("| ${headers.map((_) => "---").join(" | ")} |");

    for (final c in compared) {
      final timeDelta = _formatPercent(c.time.percentDiff);
      final timeSign = c.withinNoiseThreshold
          ? "No change (noise)"
          : (c.timeSignificant ? "Yes" : "No");

      final row = [
        c.name,
        if (hasPlatform) c.platform,
        if (hasParameter) c.parameterValue?.toString() ?? "N/A",
        _formatDuration(c.time.before),
        _formatDuration(c.time.after),
        "${_formatDiff(c.time.diff, _formatDuration)} ($timeDelta)",
        timeSign,
        if (hasMemory) ...[
          c.allocatedBytes != null
              ? _formatBytes(c.allocatedBytes!.before)
              : "N/A",
          c.allocatedBytes != null
              ? _formatBytes(c.allocatedBytes!.after)
              : "N/A",
          c.allocatedBytes != null
              ? "${_formatDiff(c.allocatedBytes!.diff, _formatBytes)} (${_formatPercent(c.allocatedBytes!.percentDiff)})"
              : "N/A",
          c.allocatedObjects != null
              ? _formatCount(c.allocatedObjects!.before)
              : "N/A",
          c.allocatedObjects != null
              ? _formatCount(c.allocatedObjects!.after)
              : "N/A",
          c.allocatedObjects != null
              ? "${_formatDiff(c.allocatedObjects!.diff, _formatCount)} (${_formatPercent(c.allocatedObjects!.percentDiff)})"
              : "N/A",
        ],
        if (hasInstructions) ...[
          c.instructions != null ? _formatCount(c.instructions!.before) : "N/A",
          c.instructions != null ? _formatCount(c.instructions!.after) : "N/A",
          c.instructions != null
              ? "${_formatDiff(c.instructions!.diff, _formatCount)} (${_formatPercent(c.instructions!.percentDiff)})"
              : "N/A",
        ],
        if (hasCycles) ...[
          c.cycles != null ? _formatCount(c.cycles!.before) : "N/A",
          c.cycles != null ? _formatCount(c.cycles!.after) : "N/A",
          c.cycles != null
              ? "${_formatDiff(c.cycles!.diff, _formatCount)} (${_formatPercent(c.cycles!.percentDiff)})"
              : "N/A",
        ],
      ];
      sb.writeln("| ${row.join(" | ")} |");
    }

    if (removed.isNotEmpty) {
      sb.writeln("\n### Removed Benchmarks");
      for (final key in removed) {
        sb.writeln("- $key");
      }
    }

    if (added.isNotEmpty) {
      sb.writeln("\n### Added Benchmarks");
      for (final key in added) {
        sb.writeln("- $key");
      }
    }

    return sb.toString();
  }
}

String _comparisonKey(BenchmarkResult r) {
  final parts = [r.name];
  if (r.platform.isNotEmpty) parts.add(r.platform);
  if (r.parameterValue != null) parts.add(r.parameterValue.toString());
  return parts.join('::');
}

/// Computes the two-sample bootstrap p-value under the null hypothesis H0: mu_A = mu_B.
double _twoSampleBootstrapPValue(
  List<double> a,
  List<double> b, {
  int resamples = 2000,
}) {
  final meanA = a.reduce((x, y) => x + y) / a.length;
  final meanB = b.reduce((x, y) => x + y) / b.length;
  final obsDiff = (meanA - meanB).abs();

  final totalN = a.length + b.length;
  final pooledSum = a.reduce((x, y) => x + y) + b.reduce((x, y) => x + y);
  final pooledMean = pooledSum / totalN;

  final aShifted = a.map((x) => x - meanA + pooledMean).toList();
  final bShifted = b.map((y) => y - meanB + pooledMean).toList();

  final random = math.Random(42);
  var extremeCount = 0;

  final lenA = aShifted.length;
  final lenB = bShifted.length;

  for (var i = 0; i < resamples; i++) {
    var sumA = 0.0;
    for (var j = 0; j < lenA; j++) {
      sumA += aShifted[random.nextInt(lenA)];
    }
    final bootMeanA = sumA / lenA;

    var sumB = 0.0;
    for (var j = 0; j < lenB; j++) {
      sumB += bShifted[random.nextInt(lenB)];
    }
    final bootMeanB = sumB / lenB;

    if ((bootMeanA - bootMeanB).abs() >= obsDiff) {
      extremeCount++;
    }
  }

  return extremeCount / resamples;
}

/// Compares two lists of benchmark results.
SuiteComparison compareResults(
  List<BenchmarkResult> before,
  List<BenchmarkResult> after, {
  double noiseThreshold = 0.01,
}) {
  final beforeMap = {for (var r in before) _comparisonKey(r): r};
  final afterMap = {for (var r in after) _comparisonKey(r): r};

  final compared = <BenchmarkComparison>[];
  final removed = <String>[];
  final added = <String>[];

  for (final key in beforeMap.keys) {
    if (!afterMap.containsKey(key)) {
      removed.add(key);
    }
  }

  for (final key in afterMap.keys) {
    if (!beforeMap.containsKey(key)) {
      added.add(key);
    }
  }

  // Sort keys for deterministic output
  final matchedKeys =
      beforeMap.keys.where((key) => afterMap.containsKey(key)).toList()..sort();
  removed.sort();
  added.sort();

  for (final key in matchedKeys) {
    final b = beforeMap[key]!;
    final a = afterMap[key]!;

    final bMeanCI = (b.net != null && b.noOp != null)
        ? ConfidenceInterval(
            lowerBound: (b.primary.meanCI.lowerBound - b.noOp!.mean).clamp(
              0.0,
              double.infinity,
            ),
            upperBound: (b.primary.meanCI.upperBound - b.noOp!.mean).clamp(
              0.0,
              double.infinity,
            ),
          )
        : b.primary.meanCI;
    final aMeanCI = (a.net != null && a.noOp != null)
        ? ConfidenceInterval(
            lowerBound: (a.primary.meanCI.lowerBound - a.noOp!.mean).clamp(
              0.0,
              double.infinity,
            ),
            upperBound: (a.primary.meanCI.upperBound - a.noOp!.mean).clamp(
              0.0,
              double.infinity,
            ),
          )
        : a.primary.meanCI;
    final bool statisticallyDifferent;
    final double? pVal;

    final bNoOpMean = (b.net != null && b.noOp != null) ? b.noOp!.mean : 0.0;
    final aNoOpMean = (a.net != null && a.noOp != null) ? a.noOp!.mean : 0.0;
    final bTimes = bNoOpMean > 0
        ? b.primary.sampleTimes
              .map((t) => (t - bNoOpMean).clamp(0.0, double.infinity))
              .toList()
        : b.primary.sampleTimes;
    final aTimes = aNoOpMean > 0
        ? a.primary.sampleTimes
              .map((t) => (t - aNoOpMean).clamp(0.0, double.infinity))
              .toList()
        : a.primary.sampleTimes;

    if (bTimes.length >= 2 &&
        aTimes.length >= 2 &&
        (b.primary.stdDev > 0 || a.primary.stdDev > 0)) {
      final p = _twoSampleBootstrapPValue(bTimes, aTimes);
      pVal = p;
      statisticallyDifferent =
          (p < 0.05 && !_intervalsOverlap(bMeanCI, aMeanCI)) || p < 0.01;
    } else {
      final diff = !_intervalsOverlap(bMeanCI, aMeanCI);
      pVal = diff ? 0.0 : 1.0;
      statisticallyDifferent = diff;
    }

    final bTime = b.net?.timeNs ?? b.primary.mean;
    final aTime = a.net?.timeNs ?? a.primary.mean;
    final timeComp = MetricComparison(bTime, aTime);
    final exceedsNoise = timeComp.percentDiff.abs() > (noiseThreshold * 100.0);

    final bool timeSignificant;
    final bool withinNoiseThreshold;

    if (statisticallyDifferent && !exceedsNoise) {
      timeSignificant = false;
      withinNoiseThreshold = true;
    } else if (statisticallyDifferent && exceedsNoise) {
      timeSignificant = true;
      withinNoiseThreshold = false;
    } else {
      timeSignificant = false;
      withinNoiseThreshold = false;
    }

    final bBytes =
        b.net?.allocatedBytes ?? b.primary.memory?.allocatedBytesPerIteration;
    final aBytes =
        a.net?.allocatedBytes ?? a.primary.memory?.allocatedBytesPerIteration;
    MetricComparison? bytes;
    if (bBytes != null && aBytes != null) {
      bytes = MetricComparison(bBytes, aBytes);
    }

    final bObjects =
        b.net?.allocatedObjects ??
        b.primary.memory?.allocatedObjectsPerIteration;
    final aObjects =
        a.net?.allocatedObjects ??
        a.primary.memory?.allocatedObjectsPerIteration;
    MetricComparison? objects;
    if (bObjects != null && aObjects != null) {
      objects = MetricComparison(bObjects, aObjects);
    }

    final bInst =
        b.net?.instructions ?? b.primary.instructions?.instructionsPerIteration;
    final aInst =
        a.net?.instructions ?? a.primary.instructions?.instructionsPerIteration;
    MetricComparison? inst;
    if (bInst != null && aInst != null) {
      inst = MetricComparison(bInst, aInst);
    }

    final bCycles = b.net?.cycles ?? b.primary.cyclesPerIteration;
    final aCycles = a.net?.cycles ?? a.primary.cyclesPerIteration;
    MetricComparison? cycles;
    if (bCycles != null && aCycles != null) {
      cycles = MetricComparison(bCycles, aCycles);
    }

    compared.add(
      BenchmarkComparison(
        name: a.name,
        platform: a.platform,
        parameterValue: a.parameterValue,
        time: timeComp,
        timeSignificant: timeSignificant,
        pValue: pVal,
        withinNoiseThreshold: withinNoiseThreshold,
        allocatedBytes: bytes,
        allocatedObjects: objects,
        instructions: inst,
        cycles: cycles,
      ),
    );
  }

  return SuiteComparison(compared: compared, removed: removed, added: added);
}

bool _intervalsOverlap(ConfidenceInterval a, ConfidenceInterval b) {
  return a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound;
}

String _formatDuration(double ns) {
  final absNs = ns.abs();
  if (absNs < 1.0) {
    return "${(ns * 1000).toStringAsFixed(2)} ps";
  }
  if (absNs < 1000.0) {
    return "${ns.toStringAsFixed(2)} ns";
  }
  final us = ns / 1000.0;
  final absUs = us.abs();
  if (absUs < 1000.0) {
    return "${us.toStringAsFixed(2)} μs";
  }
  final ms = us / 1000.0;
  final absMs = ms.abs();
  if (absMs < 1000.0) {
    return "${ms.toStringAsFixed(2)} ms";
  }
  final s = ms / 1000.0;
  return "${s.toStringAsFixed(2)} s";
}

String _formatBytes(double bytes) {
  final absBytes = bytes.abs();
  if (absBytes < 1024) {
    return "${bytes.toStringAsFixed(1)} B";
  }
  final kb = bytes / 1024;
  final absKb = kb.abs();
  if (absKb < 1024) {
    return "${kb.toStringAsFixed(1)} KB";
  }
  final mb = kb / 1024;
  return "${mb.toStringAsFixed(1)} MB";
}

String _formatCount(double count) {
  if (count.abs() < 1000) {
    return count.toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "");
  }
  final intCount = count.round();
  final str = intCount.toString();
  final buffer = StringBuffer();
  final isNegative = str.startsWith("-");
  final digits = isNegative ? str.substring(1) : str;

  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(",");
    }
    buffer.write(digits[i]);
  }
  return (isNegative ? "-" : "") + buffer.toString();
}

String _formatPercent(double pct) {
  if (pct.isNaN) return "N/A";
  if (pct.isInfinite) return pct > 0 ? "+∞%" : "-∞%";
  final sign = pct > 0 ? "+" : "";
  return "$sign${pct.toStringAsFixed(2)}%";
}

String _formatDiff(double diff, String Function(double) formatter) {
  final sign = diff > 0 ? "+" : "";
  return "$sign${formatter(diff)}";
}

/// Parses a list of [BenchmarkResult]s from a JSON string.
List<BenchmarkResult> loadResults(String jsonString) {
  final decoded = jsonDecode(jsonString);
  if (decoded is! List) {
    throw FormatException("Expected a list of benchmark results");
  }
  return decoded.map((e) {
    if (e is! Map<String, dynamic>) {
      throw FormatException("Expected a map for benchmark result");
    }
    return BenchmarkResult.fromJson(e);
  }).toList();
}

/// Formats a list of [BenchmarkResult]s as a pretty JSON string.
String formatResults(List<BenchmarkResult> results) {
  return const JsonEncoder.withIndent(
    '  ',
  ).convert(results.map((r) => r.toJson()).toList());
}
