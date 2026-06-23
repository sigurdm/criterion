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
  double get percentDiff => before == 0 ? 0 : (diff / before) * 100;

  /// Creates a [MetricComparison].
  MetricComparison(this.before, this.after);
}

/// Represents the comparison of a single benchmark.
final class BenchmarkComparison {
  /// The name of the benchmark.
  final String name;

  /// The time comparison.
  final MetricComparison time;

  /// Whether the time difference is statistically significant (95% CI overlap).
  final bool timeSignificant;

  /// The allocated bytes comparison, if available.
  final MetricComparison? allocatedBytes;

  /// The allocated objects comparison, if available.
  final MetricComparison? allocatedObjects;

  /// The instructions comparison, if available.
  final MetricComparison? instructions;

  /// Creates a [BenchmarkComparison].
  BenchmarkComparison({
    required this.name,
    required this.time,
    required this.timeSignificant,
    this.allocatedBytes,
    this.allocatedObjects,
    this.instructions,
  });
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

  /// Formats the comparison as a Markdown table.
  String toMarkdownTable() {
    if (compared.isEmpty && added.isEmpty && removed.isEmpty) {
      return "No results to compare.";
    }

    final hasMemory = compared.any(
      (c) => c.allocatedBytes != null || c.allocatedObjects != null,
    );
    final hasInstructions = compared.any((c) => c.instructions != null);

    final headers = [
      "Benchmark",
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
    ];

    final sb = StringBuffer();
    sb.writeln("| ${headers.join(" | ")} |");
    sb.writeln("| ${headers.map((_) => "---").join(" | ")} |");

    for (final c in compared) {
      final timeDelta = _formatPercent(c.time.percentDiff);
      final timeSign = c.timeSignificant ? "Yes" : "No";

      final row = [
        c.name,
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
      ];
      sb.writeln("| ${row.join(" | ")} |");
    }

    if (removed.isNotEmpty) {
      sb.writeln("\n### Removed Benchmarks");
      for (final name in removed) {
        sb.writeln("- $name");
      }
    }

    if (added.isNotEmpty) {
      sb.writeln("\n### Added Benchmarks");
      for (final name in added) {
        sb.writeln("- $name");
      }
    }

    return sb.toString();
  }
}

/// Compares two lists of benchmark results.
SuiteComparison compareResults(
  List<BenchmarkResult> before,
  List<BenchmarkResult> after,
) {
  final beforeMap = {for (var r in before) r.name: r};
  final afterMap = {for (var r in after) r.name: r};

  final compared = <BenchmarkComparison>[];
  final removed = <String>[];
  final added = <String>[];

  for (final name in beforeMap.keys) {
    if (!afterMap.containsKey(name)) {
      removed.add(name);
    }
  }

  for (final name in afterMap.keys) {
    if (!beforeMap.containsKey(name)) {
      added.add(name);
    }
  }

  // Sort names for deterministic output
  final matchedNames =
      beforeMap.keys.where((name) => afterMap.containsKey(name)).toList()
        ..sort();
  removed.sort();
  added.sort();

  for (final name in matchedNames) {
    final b = beforeMap[name]!;
    final a = afterMap[name]!;
    final timeSignificant = _isSignificant(b.primary.meanCI, a.primary.meanCI);

    MetricComparison? bytes;
    if (b.primary.memory?.allocatedBytesPerIteration != null &&
        a.primary.memory?.allocatedBytesPerIteration != null) {
      bytes = MetricComparison(
        b.primary.memory!.allocatedBytesPerIteration!,
        a.primary.memory!.allocatedBytesPerIteration!,
      );
    }

    MetricComparison? objects;
    if (b.primary.memory?.allocatedObjectsPerIteration != null &&
        a.primary.memory?.allocatedObjectsPerIteration != null) {
      objects = MetricComparison(
        b.primary.memory!.allocatedObjectsPerIteration!,
        a.primary.memory!.allocatedObjectsPerIteration!,
      );
    }

    MetricComparison? inst;
    if (b.primary.instructions?.instructionsPerIteration != null &&
        a.primary.instructions?.instructionsPerIteration != null) {
      inst = MetricComparison(
        b.primary.instructions!.instructionsPerIteration,
        a.primary.instructions!.instructionsPerIteration,
      );
    }

    compared.add(
      BenchmarkComparison(
        name: name,
        time: MetricComparison(b.primary.mean, a.primary.mean),
        timeSignificant: timeSignificant,
        allocatedBytes: bytes,
        allocatedObjects: objects,
        instructions: inst,
      ),
    );
  }

  return SuiteComparison(compared: compared, removed: removed, added: added);
}

bool _isSignificant(ConfidenceInterval before, ConfidenceInterval after) {
  return before.upperBound < after.lowerBound ||
      after.upperBound < before.lowerBound;
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
  final sign = pct > 0 ? "+" : "";
  return "$sign${pct.toStringAsFixed(2)}%";
}

String _formatDiff(double diff, String Function(double) formatter) {
  final sign = diff > 0 ? "+" : "";
  return "$sign${formatter(diff)}";
}
