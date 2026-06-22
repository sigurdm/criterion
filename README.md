# Criterion

[![pub package](https://img.shields.io/pub/v/criterion.svg)](https://pub.dev/packages/criterion)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A high-performance, statistically robust benchmarking framework for Dart, heavily inspired by Rust's `criterion.rs`.

Unlike simple timing loops, `criterion` accounts for the unique characteristics of the Dart Virtual Machine (VM)—such as JIT compilation, garbage collection, and native FFI transition overheads—to deliver extremely precise, reproducible, and detailed performance insights.

---

## Key Features

*   📊 **Statistical Rigor & Bootstrapping**: Calculates 95% confidence intervals for both mean and median execution times using bootstrap resampling. This prevents temporary system noise or GC pauses from skewing your results.
*   🔍 **Outlier Analysis**: Identifies mild and severe outliers, reporting the percentage of variance in your benchmarks caused by them.
*   ⚡ **JIT-Aware Warm-up**: Automatically warms up your functions before taking measurements, ensuring that the Dart VM JIT-compiles and optimizes the code before it is timed.
*   ⚖️ **Automated Calibration**: Automatically determines the optimal number of iterations per sample to ensure measurements are well above the system clock's resolution.
*   💾 **Granular Memory Tracking**: Reports allocated bytes, the number of allocated Dart objects, and Resident Set Size (RSS) delta per iteration, using the Dart VM Service.
*   🦾 **Hardware Instruction Counting**: Measures the exact number of CPU instructions executed per iteration on Linux systems (requires `perf_event_paranoid` configuration).
*   🎯 **FFI & Overhead Calibration (`noOp`)**: Allows you to specify a "no-op" baseline function. Criterion will measure its performance and automatically subtract the call/bridge overhead, providing the **Net** time, memory, and instruction counts of your core logic.
*   📈 **Interactive HTML Reports**: Automatically generates stunning, interactive HTML reports with charts and detailed tables in `benchmark/report/`.
*   📥 **JSON Exports**: Exports raw benchmark data as JSON for CI/CD integration and historical tracking.

---

## Getting Started

Add `criterion` to your `dev_dependencies` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  criterion: ^1.0.0
```

---

## Usage Examples

### 1. Basic Benchmarking

Create a benchmark file, e.g., `benchmark/my_benchmark.dart`:

```dart
import 'package:criterion/criterion.dart';

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

void main() async {
  // Define a benchmark suite
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

Run it using the Dart VM:
```bash
dart benchmark/my_benchmark.dart
```

### 2. Grouping Benchmarks

You can group related benchmarks together to make the output and HTML reports easier to compare:

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

### 3. FFI Overhead & Boundary Calibration

When benchmarking Dart FFI calls, the transition overhead of the FFI bridge itself can often dominate micro-benchmarks. Criterion allows you to pass a `noOp` function (e.g., an FFI call that does no work) to isolate and subtract the overhead.

```dart
import 'dart:ffi';
import 'package:criterion/criterion.dart';
import 'package:ffi/ffi.dart';

// Leaf FFI call to C strlen (highly optimized transition)
@Native<UintPtr Function(Pointer<Char>)>(symbol: 'strlen', isLeaf: true)
external int strlenLeaf(Pointer<Char> s);

void main() async {
  // Allocate native memory outside the benchmark loop to avoid measuring allocation cost.
  final str1000 = ('a' * 1000).toNativeUtf8();
  final strEmpty = ''.toNativeUtf8();

  try {
    await criterion('FFI Boundary Calibration', (c) {
      c.bench(
        'strlen (1000 chars)',
        () {
          // Main function: Leaf FFI call with 1000 iterations inside strlen
          strlenLeaf(str1000.cast<Char>());
        },
        noOp: () {
          // Overhead function: Leaf FFI call with 0 iterations (returns immediately)
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

#### Example Output:
```text
=== Running Suite: FFI Boundary Calibration ===
Benchmarking strlen (1000 chars)...
  Calibrated to 1000000 iterations per sample (no-op: 10000000).
  time:   [Total: 124.50 ns] [Overhead (FFI bridge): 2.10 ns] [Net logic: 122.40 ns]
  memory: [Total: 0.0 B] [Overhead: 0.0 B] [Net: 0.0 B]
  RSS:    [Total: +0.0 B] [Overhead: +0.0 B] [Net: +0.0 B]
  instructions: [Total: 412] [Overhead: 7] [Net: 405]
```

---

## Configuration

You can customize the benchmark runner's behavior by passing a `CriterionConfig` to the `criterion` entrypoint:

```dart
await criterion(
  'My Suite',
  (c) {
    // ...
  },
  config: CriterionConfig(
    generateHtmlReport: true,        // Generate interactive HTML reports (default: true)
    exportJson: true,                // Export raw JSON results (default: true)
    reportDir: 'benchmark/report',   // Output directory (default: 'benchmark/report')
  ),
);
```

---

## Advanced: Instruction Counting on Linux

To measure hardware CPU instructions, Criterion accesses Linux performance counters. By default, Linux restricts access to these counters for non-root users.

To enable instruction counting, run the following command on your Linux host:

```bash
sudo sysctl kernel.perf_event_paranoid=1
```

To make this change permanent, add the following line to `/etc/sysctl.conf`:

```text
kernel.perf_event_paranoid=1
```

If instruction counting is unsupported or disabled, Criterion will gracefully omit it from the report.

---

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.
