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

/// Compile-time constants and environment helpers for Criterion.
library;

/// Compile-time environment configuration for Criterion.
final class DartEnvironment {
  /// Creates a [DartEnvironment] instance.
  const DartEnvironment();

  /// The platform flavor we are running on (jit, aot, js, wasm).
  String get platform =>
      const String.fromEnvironment("criterion.platform", defaultValue: "jit");

  /// The target OS.
  String get os =>
      const String.fromEnvironment("criterion.os", defaultValue: "unknown");

  /// The Dart SDK version.
  String get dartSdkVersion => const String.fromEnvironment(
    "criterion.dart_sdk_version",
    defaultValue: "unknown",
  );

  /// Whether to output results as JSON to stdout.
  bool get isJson =>
      const bool.fromEnvironment("criterion.json", defaultValue: false);

  /// Filter regex pattern from `CRITERION_FILTER`.
  String get filter => const String.fromEnvironment('CRITERION_FILTER');

  /// Whether fast timing-only quick mode is enabled from `CRITERION_QUICK`.
  bool get isQuick => const bool.fromEnvironment('CRITERION_QUICK');

  /// Sample count override from `CRITERION_SAMPLES`, or -1 if not set.
  int get samplesOverride =>
      const int.fromEnvironment('CRITERION_SAMPLES', defaultValue: -1);

  /// Warmup milliseconds override from `CRITERION_WARMUP_MS`, or -1 if not set.
  int get warmupMsOverride =>
      const int.fromEnvironment('CRITERION_WARMUP_MS', defaultValue: -1);

  /// Whether HTML report generation is disabled from `CRITERION_NO_HTML`.
  bool get noHtml => const bool.fromEnvironment('CRITERION_NO_HTML');

  /// Whether all non-timing profilers are skipped from `CRITERION_TIMING_ONLY`.
  bool get timingOnly => const bool.fromEnvironment('CRITERION_TIMING_ONLY');

  /// Whether every non-timing profiler is enabled from `CRITERION_ALL_METRICS`.
  bool get allMetrics => const bool.fromEnvironment('CRITERION_ALL_METRICS');

  /// Whether memory measurement is enabled from `CRITERION_MEMORY`.
  bool get memory => const bool.fromEnvironment('CRITERION_MEMORY');

  /// Whether hardware instruction measurement is enabled from
  /// `CRITERION_INSTRUCTIONS`.
  bool get instructions => const bool.fromEnvironment('CRITERION_INSTRUCTIONS');

  /// Whether CPU cycle measurement is enabled from `CRITERION_CYCLES`.
  bool get cycles => const bool.fromEnvironment('CRITERION_CYCLES');

  /// Whether memory measurement is disabled from `CRITERION_NO_MEMORY`.
  bool get noMemory => const bool.fromEnvironment('CRITERION_NO_MEMORY');

  /// Whether hardware instruction measurement is disabled from `CRITERION_NO_INSTRUCTIONS`.
  bool get noInstructions =>
      const bool.fromEnvironment('CRITERION_NO_INSTRUCTIONS');

  /// Whether CPU cycle measurement is disabled from `CRITERION_NO_CYCLES`.
  bool get noCycles => const bool.fromEnvironment('CRITERION_NO_CYCLES');

  /// Named baseline to save from `CRITERION_SAVE_BASELINE`.
  String get saveBaseline =>
      const String.fromEnvironment('CRITERION_SAVE_BASELINE');

  /// Named baseline to compare against from `CRITERION_BASELINE`.
  String get baseline => const String.fromEnvironment('CRITERION_BASELINE');

  /// Whether to fail on regression from `CRITERION_FAIL_ON_REGRESSION`.
  bool get failOnRegression =>
      const bool.fromEnvironment('CRITERION_FAIL_ON_REGRESSION');

  /// Relative noise threshold override from `CRITERION_NOISE_THRESHOLD`.
  String get noiseThreshold =>
      const String.fromEnvironment('CRITERION_NOISE_THRESHOLD');
}

/// The default [DartEnvironment] instance.
const DartEnvironment defaultEnvironment = DartEnvironment();

/// The platform flavor we are running on (jit, aot, js, wasm).
const String platform = String.fromEnvironment(
  "criterion.platform",
  defaultValue: "jit",
);

/// The target OS.
const String os = String.fromEnvironment(
  "criterion.os",
  defaultValue: "unknown",
);

/// The Dart SDK version.
const String dartSdkVersion = String.fromEnvironment(
  "criterion.dart_sdk_version",
  defaultValue: "unknown",
);

/// Whether to output results as JSON to stdout.
const bool isJson = bool.fromEnvironment("criterion.json", defaultValue: false);

/// Filter regex pattern from `CRITERION_FILTER`.
String get filter => defaultEnvironment.filter;

/// Whether fast timing-only quick mode is enabled.
bool get isQuick => defaultEnvironment.isQuick;

/// Sample count override from `CRITERION_SAMPLES`.
int get samplesOverride => defaultEnvironment.samplesOverride;

/// Warmup milliseconds override from `CRITERION_WARMUP_MS`.
int get warmupMsOverride => defaultEnvironment.warmupMsOverride;

/// Whether HTML report generation is disabled.
bool get noHtml => defaultEnvironment.noHtml;

/// Whether all non-timing profilers are skipped.
bool get timingOnly => defaultEnvironment.timingOnly;

/// Whether every non-timing profiler is enabled.
bool get allMetrics => defaultEnvironment.allMetrics;

/// Whether memory measurement is enabled.
bool get memory => defaultEnvironment.memory;

/// Whether hardware instruction measurement is enabled.
bool get instructions => defaultEnvironment.instructions;

/// Whether CPU cycle measurement is enabled.
bool get cycles => defaultEnvironment.cycles;

/// Whether memory measurement is disabled.
bool get noMemory => defaultEnvironment.noMemory;

/// Whether hardware instruction measurement is disabled.
bool get noInstructions => defaultEnvironment.noInstructions;

/// Whether CPU cycle measurement is disabled.
bool get noCycles => defaultEnvironment.noCycles;

/// Named baseline to save from `CRITERION_SAVE_BASELINE`.
String get saveBaseline => defaultEnvironment.saveBaseline;

/// Named baseline to compare against from `CRITERION_BASELINE`.
String get baseline => defaultEnvironment.baseline;

/// Whether to fail on regression from `CRITERION_FAIL_ON_REGRESSION`.
bool get failOnRegression => defaultEnvironment.failOnRegression;

/// Relative noise threshold override from `CRITERION_NOISE_THRESHOLD`.
String get noiseThreshold => defaultEnvironment.noiseThreshold;

/// Helper to generate `-D` and `--define=` flags for a given configuration.
List<String> dartDefineFlags({
  required String platform,
  required String os,
  required String dartSdkVersion,
  required bool json,
  String? filter,
  bool quick = false,
  int? samples,
  int? warmupMs,
  bool noHtml = false,
  bool timingOnly = false,
  bool allMetrics = false,
  bool memory = false,
  bool instructions = false,
  bool cycles = false,
  bool noMemory = false,
  bool noInstructions = false,
  bool noCycles = false,
  String? saveBaseline,
  String? baseline,
  bool failOnRegression = false,
  double? noiseThreshold,
}) {
  return [
    "-Dcriterion.platform=$platform",
    "-Dcriterion.os=$os",
    "-Dcriterion.dart_sdk_version=$dartSdkVersion",
    "-Dcriterion.json=$json",
    if (filter != null && filter.isNotEmpty)
      "--define=CRITERION_FILTER=$filter",
    if (quick) "--define=CRITERION_QUICK=true",
    if (samples != null) "--define=CRITERION_SAMPLES=$samples",
    if (warmupMs != null) "--define=CRITERION_WARMUP_MS=$warmupMs",
    if (noHtml) "--define=CRITERION_NO_HTML=true",
    if (timingOnly) "--define=CRITERION_TIMING_ONLY=true",
    if (allMetrics) "--define=CRITERION_ALL_METRICS=true",
    if (memory) "--define=CRITERION_MEMORY=true",
    if (instructions) "--define=CRITERION_INSTRUCTIONS=true",
    if (cycles) "--define=CRITERION_CYCLES=true",
    if (noMemory) "--define=CRITERION_NO_MEMORY=true",
    if (noInstructions) "--define=CRITERION_NO_INSTRUCTIONS=true",
    if (noCycles) "--define=CRITERION_NO_CYCLES=true",
    if (saveBaseline != null && saveBaseline.isNotEmpty)
      "--define=CRITERION_SAVE_BASELINE=$saveBaseline",
    if (baseline != null && baseline.isNotEmpty)
      "--define=CRITERION_BASELINE=$baseline",
    if (failOnRegression) "--define=CRITERION_FAIL_ON_REGRESSION=true",
    if (noiseThreshold != null)
      "--define=CRITERION_NOISE_THRESHOLD=$noiseThreshold",
  ];
}
