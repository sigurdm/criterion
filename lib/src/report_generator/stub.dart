import "../config.dart";
import "../result.dart";

/// Stub implementation of ReportGenerator when VM service / IO is not available.
final class ReportGenerator {
  /// The configuration options.
  final CriterionConfig config;

  /// Creates a new [ReportGenerator].
  ReportGenerator(this.config);

  /// No-op on web platforms.
  Future<void> generate(List<BenchmarkResult> results) async {
    // Do nothing.
  }
}
