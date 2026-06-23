# Criterion

A benchmarking framework for Dart, inspired by Rust's `criterion.rs` and the Haskell `criterion` package.

Criterion helps you write precise benchmarks by accounting for JIT warm-up, garbage collection, and system noise.

## Features

*   **Statistical analysis**: Uses bootstrapping to estimate 95% confidence intervals for both mean and median execution times.
*   **Outlier detection**: Identifies outliers and estimates how much they affect the variance of the measurements.
*   **Warm-up and calibration**: Runs a warm-up phase to allow the Dart VM to JIT-compile and optimize the code, and calibrates the number of iterations per sample to overcome clock resolution limits.
*   **Memory tracking**: Measures allocated bytes, the number of allocated Dart objects, and RSS delta per iteration using the Dart VM Service.
*   **Instruction counting**: Measures CPU instructions executed per iteration on Linux (requires performance counter access).
*   **Overhead calibration**: Subtracts a baseline `noOp` execution (e.g., an empty FFI call) to measure the net performance of your code.
*   **HTML & JSON output**: Generates interactive HTML reports with performance charts and exports raw results to JSON.

## Getting started

Add `criterion` to your `dev_dependencies` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  criterion: ^1.0.0
```

## Usage

### Basic benchmark

Define a suite and register benchmarks using `c.bench`:

```dart
import 'package:criterion/criterion.dart';

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

void main() async {
  await criterion('Fibonacci', (c) {
    c.bench('fib(10)', () {
      fib(10);
    });

    c.bench('fib(20)', () {
      fib(20);
    });
  });
}
```

### Running Benchmarks

#### Multi-Runtime CLI Tool (Recommended)
Criterion provides a multi-runtime runner that allows you to run benchmarks in different execution flavors (JIT, AOT, JS, WASM) and compare their performance.

To run a benchmark in the default AOT flavor:
```bash
dart run criterion:run benchmark/my_benchmark.dart
```

You can customize the run using the following options:
*   `-f, --flavor`: The flavor(s) to run. Options are `jit`, `aot`, `js`, `wasm`. Can be specified multiple times or as a comma-separated list. (default: `aot`).
*   `--json`: Output aggregated JSON results to stdout (suppresses normal console output and file reports).
*   `--compiler-flag`: Extra flags to pass to the compiler (e.g. `dart compile exe` or `dart compile js`).
*   `--vm-flag`: Extra flags to pass to the VM (for JIT/AOT) or Node.js (for JS/WASM).

Examples:
*   Run JIT and AOT comparison:
    ```bash
    dart run criterion:run -f jit -f aot benchmark/my_benchmark.dart
    ```
*   Run JS and WASM comparison (requires Node.js):
    ```bash
    dart run criterion:run -f js -f wasm benchmark/my_benchmark.dart
    ```
*   Output aggregated JSON results for JIT and AOT:
    ```bash
    dart run criterion:run -f jit,aot --json benchmark/my_benchmark.dart
    ```

#### JIT Mode (Direct Execution)
Alternatively, you can run the benchmark directly in JIT (Just-In-Time) mode using the Dart VM:

```bash
dart benchmark/my_benchmark.dart
```

### Grouping benchmarks

You can group related benchmarks to organize the console output and HTML reports:

```dart
import 'package:criterion/criterion.dart';

void main() async {
  await criterion('String Concatenation', (c) {
    c.group('methods', () {
      c.bench('operator +', () {
        var s = '';
        for (var i = 0; i < 100; i++) {
          s += 'a';
        }
      });

      c.bench('StringBuffer', () {
        final sb = StringBuffer();
        for (var i = 0; i < 100; i++) {
          sb.write('a');
        }
        sb.toString();
      });
    });
  });
}
```

### Benchmark Variants

If you want to compare multiple implementations of the same task, you can register them as variants using `c.variants`:

```dart
import 'package:criterion/criterion.dart';

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

int fibIter(int n) {
  if (n <= 1) return n;
  var a = 0;
  var b = 1;
  for (var i = 2; i <= n; i++) {
    final temp = a + b;
    a = b;
    b = temp;
  }
  return b;
}

void main() async {
  await criterion('Fibonacci Implementations', (c) {
    c.variants('Fibonacci', {
      'recursive': () => fib(10),
      'iterative': () => fibIter(10),
    });
  });
}
```

When you run this benchmark, Criterion will:
1.  Run both variants.
2.  Print a comparison table to the console at the end, using the first variant (`recursive` in this case) as the baseline.
3.  Include a "Variants" tab in the generated HTML report, displaying a bar chart comparing the mean execution times of all variants in the group.

Console output example:
```text
=== Variant Comparison: Fibonacci ===
| Variant | Time | Relative Speed | Significant? |
| --- | --- | --- | --- |
| recursive (baseline) | 120.50 ns | 1.00x | - |
| iterative | 12.05 ns | 10.00x (faster) | Yes |
```

### Overhead Calibration

When measuring micro-benchmarks, the overhead of the function call harness or loop structure can sometimes skew the results. You can pass a `noOp` callback to measure and subtract this baseline overhead from the primary benchmark.

A common use case is measuring and subtracting the transition overhead of Dart FFI:

```dart
import 'dart:ffi';
import 'package:criterion/criterion.dart';
import 'package:ffi/ffi.dart';

@Native<UintPtr Function(Pointer<Char>)>(symbol: 'strlen', isLeaf: true)
external int strlenLeaf(Pointer<Char> s);

void main() async {
  final str1000 = ('a' * 1000).toNativeUtf8();
  final strEmpty = ''.toNativeUtf8();

  try {
    await criterion('FFI Boundary Calibration', (c) {
      c.bench(
        'strlen (1000 chars)',
        () {
          strlenLeaf(str1000.cast<Char>());
        },
        noOp: () {
          strlenLeaf(strEmpty.cast<Char>());
        },
      );
    });
  } finally {
    calloc.free(str1000);
    calloc.free(strEmpty);
  }
}
```

Output format:
```text
=== Running Suite: FFI Boundary Calibration ===
Benchmarking strlen (1000 chars)...
  Calibrated to 1000000 iterations per sample (no-op: 10000000).
  time:   [Total: 124.50 ns] [Overhead (FFI bridge): 2.10 ns] [Net logic: 122.40 ns]
  memory: [Total: 0.0 B] [Overhead: 0.0 B] [Net: 0.0 B]
  RSS:    [Total: +0.0 B] [Overhead: +0.0 B] [Net: +0.0 B]
  instructions: [Total: 412] [Overhead: 7] [Net: 405]
```

## Configuration

Configure the runner by passing a `CriterionConfig` instance:

```dart
await criterion(
  'My Suite',
  (c) {
    // ...
  },
  config: CriterionConfig(
    generateHtmlReport: true,        // Generate HTML reports (default: true)
    exportJson: true,                // Export JSON results (default: true)
    reportDir: 'benchmark/report',   // Output directory (default: 'benchmark/report')
    
    // KBSSD (Kernel-Based Steady-State Detection) Adaptive Benchmarking
    useKbssd: false,                 // Use KBSSD instead of fixed warmup/samples (default: false)
    kbssdWindowSize: 15,             // Sliding window size (w) (default: 15)
    kbssdStabilityRequired: 8,       // Consecutive stable samples required (default: 8)
    kbssdTrimPercentage: 0.10,       // Fraction of extreme values to trim (default: 0.10)
    kbssdScaleFactor: 2.0,           // Scale factor for dynamic threshold (default: 2.0)
    kbssdMaxSamples: 200,            // Max samples to collect before warning (default: 200)
  ),
);
```

### KBSSD Adaptive Benchmarking
When `useKbssd` is enabled, Criterion uses Kernel-Based Steady-State Detection (KBSSD) to automatically determine when the benchmark has converged. Instead of running for a fixed number of samples, it monitors a sliding window of measurements and stops when the variance (measured by Maximum Mean Discrepancy) stabilizes. This is more noise-resilient and can save time for benchmarks that converge quickly, while ensuring stability for noisier benchmarks.

## JSON Output Format

When exporting results to JSON (either via `CriterionConfig.exportJson` or `--json` CLI flag), the output contains detailed information about the benchmark run, including host environment and execution platform.

Example JSON output structure:
```json
[
  {
    "name": "fib(10)",
    "iterations": 10000000,
    "primary": {
      "sampleTimes": [2.41, 2.42, ...],
      "mean": 2.42,
      "median": 2.42,
      "stdDev": 0.019,
      "meanCI": { "lowerBound": 2.41, "upperBound": 2.42 },
      "medianCI": { "lowerBound": 2.41, "upperBound": 2.42 },
      "outliers": { ... },
      "memory": { ... }
    },
    "hostEnvironment": {
      "os": "linux",
      "dartSdkVersion": "3.12.0"
    },
    "platform": "jit",
    "timestamp": "2026-06-23T10:18:13.247Z",
    "variantGroup": "Fibonacci",
    "variantName": "recursive"
  }
]
```

Fields added in version 2.0:
*   `hostEnvironment`: Contains `os` (operating system name) and `dartSdkVersion`.
*   `platform`: The execution flavor used to run the benchmark (`jit`, `aot`, `js`, `wasm`).
*   `timestamp`: The ISO 8601 timestamp of when the benchmark completed.
*   `variantGroup` (Optional): The name of the variant group if this benchmark is a variant.
*   `variantName` (Optional): The name of the variant if this benchmark is a variant.

## Comparing Implementations

Criterion supports comparing benchmark results across different runs or different git branches/references.

### 1. Comparing JSON Results

If you have already run benchmarks and saved the JSON results, you can compare them using the `compare` tool:

```bash
dart run criterion:compare path/to/before.json path/to/after.json
```

This will output a Markdown table comparing execution time, memory usage, and CPU instruction counts (if available). 

For execution time, Criterion performs a statistical significance test by checking if the 95% confidence intervals of the runs overlap. If they do not overlap, the change is marked as significant.

### 2. Automating Git Reference Comparison

You can automate comparing two different git references (branches, tags, or commits) using the `compare_git` tool. This tool checks out both references to temporary worktrees, runs the benchmark in each, and outputs the comparison report:

```bash
dart run criterion:compare_git <ref1> <ref2> benchmark/my_benchmark.dart [extra_args...]
```

Example comparing a feature branch to `main`:
```bash
dart run criterion:compare_git main feature-branch benchmark/my_benchmark.dart
```

*Note: The target benchmark file does not need to be committed in both references; the tool will copy the benchmark file from your active workspace to the temporary worktrees.*

---

## Sample HTML Reports

Criterion generates rich interactive HTML reports (configured by default to `benchmark/report/index.html`).

### Single Benchmark Report
Shows the summary table, time distribution (KDE), iteration variance (scatter plot), memory analysis, and FFI overhead analysis.

![Single Benchmark Report](doc/images/single_report.jpg)

### Comparison View
Compare multiple benchmarks side-by-side (overlapping KDE time distribution and mean execution time bars).

![Benchmark Comparison](doc/images/comparison_report.jpg)

## Instruction Counting on Linux

Measuring CPU instructions requires access to Linux performance counters. By default, Linux restricts this access for non-root users.

To enable instruction counting:

```bash
sudo sysctl kernel.perf_event_paranoid=1
```

To make this change persistent, add the following to `/etc/sysctl.conf`:

```text
kernel.perf_event_paranoid=1
```

If performance counters are not accessible, Criterion will omit instruction counts from the output.

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.
