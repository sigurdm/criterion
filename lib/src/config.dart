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

  /// The scale factor applied to the estimated null MMD to determine the
  /// convergence threshold.
  ///
  /// A value of `2.0` means "declare the two windows indistinguishable when
  /// their MMD is at most twice what we would expect from sampling noise
  /// alone". Larger values converge sooner.
  final double kbssdScaleFactor;

  /// The maximum number of measurements to take while waiting for the
  /// benchmark to reach a steady state.
  ///
  /// These measurements are discarded; they are the adaptive warm-up. Once
  /// steady state is reached (or this budget is exhausted), a fresh set of
  /// `samples` measurements is collected and reported.
  final int kbssdMaxSamples;

  /// Whether to measure memory allocations.
  final bool measureMemory;

  /// Whether to measure hardware instructions.
  final bool measureInstructions;

  /// Whether to measure CPU cycles.
  final bool measureCycles;

  /// An optional regular expression pattern to filter benchmarks by name.
  final String? filter;

  /// The relative change threshold below which statistically significant
  /// differences are treated as environmental noise (e.g. `0.01` for 1%).
  final double noiseThreshold;

  /// If provided, saves the current benchmark run as a named baseline.
  final String? saveBaseline;

  /// If provided, compares the current benchmark run against the named baseline.
  final String? baseline;

  /// Whether to throw or fail with a non-zero exit code when regressions are detected.
  final bool failOnRegression;

  /// Creates a new [CriterionConfig] instance.
  ///
  /// This constructor is `const` and performs no validation; call [validate]
  /// to check the field values. `Criterion.run` does so automatically.
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
    this.measureMemory = true,
    this.measureInstructions = true,
    this.measureCycles = true,
    this.filter,
    this.noiseThreshold = 0.01,
    this.saveBaseline,
    this.baseline,
    this.failOnRegression = false,
  });

  /// Checks that all field values are in range.
  ///
  /// `Criterion.run` calls this before doing any work, so a misconfigured run
  /// fails immediately rather than after minutes of measurement. Validation is
  /// a separate method rather than a constructor `assert` because the
  /// constructor is `const`, and because asserts are stripped from release and
  /// AOT builds — which is exactly where values arrive from `-D` defines and
  /// command-line flags.
  ///
  /// Throws an [ArgumentError] if:
  /// * [kbssdWindowSize] is less than 1.
  /// * [kbssdStabilityRequired] is less than 1.
  /// * [kbssdTrimPercentage] is not in `[0.0, 0.5)`.
  /// * [kbssdScaleFactor] is less than or equal to 0.0.
  /// * [kbssdMaxSamples] is less than twice [kbssdWindowSize].
  /// * [noiseThreshold] is negative.
  void validate() {
    void check(bool ok, Object? value, String name, String message) {
      if (!ok) throw ArgumentError.value(value, name, message);
    }

    check(
      kbssdWindowSize >= 1,
      kbssdWindowSize,
      'kbssdWindowSize',
      'Must be >= 1',
    );
    check(
      kbssdStabilityRequired >= 1,
      kbssdStabilityRequired,
      'kbssdStabilityRequired',
      'Must be >= 1',
    );
    check(
      kbssdTrimPercentage >= 0.0 && kbssdTrimPercentage < 0.5,
      kbssdTrimPercentage,
      'kbssdTrimPercentage',
      'Must be in [0.0, 0.5)',
    );
    check(
      kbssdScaleFactor > 0.0,
      kbssdScaleFactor,
      'kbssdScaleFactor',
      'Must be > 0.0',
    );
    check(
      kbssdMaxSamples >= kbssdWindowSize * 2,
      kbssdMaxSamples,
      'kbssdMaxSamples',
      'Must be >= kbssdWindowSize * 2 (${kbssdWindowSize * 2})',
    );
    check(
      noiseThreshold >= 0.0,
      noiseThreshold,
      'noiseThreshold',
      'Must be >= 0.0',
    );
  }

  /// Creates a copy of this configuration with the given fields replaced.
  CriterionConfig copyWith({
    bool? generateHtmlReport,
    bool? exportJson,
    String? reportDir,
    bool? exportHistory,
    bool? checkRegressions,
    bool? cpuProfiling,
    String? historyFile,
    bool? useKbssd,
    int? kbssdWindowSize,
    int? kbssdStabilityRequired,
    double? kbssdTrimPercentage,
    double? kbssdScaleFactor,
    int? kbssdMaxSamples,
    bool? measureMemory,
    bool? measureInstructions,
    bool? measureCycles,
    String? filter,
    double? noiseThreshold,
    String? saveBaseline,
    String? baseline,
    bool? failOnRegression,
  }) {
    return CriterionConfig(
      generateHtmlReport: generateHtmlReport ?? this.generateHtmlReport,
      exportJson: exportJson ?? this.exportJson,
      reportDir: reportDir ?? this.reportDir,
      exportHistory: exportHistory ?? this.exportHistory,
      checkRegressions: checkRegressions ?? this.checkRegressions,
      cpuProfiling: cpuProfiling ?? this.cpuProfiling,
      historyFile: historyFile ?? this.historyFile,
      useKbssd: useKbssd ?? this.useKbssd,
      kbssdWindowSize: kbssdWindowSize ?? this.kbssdWindowSize,
      kbssdStabilityRequired:
          kbssdStabilityRequired ?? this.kbssdStabilityRequired,
      kbssdTrimPercentage: kbssdTrimPercentage ?? this.kbssdTrimPercentage,
      kbssdScaleFactor: kbssdScaleFactor ?? this.kbssdScaleFactor,
      kbssdMaxSamples: kbssdMaxSamples ?? this.kbssdMaxSamples,
      measureMemory: measureMemory ?? this.measureMemory,
      measureInstructions: measureInstructions ?? this.measureInstructions,
      measureCycles: measureCycles ?? this.measureCycles,
      filter: filter ?? this.filter,
      noiseThreshold: noiseThreshold ?? this.noiseThreshold,
      saveBaseline: saveBaseline ?? this.saveBaseline,
      baseline: baseline ?? this.baseline,
      failOnRegression: failOnRegression ?? this.failOnRegression,
    );
  }
}
