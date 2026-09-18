import "dart:convert";

import "../config.dart";
import "../result.dart";

/// Stub implementation of ReportGenerator when VM service / IO is not available.
final class ReportGenerator {
  /// The configuration options.
  final CriterionConfig config;

  /// Creates a new [ReportGenerator].
  ReportGenerator(this.config);

  /// No-op on web platforms unless [CRITERION_EMIT_RESULTS_MARKER] is enabled.
  Future<void> generate(
    List<BenchmarkResult> results, {
    List<BenchmarkResult>? history,
    String? suiteName,
  }) async {
    if (const bool.fromEnvironment('CRITERION_EMIT_RESULTS_MARKER')) {
      print(
        '__CRITERION_RESULTS_JSON__:${jsonEncode(results.map((r) => r.toJson()).toList())}',
      );
    }
  }
}
