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

Run the benchmark with the Dart VM:
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

### FFI Overhead Calibration

When benchmarking Dart FFI, the transition overhead of the FFI bridge itself can dominate micro-benchmarks. You can pass a `noOp` callback to measure and subtract this overhead.

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
  ),
);
```

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
