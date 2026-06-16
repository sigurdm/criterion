/// Configuration options for the Criterion benchmarking framework.
final class CriterionConfig {
  /// Whether to generate an HTML report.
  final bool generateHtmlReport;

  /// Whether to export the results as JSON.
  final bool exportJson;

  /// The directory where the reports will be written.
  final String reportDir;

  /// Creates a new [CriterionConfig] instance.
  const CriterionConfig({
    this.generateHtmlReport = true,
    this.exportJson = true,
    this.reportDir = 'benchmark/report',
  });
}
