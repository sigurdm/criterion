import 'statistics.dart';
import 'memory_measurement.dart';
import 'instruction_measurement.dart';

/// Defines a benchmark suite. Runs all registered benchmarks immediately.
Future<void> criterion(
  String suiteName,
  void Function(Criterion c) body,
) async {
  print('=== Running Suite: $suiteName ===');
  final c = Criterion();
  body(c);
  await c.run();
}

/// A class used to register and run benchmarks.
final class Criterion {
  final List<Benchmark> _benchmarks = [];
  final List<String> _groupPath = [];

  /// The list of registered benchmarks.
  List<Benchmark> get benchmarks => List.unmodifiable(_benchmarks);

  /// Registers a benchmark.
  void bench(
    String name,
    void Function() fn, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    void Function()? noOp,
  }) {
    final fullName = _groupPath.isEmpty
        ? name
        : '${_groupPath.join(" / ")} / $name';
    _benchmarks.add(
      Benchmark(
        fullName,
        fn,
        samples: samples,
        warmupDuration: warmupDuration,
        noOp: noOp,
      ),
    );
  }

  /// Groups benchmarks together.
  void group(String name, void Function() body) {
    _groupPath.add(name);
    body();
    _groupPath.removeLast();
  }

  /// Runs all registered benchmarks and reports their results.
  Future<void> run() async {
    for (final benchmark in _benchmarks) {
      await benchmark.run();
    }
  }
}

/// Represents a single benchmark definition.
final class Benchmark {
  /// The full hierarchical name of the benchmark.
  final String name;

  /// The function to benchmark.
  final void Function() fn;

  /// The no-op function to measure overhead, if any.
  final void Function()? noOp;

  /// The number of samples to collect.
  final int samples;

  /// The duration of the warm-up phase.
  final Duration warmupDuration;

  /// Creates a [Benchmark].
  Benchmark(
    this.name,
    this.fn, {
    this.noOp,
    this.samples = 100,
    this.warmupDuration = const Duration(seconds: 1),
  });

  /// Executes the warm-up, calibration, sampling, statistical analysis,
  /// and outputs the report.
  Future<void> run() async {
    print('Benchmarking $name...');

    final hasNoOp = noOp != null;

    // 1. Warm-up
    _warmup(fn);
    if (hasNoOp) {
      _warmup(noOp!);
    }

    // 2. Calibration
    final iterations = _calibrate(fn);
    int? noOpIterations;
    if (hasNoOp) {
      noOpIterations = _calibrate(noOp!);
      print(
        '  Calibrated to $iterations iterations per sample (no-op: $noOpIterations).',
      );
    } else {
      print('  Calibrated to $iterations iterations per sample.');
    }

    // 3. Run measurements
    final mainRun = await _measureFunction(fn, iterations);
    _MeasurementRun? noOpRun;
    if (hasNoOp) {
      noOpRun = await _measureFunction(noOp!, noOpIterations!);
    }

    // 4. Report
    _report(mainRun, noOpRun);

    // 5. Output warning footnote if instructions are unsupported (one-time)
    _checkAndPrintFootnote();

    print(''); // Empty line after each benchmark
  }

  Future<_MeasurementRun> _measureFunction(
    void Function() targetFn,
    int iterations,
  ) async {
    // Sampling
    final sampleTimes = _collectSamples(targetFn, iterations);

    // Statistical Analysis
    final sample = Sample(sampleTimes);
    final bootstrapResult = sample.bootstrap();
    final outlierAnalysis = sample.analyzeOutliers();

    // Memory Measurement
    final memoryIterations = iterations > 10000 ? iterations : 10000;
    final memoryResult = await MemoryMeasurer.measure(
      fn: targetFn,
      iterations: memoryIterations,
    );

    // Instruction Measurement
    final instructionResult = InstructionMeasurer.measure(
      fn: targetFn,
      iterations: memoryIterations,
    );

    return _MeasurementRun(
      sample: sample,
      bootstrap: bootstrapResult,
      outliers: outlierAnalysis,
      memory: memoryResult,
      instructions: instructionResult,
    );
  }

  void _warmup(void Function() targetFn) {
    final stopwatch = Stopwatch()..start();
    final frequency = stopwatch.frequency;
    final targetTicks = (frequency * warmupDuration.inMicroseconds) / 1000000;
    while (stopwatch.elapsedTicks < targetTicks) {
      targetFn();
    }
    stopwatch.stop();
  }

  int _calibrate(void Function() targetFn) {
    var iterations = 1;
    const targetNs = 10 * 1000 * 1000; // 10ms
    while (true) {
      final ns = _measureIterations(targetFn, iterations);
      if (ns >= targetNs) {
        break;
      }
      iterations *= 10;
      if (iterations > 1000000000) {
        break;
      }
    }
    return iterations;
  }

  double _measureIterations(void Function() targetFn, int count) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      targetFn();
    }
    stopwatch.stop();
    final ticks = stopwatch.elapsedTicks;
    final frequency = stopwatch.frequency;
    return (ticks * 1000000000.0) / frequency; // Returns nanoseconds
  }

  List<double> _collectSamples(void Function() targetFn, int iterations) {
    final times = <double>[];
    for (var s = 0; s < samples; s++) {
      final totalNs = _measureIterations(targetFn, iterations);
      times.add(totalNs / iterations);
    }
    return times;
  }

  void _report(_MeasurementRun mainRun, _MeasurementRun? noOpRun) {
    if (noOpRun == null) {
      final sample = mainRun.sample;
      final bootstrap = mainRun.bootstrap;
      final outliers = mainRun.outliers;
      final memory = mainRun.memory;
      final instructions = mainRun.instructions;

      final mean = sample.mean;
      final median = sample.median;
      final stdDev = sample.stdDev;

      final meanCI = bootstrap.meanConfidenceInterval;
      final medianCI = bootstrap.medianConfidenceInterval;

      print(
        '  time:   [${formatDuration(meanCI.lowerBound)} '
        '${bold(formatDuration(mean))} '
        '${formatDuration(meanCI.upperBound)}] (95% CI)',
      );
      print(
        '  mean:   ${formatDuration(mean)} (std dev: ${formatDuration(stdDev)})',
      );
      print(
        '  median: ${formatDuration(median)} [${formatDuration(medianCI.lowerBound)} '
        '${formatDuration(medianCI.upperBound)}] (95% CI)',
      );

      final totalOutliers = outliers.totalOutliers;
      final percent = (totalOutliers / samples) * 100.0;
      final varPct = outliers.outlierVariancePercentage;

      String effect;
      if (varPct < 1.0) {
        effect = 'no effect';
      } else if (varPct < 10.0) {
        effect = 'slight effect';
      } else if (varPct < 50.0) {
        effect = 'moderate effect';
      } else {
        effect = 'severe effect';
      }

      if (totalOutliers > 0) {
        print(
          '  outliers: $totalOutliers/$samples outliers detected (${percent.toStringAsFixed(1)}%). '
          'Variance due to outliers: ${varPct.toStringAsFixed(1)}% ($effect)',
        );
      } else {
        print('  outliers: no outliers detected.');
      }

      if (memory != null) {
        print(
          '  memory: ${formatBytes(memory.allocatedBytesPerIteration)} allocated '
          '(${formatCount(memory.allocatedObjectsPerIteration)} objects) per iteration',
        );
        print(
          '  RSS:    ${formatRssDelta(memory.rssDeltaBytes)} (native heap growth)',
        );
      }

      if (instructions != null) {
        print(
          '  instructions: ${formatCount(instructions.instructionsPerIteration)} per iteration',
        );
      }
    } else {
      // Time metrics
      final totalTime = mainRun.sample.mean;
      final overheadTime = noOpRun.sample.mean;
      final netTime = totalTime - overheadTime;
      final netTimeClamped = netTime < 0 ? 0.0 : netTime;

      print(
        '  time:   [Total: ${bold(formatDuration(totalTime))}] '
        '[Overhead (FFI bridge): ${bold(formatDuration(overheadTime))}] '
        '[Net logic: ${bold(formatDuration(netTimeClamped))}]',
      );

      // Memory metrics
      final totalMemory = mainRun.memory;
      final noOpMemory = noOpRun.memory;
      if (totalMemory != null && noOpMemory != null) {
        final totalBytes = totalMemory.allocatedBytesPerIteration;
        final overheadBytes = noOpMemory.allocatedBytesPerIteration;
        final netBytes = totalBytes - overheadBytes;
        final netBytesClamped = netBytes < 0 ? 0.0 : netBytes;

        print(
          '  memory: [Total: ${bold(formatBytes(totalBytes))}] '
          '[Overhead: ${bold(formatBytes(overheadBytes))}] '
          '[Net: ${bold(formatBytes(netBytesClamped))}]',
        );
      }

      // Instruction metrics
      final totalInstr = mainRun.instructions;
      final noOpInstr = noOpRun.instructions;
      if (totalInstr != null && noOpInstr != null) {
        final totalCountVal = totalInstr.instructionsPerIteration;
        final overheadCountVal = noOpInstr.instructionsPerIteration;
        final netCountVal = totalCountVal - overheadCountVal;
        final netCountClamped = netCountVal < 0 ? 0.0 : netCountVal;

        print(
          '  instructions: [Total: ${bold(formatCount(totalCountVal))}] '
          '[Overhead: ${bold(formatCount(overheadCountVal))}] '
          '[Net: ${bold(formatCount(netCountClamped))}]',
        );
      }
    }
  }

  /// Formats duration in nanoseconds to a human readable string.
  static String formatDuration(double ns) {
    if (ns < 1.0) {
      return '${(ns * 1000).toStringAsFixed(2)} ps';
    }
    if (ns < 1000.0) {
      return '${ns.toStringAsFixed(2)} ns';
    }
    final us = ns / 1000.0;
    if (us < 1000.0) {
      return '${us.toStringAsFixed(2)} μs';
    }
    final ms = us / 1000.0;
    if (ms < 1000.0) {
      return '${ms.toStringAsFixed(2)} ms';
    }
    final s = ms / 1000.0;
    return '${s.toStringAsFixed(2)} s';
  }

  /// Formats text to be bold in ansi supporting terminals.
  static String bold(String text) {
    return '\x1B[1m$text\x1B[22m';
  }

  /// Formats bytes to a human readable string.
  static String formatBytes(double bytes) {
    if (bytes < 1024) {
      return '${bytes.toStringAsFixed(1)} B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Formats count with commas.
  static String formatCount(double count) {
    if (count < 1000) {
      return count.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    }
    final intCount = count.round();
    final str = intCount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  /// Formats RSS delta.
  static String formatRssDelta(int bytes) {
    final sign = bytes >= 0 ? '+' : '';
    return '$sign${formatBytes(bytes.toDouble())}';
  }
}

bool _printedPerfParanoidFootnote = false;

void _checkAndPrintFootnote() {
  if (!InstructionMeasurer.isSupported && !_printedPerfParanoidFootnote) {
    _printedPerfParanoidFootnote = true;
    print(
      'Note: Instruction counting is unsupported on this host.\n'
      '      It can be enabled on Linux by setting "sysctl kernel.perf_event_paranoid=1".',
    );
  }
}

final class _MeasurementRun {
  final Sample sample;
  final BootstrapResult bootstrap;
  final OutlierAnalysis outliers;
  final MemoryResult? memory;
  final InstructionResult? instructions;

  _MeasurementRun({
    required this.sample,
    required this.bootstrap,
    required this.outliers,
    required this.memory,
    required this.instructions,
  });
}
