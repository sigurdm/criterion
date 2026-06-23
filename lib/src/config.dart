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

  /// Whether to use Kernel-Based Steady-State Detection (KBSSD) for adaptive benchmarking.
  final bool useKbssd;

  /// The size of the sliding windows used in KBSSD.
  final int kbssdWindowSize;

  /// The number of consecutive stable samples required to declare convergence.
  final int kbssdStabilityRequired;

  /// The percentage of extreme values to trim from the windows.
  final double kbssdTrimPercentage;

  /// The scale factor applied to the relative MAD of the cold buffer to determine the threshold.
  final double kbssdScaleFactor;

  /// The maximum number of samples to collect before giving up.
  final int kbssdMaxSamples;

  /// Creates a new [CriterionConfig] instance.
  const CriterionConfig({
    this.generateHtmlReport = true,
    this.exportJson = true,
    this.reportDir = 'benchmark/report',
    this.useKbssd = false,
    this.kbssdWindowSize = 15,
    this.kbssdStabilityRequired = 8,
    this.kbssdTrimPercentage = 0.10,
    this.kbssdScaleFactor = 2.0,
    this.kbssdMaxSamples = 200,
  });
}
