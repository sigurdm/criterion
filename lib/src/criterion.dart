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

import 'dart:async';
import 'dart:convert';
import 'dart_environment.dart' as env;
import 'statistics.dart';
import 'memory_measurement.dart';
import 'instruction_measurement.dart';
import 'config.dart';
import 'kbssd_math.dart';
import 'result.dart';
import 'report_generator.dart';
import 'blackhole.dart';
import 'throughput.dart';
import 'history.dart';
import 'cpu_profiler.dart';
import 'cycle_counter.dart';
import 'package:path/path.dart' as p;

/// Defines a benchmark suite and runs all registered benchmarks.
///
/// The [suiteName] is used as a header in the reports.
/// The [body] callback is used to register benchmarks using [Criterion.bench].
/// The [config] allows customizing the benchmark execution.
///
/// Returns a list of [BenchmarkResult]s.
Future<List<BenchmarkResult>> criterion(
  String suiteName,
  void Function(Criterion c) body, {
  CriterionConfig config = const CriterionConfig(),
}) async {
  if (!env.isJson) {
    print('=== Running Suite: $suiteName ===');
  }
  final c = Criterion(config: config);
  body(c);
  return await c.run();
}

/// A runner and registry for benchmarks.
///
/// Use [Criterion] to register benchmarks with [bench], group them with [group],
/// and compare variants with [variants].
final class Criterion {
  final List<Benchmark> _benchmarks = [];
  final List<String> _groupPath = [];

  /// The configuration for this Criterion instance.
  final CriterionConfig config;

  /// The list of registered benchmarks.
  List<Benchmark> get benchmarks => List.unmodifiable(_benchmarks);

  /// Creates a new [Criterion] instance.
  Criterion({this.config = const CriterionConfig()});

  /// Registers a benchmark.
  ///
  /// The [name] uniquely identifies this benchmark within its group.
  /// The [fn] is the benchmark function.
  ///
  /// If [setup] is provided, it is executed before each iteration to generate
  /// a state of type [T], which is then passed to [fn]. In this case, [fn] must
  /// be a function that accepts a single parameter of type [T] (e.g., `void Function(T)`).
  ///
  /// If [setup] is not provided, [fn] must be a function that accepts no parameters
  /// (e.g., `void Function()`).
  ///
  /// The [samples] configures how many measurement samples to collect.
  /// The [warmupDuration] is the minimum time spent warming up the JIT compiler.
  /// The [noOp] is an optional function with the same signature as [fn] that can
  /// be used to measure and subtract harness or bridge overhead.
  /// The [throughput] is an optional metric to track throughput (bytes or elements).
  ///
  /// Throws [ArgumentError] if the signature of [fn] or [noOp] does not match
  /// the requirements based on [setup] presence.
  void bench<T>(
    String name,
    Function fn, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Function? noOp,
    Throughput? throughput,
    FutureOr<T> Function()? setup,
  }) {
    if (setup != null) {
      if (fn is Function()) {
        throw ArgumentError(
          'fn must accept a parameter of type $T when setup is provided',
        );
      }
      if (noOp != null && noOp is Function()) {
        throw ArgumentError(
          'noOp must accept a parameter of type $T when setup is provided',
        );
      }
    } else {
      if (fn is! Function()) {
        throw ArgumentError(
          'fn must not accept any parameters when setup is not provided',
        );
      }
      if (noOp != null && noOp is! Function()) {
        throw ArgumentError(
          'noOp must not accept any parameters when setup is not provided',
        );
      }
    }

    final fullName = _groupPath.isEmpty
        ? name
        : '${_groupPath.join(" / ")} / $name';
    _benchmarks.add(
      Benchmark<T>(
        fullName,
        fn,
        config: config,
        samples: samples,
        warmupDuration: warmupDuration,
        noOp: noOp,
        throughput: throughput,
        setup: setup,
      ),
    );
  }

  /// Groups related benchmarks together to organize reports.
  ///
  /// Groups can be nested. The [name] is appended to the parent group path.
  /// The [body] callback is executed immediately to register benchmarks within the group.
  void group(String name, void Function() body) {
    _groupPath.add(name);
    body();
    _groupPath.removeLast();
  }

  /// Registers a group of benchmark variants to compare their performance.
  ///
  /// The [groupName] identifies the group of variants.
  /// The [variants] map contains variant names and their corresponding functions.
  ///
  /// If [setup] is provided, it is executed before each iteration to generate
  /// a state of type [T] for each variant. In this case, all variant functions
  /// must accept a single parameter of type [T].
  ///
  /// If [setup] is not provided, all variant functions must accept no parameters.
  ///
  /// The [samples], [warmupDuration], and [throughput] apply to all variants in the group.
  ///
  /// Throws [ArgumentError] if the signature of any variant function does not match
  /// the requirements based on [setup] presence.
  void variants<T>(
    String groupName,
    Map<String, Function> variants, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Throughput? throughput,
    FutureOr<T> Function()? setup,
  }) {
    variants.forEach((variantName, fn) {
      if (setup != null) {
        if (fn is Function()) {
          throw ArgumentError(
            'Variant "$variantName" must accept a parameter of type $T when setup is provided',
          );
        }
      } else {
        if (fn is! Function()) {
          throw ArgumentError(
            'Variant "$variantName" must not accept any parameters when setup is not provided',
          );
        }
      }
    });

    final baseName = _groupPath.isEmpty
        ? groupName
        : '${_groupPath.join(" / ")} / $groupName';

    variants.forEach((variantName, fn) {
      final fullName = '$baseName / $variantName';
      _benchmarks.add(
        Benchmark<T>(
          fullName,
          fn,
          config: config,
          samples: samples,
          warmupDuration: warmupDuration,
          variantGroup: groupName,
          variantName: variantName,
          throughput: throughput,
          setup: setup,
        ),
      );
    });
  }

  /// Registers a benchmark that is run with different parameters.
  ///
  /// The [groupName] identifies the group of parameterized benchmarks.
  /// The [parameters] is a list of values to run the benchmark with.
  /// The [fn] is the benchmark function.
  ///
  /// If [setup] is provided, it is executed before each iteration to generate
  /// a state of type [T] for each parameter value. In this case, [fn] must
  /// accept either [T] (the state) or both [T] and [P] (the state and the parameter).
  ///
  /// If [setup] is not provided, [fn] must accept [P] (the parameter).
  ///
  /// The [samples], [warmupDuration], and [throughput] apply to all runs.
  /// [throughput] can be a function that returns a [Throughput] for a given parameter.
  void benchWith<T, P>(
    String groupName,
    List<P> parameters,
    Function fn, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Function? noOp,
    Throughput Function(P param)? throughput,
    FutureOr<T> Function(P param)? setup,
  }) {
    for (final p in parameters) {
      final String fullName = _groupPath.isEmpty
          ? '$groupName / $p'
          : '${_groupPath.join(" / ")} / $groupName / $p';

      final FutureOr<T> Function()? wrappedSetup = setup != null
          ? () => setup(p)
          : null;

      final Function wrappedFn;
      final Function? wrappedNoOp;

      if (setup != null) {
        if (fn is Function(T, P)) {
          wrappedFn = (T state) => fn(state, p);
        } else if (fn is Function(T)) {
          wrappedFn = fn;
        } else if (fn is Function(dynamic, dynamic)) {
          // Fallback for dynamic types
          wrappedFn = (T state) => fn(state, p);
        } else if (fn is Function(dynamic)) {
          wrappedFn = fn;
        } else {
          throw ArgumentError(
            'fn must accept (T state) or (T state, P parameter) when setup is provided',
          );
        }

        if (noOp != null) {
          if (noOp is Function(T, P)) {
            wrappedNoOp = (T state) => noOp(state, p);
          } else if (noOp is Function(T)) {
            wrappedNoOp = noOp;
          } else if (noOp is Function(dynamic, dynamic)) {
            wrappedNoOp = (T state) => noOp(state, p);
          } else if (noOp is Function(dynamic)) {
            wrappedNoOp = noOp;
          } else {
            throw ArgumentError(
              'noOp must accept (T state) or (T state, P parameter) when setup is provided',
            );
          }
        } else {
          wrappedNoOp = null;
        }
      } else {
        if (fn is Function(P)) {
          wrappedFn = () => fn(p);
        } else if (fn is Function(dynamic)) {
          wrappedFn = () => fn(p);
        } else if (fn is Function()) {
          // If it takes no arguments, it's an error because it should take the parameter
          throw ArgumentError(
            'fn must accept (P parameter) when setup is not provided',
          );
        } else {
          wrappedFn = () => fn(p);
        }

        if (noOp != null) {
          if (noOp is Function(P)) {
            wrappedNoOp = () => noOp(p);
          } else if (noOp is Function(dynamic)) {
            wrappedNoOp = () => noOp(p);
          } else {
            wrappedNoOp = () => noOp(p);
          }
        } else {
          wrappedNoOp = null;
        }
      }

      final tp = throughput != null ? throughput(p) : null;

      _benchmarks.add(
        Benchmark<T>(
          fullName,
          wrappedFn,
          config: config,
          samples: samples,
          warmupDuration: warmupDuration,
          noOp: wrappedNoOp,
          throughput: tp,
          setup: wrappedSetup,
          parameterGroup: groupName,
          parameterValue: p,
        ),
      );
    }
  }

  /// Runs all registered benchmarks and reports their results.
  Future<List<BenchmarkResult>> run() async {
    await CycleCounter.init();
    final results = <BenchmarkResult>[];
    for (final benchmark in _benchmarks) {
      final result = await benchmark.run();
      results.add(result);
    }
    Blackhole.preventDCE();

    final historyMgr = HistoryManager(config.historyFile);
    List<BenchmarkResult>? history;

    if (!env.isJson && (config.checkRegressions || config.exportHistory)) {
      history = await historyMgr.load();
    }

    if (!env.isJson && config.checkRegressions && history != null) {
      checkRegressions(current: results, history: history);
    }

    if (env.isJson) {
      print(jsonEncode(results.map((r) => r.toJson()).toList()));
    } else {
      await ReportGenerator(config).generate(results);
      _printVariantComparisons(results);
    }

    if (!env.isJson && config.exportHistory && history != null) {
      history.addAll(results);
      await historyMgr.save(history);
    }

    return results;
  }

  void _printVariantComparisons(List<BenchmarkResult> results) {
    if (env.isJson) return;

    final groups = <String, List<BenchmarkResult>>{};
    for (final r in results) {
      if (r.variantGroup != null) {
        groups.putIfAbsent(r.variantGroup!, () => []).add(r);
      }
    }

    if (groups.isEmpty) return;

    for (final entry in groups.entries) {
      final groupName = entry.key;
      final groupResults = entry.value;
      if (groupResults.isEmpty) continue;

      print('=== Variant Comparison: $groupName ===');
      print('| Variant | Time | Relative Speed | Significant? |');
      print('| --- | --- | --- | --- |');

      final baseline = groupResults.first;
      final baselineName = baseline.variantName ?? baseline.name;
      final baselineTime = baseline.primary.mean;

      print(
        '| $baselineName (baseline) | ${Benchmark.formatDuration(baselineTime)} | 1.00x | - |',
      );

      for (var i = 1; i < groupResults.length; i++) {
        final current = groupResults[i];
        final currentName = current.variantName ?? current.name;
        final currentTime = current.primary.mean;

        final relativeSpeedStr = _formatRelativeSpeed(
          baselineTime,
          currentTime,
        );

        final significant = _isSignificant(
          baseline.primary.meanCI,
          current.primary.meanCI,
        );
        final significantStr = significant ? 'Yes' : 'No';

        print(
          '| $currentName | ${Benchmark.formatDuration(currentTime)} | $relativeSpeedStr | $significantStr |',
        );
      }
      print('');
    }
  }

  String _formatRelativeSpeed(double baselineMean, double variantMean) {
    if (variantMean == 0 && baselineMean == 0) return '1.00x';
    if (variantMean == 0) return 'Infinityx (faster)';
    if (baselineMean == 0) return 'Infinityx (slower)';
    final factor = baselineMean / variantMean;
    final factorStr = factor.toStringAsFixed(2);
    if (factorStr == '1.00') {
      return '1.00x';
    }
    if (factor > 1.0) {
      return '${factorStr}x (faster)';
    } else {
      final slowerFactor = 1 / factor;
      return '${slowerFactor.toStringAsFixed(2)}x (slower)';
    }
  }

  bool _isSignificant(ConfidenceInterval a, ConfidenceInterval b) {
    return a.upperBound < b.lowerBound || b.upperBound < a.lowerBound;
  }
}

/// Represents a single benchmark definition.
final class Benchmark<T> {
  /// The full hierarchical name of the benchmark.
  final String name;

  /// The function to benchmark.
  final Function fn;

  /// The no-op function to measure overhead, if any.
  final Function? noOp;

  /// The throughput configuration, if any.
  final Throughput? throughput;

  /// The setup function, if any.
  final FutureOr<T> Function()? setup;

  /// The number of samples to collect.
  final int samples;

  /// The duration of the warm-up phase.
  final Duration warmupDuration;

  /// The configuration for this benchmark.
  final CriterionConfig config;

  /// The variant group name, if this benchmark is part of a variant group.
  final String? variantGroup;

  /// The variant name, if this benchmark is part of a variant group.
  final String? variantName;

  /// The parameter group name, if this benchmark is part of a parameterized group.
  final String? parameterGroup;

  /// The parameter value, if this benchmark is part of a parameterized group.
  final Object? parameterValue;

  /// Creates a [Benchmark].
  Benchmark(
    this.name,
    this.fn, {
    this.config = const CriterionConfig(),
    this.noOp,
    this.samples = 100,
    this.warmupDuration = const Duration(seconds: 1),
    this.variantGroup,
    this.variantName,
    this.parameterGroup,
    this.parameterValue,
    this.throughput,
    this.setup,
  });

  /// Executes the warm-up, calibration, sampling, statistical analysis,
  /// and outputs the report.
  Future<BenchmarkResult> run() async {
    if (!env.isJson) {
      print('Benchmarking $name...');
    }

    final hasNoOp = noOp != null;

    // 1. Warm-up
    if (!config.useKbssd) {
      await _warmup(fn);
      if (hasNoOp) {
        await _warmup(noOp!);
      }
    }

    // 2. Calibration
    final iterations = await _calibrate(fn);
    int? noOpIterations;
    if (hasNoOp) {
      noOpIterations = await _calibrate(noOp!);
      if (!env.isJson) {
        print(
          '  Calibrated to $iterations iterations per sample (no-op: $noOpIterations).',
        );
      }
    } else {
      if (!env.isJson) {
        print('  Calibrated to $iterations iterations per sample.');
      }
    }

    // 3. Run measurements
    final mainRun = await _measureFunction(fn, iterations);
    _MeasurementRun? noOpRun;
    if (hasNoOp) {
      noOpRun = await _measureFunction(noOp!, noOpIterations!);
    }

    // 4. Report
    if (!env.isJson) {
      _report(mainRun, noOpRun);
    }

    // 5. Output warning footnote if instructions are unsupported (one-time)
    if (!env.isJson) {
      _checkAndPrintFootnote();
    }

    if (!env.isJson) {
      print(''); // Empty line after each benchmark
    }

    return _createResult(iterations, mainRun, noOpRun);
  }

  BenchmarkResult _createResult(
    int iterations,
    _MeasurementRun mainRun,
    _MeasurementRun? noOpRun,
  ) {
    final primaryResult = MeasurementResult(
      sampleTimes: mainRun.sample.values,
      mean: mainRun.sample.mean,
      median: mainRun.sample.median,
      stdDev: mainRun.sample.stdDev,
      meanCI: mainRun.bootstrap.meanConfidenceInterval,
      medianCI: mainRun.bootstrap.medianConfidenceInterval,
      outliers: mainRun.outliers,
      memory: mainRun.memory,
      instructions: mainRun.instructions,
      cpuProfile: mainRun.cpuProfile,
      cyclesPerIteration: mainRun.cycles,
    );

    MeasurementResult? noOpResult;
    NetResult? netResult;

    if (noOpRun != null) {
      noOpResult = MeasurementResult(
        sampleTimes: noOpRun.sample.values,
        mean: noOpRun.sample.mean,
        median: noOpRun.sample.median,
        stdDev: noOpRun.sample.stdDev,
        meanCI: noOpRun.bootstrap.meanConfidenceInterval,
        medianCI: noOpRun.bootstrap.medianConfidenceInterval,
        outliers: noOpRun.outliers,
        memory: noOpRun.memory,
        instructions: noOpRun.instructions,
        cpuProfile: noOpRun.cpuProfile,
        cyclesPerIteration: noOpRun.cycles,
      );

      final totalTime = mainRun.sample.mean;
      final overheadTime = noOpRun.sample.mean;
      final netTime = totalTime - overheadTime;
      final netTimeClamped = netTime < 0 ? 0.0 : netTime;

      double? netBytes;
      double? netObjects;
      if (mainRun.memory != null && noOpRun.memory != null) {
        final mainB = mainRun.memory!.allocatedBytesPerIteration;
        final noOpB = noOpRun.memory!.allocatedBytesPerIteration;
        if (mainB != null && noOpB != null) {
          final netB = mainB - noOpB;
          netBytes = netB < 0 ? 0.0 : netB;
        }

        final mainO = mainRun.memory!.allocatedObjectsPerIteration;
        final noOpO = noOpRun.memory!.allocatedObjectsPerIteration;
        if (mainO != null && noOpO != null) {
          final netO = mainO - noOpO;
          netObjects = netO < 0 ? 0.0 : netO;
        }
      }

      double? netInstr;
      if (mainRun.instructions != null && noOpRun.instructions != null) {
        final netI =
            mainRun.instructions!.instructionsPerIteration -
            noOpRun.instructions!.instructionsPerIteration;
        netInstr = netI < 0 ? 0.0 : netI;
      }

      double? netCycles;
      if (mainRun.cycles != null && noOpRun.cycles != null) {
        final netC = mainRun.cycles! - noOpRun.cycles!;
        netCycles = netC < 0 ? 0.0 : netC;
      }

      netResult = NetResult(
        timeNs: netTimeClamped,
        allocatedBytes: netBytes,
        allocatedObjects: netObjects,
        instructions: netInstr,
        cycles: netCycles,
      );
    }

    return BenchmarkResult(
      name: name,
      iterations: iterations,
      primary: primaryResult,
      noOp: noOpResult,
      net: netResult,
      variantGroup: variantGroup,
      variantName: variantName,
      parameterGroup: parameterGroup,
      parameterValue: parameterValue,
      throughput: throughput,
    );
  }

  Future<_MeasurementRun> _measureFunction(
    Function targetFn,
    int iterations,
  ) async {
    // Sampling
    final List<double> sampleTimes;
    if (config.useKbssd) {
      sampleTimes = await _collectSamplesKbssd(targetFn, iterations);
    } else {
      sampleTimes = await _collectSamples(targetFn, iterations);
    }

    // Statistical Analysis
    final sample = Sample(sampleTimes);
    final bootstrapResult = sample.bootstrap();
    final outlierAnalysis = sample.analyzeOutliers();

    // Memory Measurement
    final memoryIterations = iterations > 100 ? iterations : 100;
    final memoryResult = await MemoryMeasurer.measure(
      fn: targetFn,
      iterations: memoryIterations,
      setup: setup,
    );

    // Instruction Measurement
    final instructionResult = await InstructionMeasurer.measure(
      fn: targetFn,
      iterations: memoryIterations,
      setup: setup,
    );

    // CPU Profiling
    CpuProfileResult? cpuProfileResult;
    if (config.cpuProfiling) {
      final targetProfileNs = 200 * 1000 * 1000; // 200ms
      final profileIterations = (targetProfileNs / sample.mean).round().clamp(
        100,
        1000000,
      );
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final exportPath = p.join(
        config.reportDir,
        'profiles',
        '$safeName.cpuprofile.json',
      );
      cpuProfileResult = await CpuProfiler.collect(
        fn: targetFn,
        iterations: profileIterations,
        setup: setup,
        exportPath: exportPath,
      );
    }

    // Cycle Measurement
    final cyclesResult = await CycleCounter.measure(
      fn: targetFn,
      iterations: memoryIterations,
      setup: setup,
    );

    return _MeasurementRun(
      sample: sample,
      bootstrap: bootstrapResult,
      outliers: outlierAnalysis,
      memory: memoryResult,
      instructions: instructionResult,
      cpuProfile: cpuProfileResult,
      cycles: cyclesResult,
    );
  }

  Future<void> _warmup(Function targetFn) async {
    final stopwatch = Stopwatch()..start();
    final frequency = stopwatch.frequency;
    final targetTicks = (frequency * warmupDuration.inMicroseconds) / 1000000;
    while (stopwatch.elapsedTicks < targetTicks) {
      if (setup != null) {
        final state = setup!();
        final resolvedState = state is Future ? await state : state;
        final r = targetFn(resolvedState);
        if (r is Future) {
          await r;
        }
      } else {
        final r = targetFn();
        if (r is Future) {
          await r;
        }
      }
    }
    stopwatch.stop();
  }

  Future<int> _calibrate(Function targetFn) async {
    var iterations = 1;
    const targetNs = 10 * 1000 * 1000; // 10ms
    while (true) {
      final ns = await _measureIterations(targetFn, iterations);
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

  Future<double> _measureIterations(Function targetFn, int count) async {
    final stopwatch = Stopwatch();
    if (setup != null) {
      final states = <T>[];
      for (var i = 0; i < count; i++) {
        final state = setup!();
        states.add(state is Future ? await state : state);
      }
      stopwatch.start();
      for (var i = 0; i < count; i++) {
        final r = targetFn(states[i]);
        if (r is Future) {
          await r;
        }
      }
      stopwatch.stop();
    } else {
      stopwatch.start();
      for (var i = 0; i < count; i++) {
        final r = targetFn();
        if (r is Future) {
          await r;
        }
      }
      stopwatch.stop();
    }
    final ticks = stopwatch.elapsedTicks;
    final frequency = stopwatch.frequency;
    return (ticks * 1000000000.0) / frequency; // Returns nanoseconds
  }

  Future<List<double>> _collectSamples(
    Function targetFn,
    int iterations,
  ) async {
    final times = <double>[];
    for (var s = 0; s < samples; s++) {
      final totalNs = await _measureIterations(targetFn, iterations);
      times.add(totalNs / iterations);
    }
    return times;
  }

  Future<List<double>> _collectSamplesKbssd(
    Function targetFn,
    int iterations,
  ) async {
    final w = config.kbssdWindowSize;
    final maxSamples = config.kbssdMaxSamples;
    final stabilityRequired = config.kbssdStabilityRequired;
    final trimPct = config.kbssdTrimPercentage;
    final scale = config.kbssdScaleFactor;

    // 1. Fill cold buffer of size w * 2
    final coldBuffer = <double>[];
    for (var i = 0; i < w * 2; i++) {
      final totalNs = await _measureIterations(targetFn, iterations);
      coldBuffer.add(totalNs / iterations);
    }

    // 2. Calculate dynamic convergence threshold
    final coldSample = Sample(coldBuffer);
    final coldMedian = coldSample.median;
    final coldMad = calculateMAD(coldBuffer, coldMedian);
    final relativeMad = coldMedian == 0.0 ? 0.0 : coldMad / coldMedian;
    final threshold = relativeMad * scale;

    var sigma = populationStandardDeviation(coldBuffer);
    if (sigma == 0.0) {
      sigma = 1e-9;
    }

    final slidingBuffer = List<double>.from(coldBuffer);
    var stableCount = 0;
    List<double>? bestWindow;
    double minMmd = double.infinity;

    for (var s = w * 2; s < maxSamples; s++) {
      final totalNs = await _measureIterations(targetFn, iterations);
      final newSample = totalNs / iterations;

      slidingBuffer.add(newSample);
      slidingBuffer.removeAt(0);

      final past = slidingBuffer.sublist(0, w);
      final present = slidingBuffer.sublist(w, w * 2);

      final trimmedPast = trimWindow(past, trimPct);
      final trimmedPresent = trimWindow(present, trimPct);

      double mmd;
      if (trimmedPast.isEmpty || trimmedPresent.isEmpty) {
        mmd = double.infinity;
      } else {
        mmd = calculateMMD(trimmedPast, trimmedPresent, sigma);
      }

      final isStable = mmd < threshold || checkSEM(present);

      if (isStable) {
        stableCount++;
      } else {
        stableCount = 0;
      }

      if (mmd < minMmd) {
        minMmd = mmd;
        bestWindow = List<double>.from(present);
      }

      if (stableCount >= stabilityRequired) {
        return present;
      }
    }

    if (!env.isJson) {
      print(
        '  Warning: Benchmark $name did not converge after $maxSamples samples.',
      );
    }
    return bestWindow ?? slidingBuffer.sublist(w, w * 2);
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
      final actualSamples = sample.values.length;
      final percent = (totalOutliers / actualSamples) * 100.0;
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
          '  outliers: $totalOutliers/${sample.length} outliers detected (${percent.toStringAsFixed(1)}%). '
          'Variance due to outliers: ${varPct.toStringAsFixed(1)}% ($effect)',
        );
      } else {
        print('  outliers: no outliers detected.');
      }

      if (memory != null) {
        if (memory.allocatedBytesPerIteration != null &&
            memory.allocatedObjectsPerIteration != null) {
          print(
            '  memory: ${formatBytes(memory.allocatedBytesPerIteration!)} allocated '
            '(${formatCount(memory.allocatedObjectsPerIteration!)} objects) per iteration',
          );
          _printTopAllocations(memory.classAllocations);
          _printCpuProfile(mainRun.cpuProfile);
        }
        print(
          '  RSS:    ${formatRssDelta(memory.rssDeltaBytes)} (native heap growth)',
        );
      }

      if (instructions != null) {
        print(
          '  instructions: ${formatCount(instructions.instructionsPerIteration)} per iteration',
        );
      }

      if (mainRun.cycles != null) {
        print('  cycles:       ${formatCount(mainRun.cycles!)} per iteration');
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
        if (totalBytes != null && overheadBytes != null) {
          final netBytes = totalBytes - overheadBytes;
          final netBytesClamped = netBytes < 0 ? 0.0 : netBytes;

          print(
            '  memory: [Total: ${bold(formatBytes(totalBytes))}] '
            '[Overhead: ${bold(formatBytes(overheadBytes))}] '
            '[Net: ${bold(formatBytes(netBytesClamped))}]',
          );
          _printTopAllocations(totalMemory.classAllocations);
          _printCpuProfile(mainRun.cpuProfile);
        }
        print(
          '  RSS:    [Total: ${bold(formatRssDelta(totalMemory.rssDeltaBytes))}] '
          '[Overhead: ${bold(formatRssDelta(noOpMemory.rssDeltaBytes))}] '
          '[Net: ${bold(formatRssDelta(totalMemory.rssDeltaBytes - noOpMemory.rssDeltaBytes))}]',
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

      // Cycle metrics
      final totalCycles = mainRun.cycles;
      final noOpCycles = noOpRun.cycles;
      if (totalCycles != null && noOpCycles != null) {
        final netCycles = totalCycles - noOpCycles;
        final netCyclesClamped = netCycles < 0 ? 0.0 : netCycles;

        print(
          '  cycles:       [Total: ${bold(formatCount(totalCycles))}] '
          '[Overhead: ${bold(formatCount(noOpCycles))}] '
          '[Net: ${bold(formatCount(netCyclesClamped))}]',
        );
      }
    }
    final meanTimeNs = noOpRun != null
        ? (mainRun.sample.mean - noOpRun.sample.mean).clamp(
            0.0,
            double.infinity,
          )
        : mainRun.sample.mean;
    final throughputStr = _formatThroughput(meanTimeNs);
    if (throughputStr != null) {
      print('  throughput: $throughputStr');
    }
  }

  void _printTopAllocations(List<ClassAllocation>? allocations) {
    if (allocations == null || allocations.isEmpty) return;
    // Filter out zero allocations to keep output clean
    final activeAllocs = allocations
        .where((a) => a.bytes > 0 || a.instances > 0)
        .toList();
    if (activeAllocs.isEmpty) return;

    // Sort by bytes descending, then instances descending
    final sortedAllocs = [...activeAllocs]
      ..sort((a, b) {
        final cmp = b.bytes.compareTo(a.bytes);
        if (cmp != 0) return cmp;
        return b.instances.compareTo(a.instances);
      });
    final top = sortedAllocs.take(5).toList();
    if (top.isNotEmpty) {
      print('    Top allocations:');
      for (final alloc in top) {
        print(
          '      - ${alloc.className} (${alloc.libraryUri}): '
          '${formatBytes(alloc.bytes.toDouble())} (${alloc.instances} instances)',
        );
      }
    }
  }

  void _printCpuProfile(CpuProfileResult? profile) {
    if (profile == null || profile.functions.isEmpty) return;
    final sortedFuncs = [...profile.functions]
      ..sort((a, b) {
        final cmp = b.exclusiveTicks.compareTo(a.exclusiveTicks);
        if (cmp != 0) return cmp;
        return b.inclusiveTicks.compareTo(a.inclusiveTicks);
      });
    final top = sortedFuncs.take(5).toList();
    if (top.isNotEmpty) {
      print('    Top CPU functions:');
      for (final func in top) {
        final total = profile.sampleCount;
        final pct = total > 0 ? (func.exclusiveTicks / total) * 100 : 0.0;
        print(
          '      - ${func.name} (${func.resolvedUrl}): '
          '${func.exclusiveTicks} ticks (${pct.toStringAsFixed(1)}%)',
        );
      }
    }
  }

  String? _formatThroughput(double timeNs) {
    if (throughput == null) return null;
    if (timeNs == 0) return 'Infinity/s';

    final seconds = timeNs / 1e9;
    final rate = throughput!.count / seconds;

    if (throughput!.unit == ThroughputUnit.bytes) {
      return '${_formatBytesRate(rate)}/s';
    } else {
      return '${_formatCountRate(rate)} elements/s';
    }
  }

  String _formatBytesRate(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(1)} B';
    }
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatCountRate(double countPerSecond) {
    final intCount = countPerSecond.round();
    if (intCount < 1000) {
      return intCount.toString();
    }
    final str = intCount.toString();
    final sb = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      sb.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        sb.write(',');
      }
    }
    return sb.toString().split('').reversed.join();
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
  final CpuProfileResult? cpuProfile;
  final double? cycles;

  _MeasurementRun({
    required this.sample,
    required this.bootstrap,
    required this.outliers,
    required this.memory,
    required this.instructions,
    this.cpuProfile,
    this.cycles,
  });
}
