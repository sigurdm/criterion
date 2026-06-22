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
