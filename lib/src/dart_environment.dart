/// Compile-time constants for Criterion.
library;

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

/// Helper to generate `-D` flags for a given configuration.
List<String> dartDefineFlags({
  required String platform,
  required String os,
  required String dartSdkVersion,
  required bool json,
}) {
  return [
    "-Dcriterion.platform=$platform",
    "-Dcriterion.os=$os",
    "-Dcriterion.dart_sdk_version=$dartSdkVersion",
    "-Dcriterion.json=$json",
  ];
}
