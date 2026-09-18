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
import 'comparison.dart';
import 'kbssd_math.dart';
import 'result.dart';
import 'report_generator.dart';
import 'blackhole.dart';
import 'batch_size.dart';
import 'throughput.dart';
import 'history.dart';
import 'history_trim.dart';
import 'cpu_profiler.dart';
import 'cycle_counter.dart';
import 'platform_info.dart';
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
  final c = Criterion(suiteName: suiteName, config: config);
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

  /// The name of the benchmark suite, if provided.
  final String? suiteName;

  /// The configuration for this Criterion instance.
  final CriterionConfig config;

  /// The effective configuration taking environment overrides into account.
  final CriterionConfig effectiveConfig;

  /// The list of registered benchmarks.
  List<Benchmark> get benchmarks => List.unmodifiable(_benchmarks);

  /// Creates a new [Criterion] instance.
  Criterion({this.suiteName, this.config = const CriterionConfig()})
    : effectiveConfig = _computeEffectiveConfig(config);

  static CriterionConfig _computeEffectiveConfig(CriterionConfig base) {
    final effectiveFilter = env.filter.isNotEmpty ? env.filter : base.filter;
    final effectiveHtml = env.noHtml ? false : base.generateHtmlReport;
    final effectiveSaveBaseline = env.saveBaseline.isNotEmpty
        ? env.saveBaseline
        : base.saveBaseline;
    final effectiveBaseline = env.baseline.isNotEmpty
        ? env.baseline
        : base.baseline;
    final effectiveFailOnRegression =
        env.failOnRegression || base.failOnRegression;
    final parsedNoise = double.tryParse(env.noiseThreshold);
    final effectiveNoiseThreshold = (parsedNoise != null && parsedNoise >= 0.0)
        ? parsedNoise
        : base.noiseThreshold;

    var measureMemory = base.measureMemory || env.allMetrics || env.memory;
    var measureInstructions =
        base.measureInstructions || env.allMetrics || env.instructions;
    var measureCycles = base.measureCycles || env.allMetrics || env.cycles;
    var useKbssd = base.useKbssd;

    if (env.timingOnly) {
      measureMemory = false;
      measureInstructions = false;
      measureCycles = false;
    }
    if (env.noMemory) {
      measureMemory = false;
    }
    if (env.noInstructions) {
      measureInstructions = false;
    }
    if (env.noCycles) {
      measureCycles = false;
    }
    if (env.isQuick) {
      useKbssd = false;
      measureMemory = false;
      measureInstructions = false;
      measureCycles = false;
    }

    return base.copyWith(
      filter: effectiveFilter,
      generateHtmlReport: effectiveHtml,
      useKbssd: useKbssd,
      measureMemory: measureMemory,
      measureInstructions: measureInstructions,
      measureCycles: measureCycles,
      saveBaseline: effectiveSaveBaseline,
      baseline: effectiveBaseline,
      failOnRegression: effectiveFailOnRegression,
      noiseThreshold: effectiveNoiseThreshold,
    );
  }

  String _fullName(String name) =>
      _groupPath.isEmpty ? name : '${_groupPath.join(" / ")} / $name';

  /// Registers a benchmark that needs no per-iteration state.
  ///
  /// The [name] uniquely identifies this benchmark within its group.
  ///
  /// [fn] is called repeatedly inside the measured region. If it returns a
  /// [Future] the harness awaits it inside that region, so asynchronous
  /// benchmarks are measured end to end.
  ///
  /// [fn] is declared to return `void`, so an expression body such as
  /// `() => expensive()` works and its result is fed to [Blackhole]
  /// automatically. A block body cannot return a value; call [blackhole]
  /// explicitly instead, otherwise the compiler may delete the work being
  /// measured:
  ///
  /// ```dart
  /// c.bench('hash', () {
  ///   blackhole(expensive());
  /// });
  /// ```
  ///
  /// [samples] is how many measurement samples to collect. [warmupDuration] is
  /// the minimum time spent warming up before calibration. [noOp] is an
  /// optional function whose cost is measured and subtracted from every
  /// sample, which is how you remove a known harness or FFI-bridge overhead.
  /// [throughput] records how much work one iteration represents, so results
  /// can be reported in bytes or elements per second.
  ///
  /// Use [benchState] instead when each iteration needs freshly constructed
  /// input, so that construction is not timed.
  void bench(
    String name,
    FutureOr<void> Function() fn, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    FutureOr<void> Function()? noOp,
    Throughput? throughput,
  }) {
    _benchmarks.add(
      Benchmark<void>(
        _fullName(name),
        fn,
        config: effectiveConfig,
        samples: samples,
        warmupDuration: warmupDuration,
        noOp: noOp,
        throughput: throughput,
      ),
    );
  }

  /// Registers a benchmark that runs against freshly constructed state.
  ///
  /// [setup] runs outside the measured region and produces a value of type
  /// [T]; [fn] receives that value inside the measured region. [teardown], if
  /// given, runs outside the measured region once [fn] has been called. Each
  /// iteration gets its own state, so benchmarks that consume or mutate their
  /// input measure the same thing every time.
  ///
  /// [batchSize] controls how many states are built up front before a timed
  /// run. Large states should use [BatchSize.largeInput] to avoid exhausting
  /// RAM and evicting the CPU cache; see [BatchSize] for the trade-off against
  /// timer resolution. Defaults to [BatchSize.smallInput].
  ///
  /// [samples], [warmupDuration], [noOp] and [throughput] behave as in [bench].
  void benchState<T>(
    String name,
    FutureOr<void> Function(T state) fn, {
    required FutureOr<T> Function() setup,
    FutureOr<void> Function(T state)? teardown,
    FutureOr<void> Function(T state)? noOp,
    BatchSize? batchSize,
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Throughput? throughput,
  }) {
    _benchmarks.add(
      Benchmark<T>(
        _fullName(name),
        fn,
        config: effectiveConfig,
        samples: samples,
        warmupDuration: warmupDuration,
        noOp: noOp,
        throughput: throughput,
        setup: setup,
        teardown: teardown,
        batchSize: batchSize,
      ),
    );
  }

  /// Groups related benchmarks together to organize reports.
  ///
  /// Groups can be nested. The [name] is appended to the parent group path.
  /// The [body] callback is executed immediately to register benchmarks within the group.
  void group(String name, void Function() body) {
    _groupPath.add(name);
    try {
      body();
    } finally {
      _groupPath.removeLast();
    }
  }

  /// Registers a group of competing implementations to compare against each
  /// other.
  ///
  /// [groupName] identifies the group; the keys of [variants] name the
  /// individual implementations. Every variant is reported as its own
  /// benchmark and additionally compared head to head in the report.
  ///
  /// [samples], [warmupDuration] and [throughput] apply to every variant.
  ///
  /// Use [variantsState] when the variants need freshly constructed input.
  void variants(
    String groupName,
    Map<String, FutureOr<void> Function()> variants, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Throughput? throughput,
  }) {
    final baseName = _fullName(groupName);
    variants.forEach((variantName, fn) {
      _benchmarks.add(
        Benchmark<void>(
          '$baseName / $variantName',
          fn,
          config: effectiveConfig,
          samples: samples,
          warmupDuration: warmupDuration,
          variantGroup: groupName,
          variantName: variantName,
          throughput: throughput,
        ),
      );
    });
  }

  /// Registers a group of competing implementations that each run against
  /// freshly constructed state.
  ///
  /// Behaves like [variants], but [setup], [teardown] and [batchSize] work as
  /// described on [benchState]. Every variant is given its own state, built by
  /// the same [setup], so the comparison is fair.
  void variantsState<T>(
    String groupName,
    Map<String, FutureOr<void> Function(T state)> variants, {
    required FutureOr<T> Function() setup,
    FutureOr<void> Function(T state)? teardown,
    BatchSize? batchSize,
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Throughput? throughput,
  }) {
    final baseName = _fullName(groupName);
    variants.forEach((variantName, fn) {
      _benchmarks.add(
        Benchmark<T>(
          '$baseName / $variantName',
          fn,
          config: effectiveConfig,
          samples: samples,
          warmupDuration: warmupDuration,
          variantGroup: groupName,
          variantName: variantName,
          throughput: throughput,
          setup: setup,
          teardown: teardown,
          batchSize: batchSize,
        ),
      );
    });
  }

  /// Registers one benchmark per entry in [parameters], to measure how cost
  /// scales with the input.
  ///
  /// [fn] is called with the parameter value inside the measured region. The
  /// resulting benchmarks share [groupName] so the report can plot them
  /// against each other and estimate a complexity curve.
  ///
  /// [throughput] is a function rather than a value so that each parameter can
  /// declare how much work it represents.
  ///
  /// Use [benchWithState] when each iteration also needs freshly constructed
  /// state derived from the parameter.
  void benchWith<P>(
    String groupName,
    List<P> parameters,
    FutureOr<void> Function(P param) fn, {
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    FutureOr<void> Function(P param)? noOp,
    Throughput Function(P param)? throughput,
  }) {
    for (final p in parameters) {
      _benchmarks.add(
        Benchmark<void>(
          _fullName('$groupName / $p'),
          () => fn(p),
          config: effectiveConfig,
          samples: samples,
          warmupDuration: warmupDuration,
          noOp: noOp == null ? null : () => noOp(p),
          throughput: throughput?.call(p),
          parameterGroup: groupName,
          parameterValue: p,
        ),
      );
    }
  }

  /// Registers one benchmark per entry in [parameters], each running against
  /// freshly constructed state derived from its parameter.
  ///
  /// [setup] receives the parameter and produces the state; [fn] receives both
  /// the state and the parameter. [teardown] and [batchSize] work as described
  /// on [benchState].
  void benchWithState<T, P>(
    String groupName,
    List<P> parameters,
    FutureOr<void> Function(T state, P param) fn, {
    required FutureOr<T> Function(P param) setup,
    FutureOr<void> Function(T state)? teardown,
    FutureOr<void> Function(T state, P param)? noOp,
    BatchSize? batchSize,
    int samples = 100,
    Duration warmupDuration = const Duration(seconds: 1),
    Throughput Function(P param)? throughput,
  }) {
    for (final p in parameters) {
      _benchmarks.add(
        Benchmark<T>(
          _fullName('$groupName / $p'),
          (T state) => fn(state, p),
          config: effectiveConfig,
          samples: samples,
          warmupDuration: warmupDuration,
          noOp: noOp == null ? null : (T state) => noOp(state, p),
          throughput: throughput?.call(p),
          setup: () => setup(p),
          teardown: teardown,
          batchSize: batchSize,
          parameterGroup: groupName,
          parameterValue: p,
        ),
      );
    }
  }

  /// Runs all registered benchmarks and reports their results.
  Future<List<BenchmarkResult>> run() async {
    effectiveConfig.validate();
    if (effectiveConfig.measureCycles) {
      await CycleCounter.init();
    }
    final filterPattern = effectiveConfig.filter;
    final benchmarksToRun = (filterPattern != null && filterPattern.isNotEmpty)
        ? _benchmarks
              .where((b) => RegExp(filterPattern).hasMatch(b.name))
              .toList()
        : _benchmarks;

    final results = <BenchmarkResult>[];
    for (final benchmark in benchmarksToRun) {
      final result = await benchmark.run();
      results.add(result);
    }
    Blackhole.preventDCE();

    final historyMgr = HistoryManager(effectiveConfig.historyFile);
    List<BenchmarkResult>? history;

    if (!env.isJson &&
        (effectiveConfig.checkRegressions ||
            effectiveConfig.exportHistory ||
            effectiveConfig.generateHtmlReport)) {
      history = await historyMgr.load();
    }

    var regressions = const <BenchmarkComparison>[];
    String? regressionBaselineLabel;

    if (!env.isJson && effectiveConfig.baseline != null) {
      final baselineResults = await historyMgr.loadNamedBaseline(
        effectiveConfig.baseline!,
      );
      regressions = checkRegressions(
        current: results,
        history: baselineResults,
        noiseThreshold: effectiveConfig.noiseThreshold,
        baselineLabel: effectiveConfig.baseline,
      );
      regressionBaselineLabel = effectiveConfig.baseline;
    } else if (!env.isJson &&
        effectiveConfig.checkRegressions &&
        history != null) {
      regressions = checkRegressions(
        current: results,
        history: history,
        noiseThreshold: effectiveConfig.noiseThreshold,
      );
    }

    if (!env.isJson && effectiveConfig.saveBaseline != null) {
      await historyMgr.saveNamedBaseline(
        effectiveConfig.saveBaseline!,
        results,
      );
    }

    // Trimmed before it reaches either the report or the disk: the whole
    // array is embedded in the generated HTML, so an uncapped history makes
    // the report unopenable long before the file itself becomes a problem.
    final fullHistory = trimHistory(
      history != null ? [...history, ...results] : results,
      maxEntriesPerBenchmark: effectiveConfig.maxHistoryEntries,
    );

    if (env.isJson) {
      print(jsonEncode(results.map((r) => r.toJson()).toList()));
    } else {
      await ReportGenerator(
        effectiveConfig,
      ).generate(results, history: fullHistory, suiteName: suiteName);
      _printVariantComparisons(results);
    }

    if (!env.isJson && effectiveConfig.exportHistory && history != null) {
      await historyMgr.save(
        fullHistory,
        maxEntriesPerBenchmark: effectiveConfig.maxHistoryEntries,
      );
    }

    if (effectiveConfig.failOnRegression && regressions.isNotEmpty) {
      throw RegressionDetected(
        regressions,
        baselineLabel: regressionBaselineLabel,
      );
    }

    return results;
  }

  void _printVariantComparisons(List<BenchmarkResult> results) {
    if (env.isJson) return;

    final groups = <String, List<BenchmarkResult>>{};
    for (final r in results) {
      if (r.variantGroup != null) {
        final key =
            (r.variantName != null && r.name.endsWith(' / ${r.variantName}'))
            ? r.name.substring(0, r.name.length - ' / ${r.variantName}'.length)
            : r.variantGroup!;
        groups.putIfAbsent(key, () => []).add(r);
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
      final baselineTime = baseline.net?.timeNs ?? baseline.primary.mean;

      print(
        '| $baselineName (baseline) | ${Benchmark.formatDuration(baselineTime)} | 1.00x | - |',
      );

      for (var i = 1; i < groupResults.length; i++) {
        final current = groupResults[i];
        final currentName = current.variantName ?? current.name;
        final currentTime = current.net?.timeNs ?? current.primary.mean;

        final relativeSpeedStr = _formatRelativeSpeed(
          baselineTime,
          currentTime,
        );

        final baselineCI = (baseline.net != null && baseline.noOp != null)
            ? ConfidenceInterval(
                lowerBound:
                    (baseline.primary.meanCI.lowerBound - baseline.noOp!.mean)
                        .clamp(0.0, double.infinity),
                upperBound:
                    (baseline.primary.meanCI.upperBound - baseline.noOp!.mean)
                        .clamp(0.0, double.infinity),
              )
            : baseline.primary.meanCI;
        final currentCI = (current.net != null && current.noOp != null)
            ? ConfidenceInterval(
                lowerBound:
                    (current.primary.meanCI.lowerBound - current.noOp!.mean)
                        .clamp(0.0, double.infinity),
                upperBound:
                    (current.primary.meanCI.upperBound - current.noOp!.mean)
                        .clamp(0.0, double.infinity),
              )
            : current.primary.meanCI;

        final significant = _isSignificant(baselineCI, currentCI);
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
  ///
  /// This is `FutureOr<void> Function()` when [setup] is `null`, and
  /// `FutureOr<void> Function(T)` otherwise. The constructor rejects anything
  /// else. Prefer [Criterion.bench] and [Criterion.benchState], which express
  /// the same thing in the static type system.
  final Function fn;

  /// The no-op function to measure overhead, if any.
  ///
  /// Has the same signature as [fn].
  final Function? noOp;

  /// The throughput configuration, if any.
  final Throughput? throughput;

  /// The setup function, if any.
  final FutureOr<T> Function()? setup;

  /// The teardown function, if any.
  final FutureOr<void> Function(T state)? teardown;

  /// The batch size configuration.
  final BatchSize batchSize;

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
  ///
  /// Throws an [ArgumentError] if:
  /// * [fn] or [noOp] does not have the arity required by [setup]; see [fn].
  /// * [teardown] or [batchSize] is given without [setup], since neither means
  ///   anything for a benchmark that has no state.
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
    this.teardown,
    BatchSize? batchSize,
  }) : batchSize =
           batchSize ??
           (setup != null ? BatchSize.smallInput : BatchSize.unbatched) {
    if (setup == null && teardown != null) {
      throw ArgumentError(
        'teardown can only be provided when setup is provided',
      );
    }
    if (setup == null && batchSize != null) {
      throw ArgumentError(
        'batchSize can only be provided when setup is provided',
      );
    }
    if (setup == null) {
      if (fn is! Function()) {
        throw ArgumentError.value(
          fn,
          'fn',
          'Must not take any parameters when setup is not provided',
        );
      }
      if (noOp != null && noOp is! Function()) {
        throw ArgumentError.value(
          noOp,
          'noOp',
          'Must not take any parameters when setup is not provided',
        );
      }
    } else {
      if (fn is Function()) {
        throw ArgumentError.value(
          fn,
          'fn',
          'Must accept the state of type $T when setup is provided',
        );
      }
      if (noOp != null && noOp is Function()) {
        throw ArgumentError.value(
          noOp,
          'noOp',
          'Must accept the state of type $T when setup is provided',
        );
      }
    }
  }

  int get _effectiveSamples {
    if (env.samplesOverride > 0) return env.samplesOverride;
    if (env.isQuick) return 10;
    return samples;
  }

  Duration get _effectiveWarmupDuration {
    if (env.warmupMsOverride >= 0) {
      return Duration(milliseconds: env.warmupMsOverride);
    }
    if (env.isQuick) return const Duration(milliseconds: 50);
    return warmupDuration;
  }

  /// Executes the warm-up, calibration, sampling, statistical analysis,
  /// and outputs the report.
  Future<BenchmarkResult> run() async {
    if (!env.isJson) {
      print('Benchmarking $name...');
    }

    final hasNoOp = noOp != null;
    final effectiveWarmup = _effectiveWarmupDuration;

    // 1. Warm-up
    if (!config.useKbssd) {
      await _warmup(fn, effectiveWarmup);
      if (hasNoOp) {
        await _warmup(noOp!, effectiveWarmup);
      }
    } else if (effectiveWarmup > Duration.zero) {
      final shortWarmup = effectiveWarmup < const Duration(milliseconds: 50)
          ? effectiveWarmup
          : const Duration(milliseconds: 50);
      await _warmup(fn, shortWarmup);
      if (hasNoOp) {
        await _warmup(noOp!, shortWarmup);
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
    if (!env.isJson && config.measureInstructions) {
      _checkAndPrintFootnote();
    }

    if (!env.isJson) {
      print(''); // Empty line after each benchmark
    }

    Blackhole.preventDCE();

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

    final teardownDynamic = teardown != null
        ? (dynamic s) => teardown!(s as T)
        : null;

    // Memory Measurement
    final memoryIterations = setup != null
        ? iterations.clamp(1, 1000)
        : iterations.clamp(100, 10000);
    final memoryResult = config.measureMemory
        ? await MemoryMeasurer.measure(
            fn: targetFn,
            iterations: memoryIterations,
            setup: setup,
            teardown: teardownDynamic,
            batchSize: batchSize,
          )
        : null;

    // Instruction Measurement
    final instructionResult = config.measureInstructions
        ? await InstructionMeasurer.measure(
            fn: targetFn,
            iterations: memoryIterations,
            setup: setup,
            teardown: teardownDynamic,
            batchSize: batchSize,
          )
        : null;

    // CPU Profiling
    CpuProfileResult? cpuProfileResult;
    if (config.cpuProfiling) {
      const targetProfileNs = 200 * 1000 * 1000; // 200ms
      final profileIterations = sample.mean > 0
          ? (targetProfileNs / sample.mean).round().clamp(100, 1000000)
          : 100000;
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
        teardown: teardownDynamic,
        exportPath: exportPath,
        batchSize: batchSize,
      );
    }

    // Cycle Measurement
    final cyclesResult = config.measureCycles
        ? await CycleCounter.measure(
            fn: targetFn,
            iterations: memoryIterations,
            setup: setup,
            teardown: teardownDynamic,
            batchSize: batchSize,
          )
        : null;

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

  Future<void> _warmup(Function targetFn, [Duration? duration]) async {
    final effectiveWarmup = duration ?? _effectiveWarmupDuration;
    final stopwatch = Stopwatch()..start();
    final frequency = stopwatch.frequency;
    final targetTicks = (frequency * effectiveWarmup.inMicroseconds) / 1000000;
    if (setup != null) {
      if (targetFn is Object? Function(T)) {
        final fnSync = targetFn;
        while (stopwatch.elapsedTicks < targetTicks) {
          final state = setup!();
          final resolvedState = state is Future ? await state : state;
          try {
            final r = fnSync(resolvedState);
            if (r is Future) {
              Blackhole.sink = await r;
            } else {
              Blackhole.sink = r;
            }
          } finally {
            if (teardown != null) {
              final res = teardown!(resolvedState);
              if (res is Future) await res;
            }
          }
        }
      } else {
        while (stopwatch.elapsedTicks < targetTicks) {
          final state = setup!();
          final resolvedState = state is Future ? await state : state;
          try {
            final r = targetFn(resolvedState);
            if (r is Future) {
              Blackhole.sink = await r;
            } else {
              Blackhole.sink = r;
            }
          } finally {
            if (teardown != null) {
              final res = teardown!(resolvedState);
              if (res is Future) await res;
            }
          }
        }
      }
    } else if (targetFn is Object? Function()) {
      final fnSync = targetFn;
      while (stopwatch.elapsedTicks < targetTicks) {
        final r = fnSync();
        if (r is Future) {
          Blackhole.sink = await r;
        } else {
          Blackhole.sink = r;
        }
      }
    } else {
      while (stopwatch.elapsedTicks < targetTicks) {
        final r = targetFn();
        if (r is Future) {
          Blackhole.sink = await r;
        } else {
          Blackhole.sink = r;
        }
      }
    }
    stopwatch.stop();
  }

  Future<int> _calibrate(Function targetFn) async {
    var iterations = 1;
    final targetNs = setup != null ? 2 * 1000 * 1000 : 10 * 1000 * 1000;
    final maxWallNs = setup != null ? 3 * 1000 * 1000 : 25 * 1000 * 1000;
    while (true) {
      final wallStopwatch = Stopwatch()..start();
      final ns = await _measureIterations(targetFn, iterations);
      wallStopwatch.stop();
      final wallNs =
          (wallStopwatch.elapsedTicks * 1000000000.0) / wallStopwatch.frequency;
      if (ns >= targetNs || wallNs >= maxWallNs) {
        break;
      }
      if (ns > 0 && iterations * (targetNs / ns) < iterations * 10) {
        final estimated = (iterations * (targetNs / ns) * 1.15).ceil();
        iterations = estimated < iterations * 2 ? iterations * 2 : estimated;
      } else {
        iterations *= 10;
      }
      if (iterations > 1000000000) {
        break;
      }
    }
    return iterations;
  }

  Future<double> _measureIterations(Function targetFn, int count) async {
    final stopwatch = Stopwatch();
    if (setup != null) {
      if (targetFn is Object? Function(T)) {
        final fnSync = targetFn;
        var remaining = count;
        while (remaining > 0) {
          final batch = batchSize.batchSizeFor(remaining);
          final states = <T>[];
          for (var i = 0; i < batch; i++) {
            final state = setup!();
            states.add(state is Future ? await state : state);
          }
          stopwatch.start();
          try {
            for (var i = 0; i < batch; i++) {
              final r = fnSync(states[i]);
              if (r is Future) {
                Blackhole.sink = await r;
              } else {
                Blackhole.sink = r;
              }
            }
          } finally {
            stopwatch.stop();
            if (teardown != null) {
              for (var i = 0; i < states.length; i++) {
                final res = teardown!(states[i]);
                if (res is Future) await res;
              }
            }
          }
          remaining -= batch;
        }
      } else {
        var remaining = count;
        while (remaining > 0) {
          final batch = batchSize.batchSizeFor(remaining);
          final states = <T>[];
          for (var i = 0; i < batch; i++) {
            final state = setup!();
            states.add(state is Future ? await state : state);
          }
          stopwatch.start();
          try {
            for (var i = 0; i < batch; i++) {
              final r = targetFn(states[i]);
              if (r is Future) {
                Blackhole.sink = await r;
              } else {
                Blackhole.sink = r;
              }
            }
          } finally {
            stopwatch.stop();
            if (teardown != null) {
              for (var i = 0; i < states.length; i++) {
                final res = teardown!(states[i]);
                if (res is Future) await res;
              }
            }
          }
          remaining -= batch;
        }
      }
    } else {
      if (targetFn is Object? Function()) {
        final fnSync = targetFn;
        stopwatch.start();
        for (var i = 0; i < count; i++) {
          final r = fnSync();
          if (r is Future) {
            Blackhole.sink = await r;
          } else {
            Blackhole.sink = r;
          }
        }
        stopwatch.stop();
      } else {
        stopwatch.start();
        for (var i = 0; i < count; i++) {
          final r = targetFn();
          if (r is Future) {
            Blackhole.sink = await r;
          } else {
            Blackhole.sink = r;
          }
        }
        stopwatch.stop();
      }
    }
    final ticks = stopwatch.elapsedTicks;
    final frequency = stopwatch.frequency;
    return (ticks * 1000000000.0) / frequency; // Returns nanoseconds
  }

  Future<List<double>> _collectSamples(
    Function targetFn,
    int iterations,
  ) async {
    final targetSampleCount = _effectiveSamples;
    final times = <double>[];
    for (var s = 0; s < targetSampleCount; s++) {
      final totalNs = await _measureIterations(targetFn, iterations);
      times.add(totalNs / iterations);
    }
    return times;
  }

  /// Collects samples using Kernel-Based Steady-State Detection.
  ///
  /// This runs in two phases:
  ///
  /// 1. **Steady-state detection** (adaptive warm-up). Measurements are taken
  ///    until a sliding "past" window and "present" window become
  ///    indistinguishable for [CriterionConfig.kbssdStabilityRequired]
  ///    consecutive steps, or until [CriterionConfig.kbssdMaxSamples]
  ///    measurements have been taken. None of these measurements are reported:
  ///    they describe the transient, which is exactly what we are waiting out.
  /// 2. **Measurement**. Once steady state is reached, a fresh set of
  ///    [_effectiveSamples] measurements is collected and returned.
  ///
  /// Splitting the two is what allows the `samples` argument to mean the same
  /// thing whether or not KBSSD is enabled.
  Future<List<double>> _collectSamplesKbssd(
    Function targetFn,
    int iterations,
  ) async {
    final converged = await _detectSteadyState(targetFn, iterations);
    if (!converged && !env.isJson) {
      print(
        '  Warning: Benchmark $name did not reach a steady state after '
        '${config.kbssdMaxSamples} measurements; sampling anyway.',
      );
    }
    return _collectSamples(targetFn, iterations);
  }

  /// Runs measurements until the benchmark reaches a steady state.
  ///
  /// Returns `true` if steady state was detected, `false` if
  /// [CriterionConfig.kbssdMaxSamples] measurements were exhausted first.
  Future<bool> _detectSteadyState(Function targetFn, int iterations) async {
    final w = config.kbssdWindowSize;
    final maxSamples = config.kbssdMaxSamples;
    final stabilityRequired = config.kbssdStabilityRequired;
    final trimPct = config.kbssdTrimPercentage;
    final scale = config.kbssdScaleFactor;

    // 1. Fill cold buffer of size w * 2.
    final coldBuffer = <double>[];
    for (var i = 0; i < w * 2; i++) {
      final totalNs = await _measureIterations(targetFn, iterations);
      coldBuffer.add(totalNs / iterations);
    }

    // 2. Pick a kernel bandwidth from the observed dispersion.
    var sigma = populationStandardDeviation(coldBuffer);
    if (sigma == 0.0) {
      sigma = 1e-9;
    }

    // 3. Calibrate the convergence threshold *in MMD units*, by estimating the
    //    MMD we would see between two halves of the data if nothing changed.
    //    Comparing the live MMD against a raw dispersion measure (such as a
    //    relative MAD) is not meaningful, and degenerates for very stable
    //    benchmarks where `sigma` collapses towards zero.
    final threshold = estimateNullMmd(coldBuffer, sigma) * scale;

    final slidingBuffer = List<double>.from(coldBuffer);
    var stableCount = 0;

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

      final isStable = mmd <= threshold || checkSEM(present);

      if (isStable) {
        stableCount++;
      } else {
        stableCount = 0;
      }

      if (stableCount >= stabilityRequired) {
        return true;
      }
    }

    return false;
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

    // Printed regardless of whether memory measurement produced allocation
    // counts: CPU profiling is enabled independently of `measureMemory`.
    _printCpuProfile(mainRun.cpuProfile);

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
    final abs = ns.abs();
    if (abs < 1.0) {
      return '${(ns * 1000).toStringAsFixed(2)} ps';
    }
    if (abs < 1000.0) {
      return '${ns.toStringAsFixed(2)} ns';
    }
    final us = ns / 1000.0;
    if (us.abs() < 1000.0) {
      return '${us.toStringAsFixed(2)} μs';
    }
    final ms = us / 1000.0;
    if (ms.abs() < 1000.0) {
      return '${ms.toStringAsFixed(2)} ms';
    }
    final s = ms / 1000.0;
    return '${s.toStringAsFixed(2)} s';
  }

  /// Formats text to be bold in ANSI-supporting terminals.
  static String bold(String text) {
    if (!supportsAnsiEscapes) return text;
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
    if (count.abs() < 1000) {
      return count.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    }
    final intCount = count.round();
    final str = intCount.toString();
    final buffer = StringBuffer();
    final isNegative = str.startsWith('-');
    final digits = isNegative ? str.substring(1) : str;

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return (isNegative ? '-' : '') + buffer.toString();
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
