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

/// Configuration options for the Criterion benchmarking framework.
final class CriterionConfig {
  /// Whether to generate an HTML report.
  final bool generateHtmlReport;

  /// Whether to export the results as JSON.
  final bool exportJson;

  /// The directory where the reports will be written.
  final String reportDir;

  /// Whether to export the results to history.
  final bool exportHistory;

  /// Whether to check for regressions against history.
  final bool checkRegressions;

  /// Whether to enable CPU profiling and export profile files.
  final bool cpuProfiling;

  /// The path to the history file.
  final String historyFile;

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
  ///
  /// It is an error if:
  /// * [kbssdWindowSize] is less than 1.
  /// * [kbssdStabilityRequired] is less than 1.
  /// * [kbssdTrimPercentage] is not between 0.0 (inclusive) and 0.5 (exclusive).
  /// * [kbssdScaleFactor] is less than or equal to 0.0.
  /// * [kbssdMaxSamples] is less than double of [kbssdWindowSize].
  const CriterionConfig({
    this.generateHtmlReport = true,
    this.exportJson = true,
    this.reportDir = 'benchmark/report',
    this.exportHistory = true,
    this.checkRegressions = false,
    this.cpuProfiling = false,
    this.historyFile = 'benchmark/criterion_history.json',
    this.useKbssd = true,
    this.kbssdWindowSize = 15,
    this.kbssdStabilityRequired = 8,
    this.kbssdTrimPercentage = 0.10,
    this.kbssdScaleFactor = 2.0,
    this.kbssdMaxSamples = 200,
  }) : assert(kbssdWindowSize >= 1, 'kbssdWindowSize must be >= 1'),
       assert(
         kbssdStabilityRequired >= 1,
         'kbssdStabilityRequired must be >= 1',
       ),
       assert(
         kbssdTrimPercentage >= 0.0 && kbssdTrimPercentage < 0.5,
         'kbssdTrimPercentage must be in [0.0, 0.5)',
       ),
       assert(kbssdScaleFactor > 0.0, 'kbssdScaleFactor must be > 0.0'),
       assert(
         kbssdMaxSamples >= kbssdWindowSize * 2,
         'kbssdMaxSamples must be >= kbssdWindowSize * 2',
       );
}
