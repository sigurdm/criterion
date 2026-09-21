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

import "package:criterion/criterion.dart";
import "package:test/test.dart";

void main() {
  group("Benchmark Comparison", () {
    // Helper to create a dummy BenchmarkResult
    BenchmarkResult createMockResult({
      required String name,
      required double mean,
      required double lowerBound,
      required double upperBound,
      double? allocatedBytes,
      double? allocatedObjects,
      double? instructions,
      double? cycles,
      String platform = '',
    }) {
      return BenchmarkResult(
        name: name,
        iterations: 100,
        platform: platform,
        primary: MeasurementResult(
          sampleTimes: [mean],
          mean: mean,
          median: mean,
          stdDev: 0.0,
          meanCI: ConfidenceInterval(
            lowerBound: lowerBound,
            upperBound: upperBound,
          ),
          medianCI: ConfidenceInterval(
            lowerBound: lowerBound,
            upperBound: upperBound,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
          memory: (allocatedBytes != null || allocatedObjects != null)
              ? MemoryResult(
                  allocatedBytesPerIteration: allocatedBytes,
                  allocatedObjectsPerIteration: allocatedObjects,
                  rssDeltaBytes: 0,
                )
              : null,
          instructions: instructions != null
              ? InstructionResult(instructionsPerIteration: instructions)
              : null,
          cyclesPerIteration: cycles,
        ),
      );
    }

    test("Correct comparison of metrics (diff, % diff)", () {
      final before = [
        createMockResult(
          name: "bench1",
          mean: 100.0,
          lowerBound: 90.0,
          upperBound: 105.0,
          allocatedBytes: 1000.0,
          allocatedObjects: 10.0,
          instructions: 500.0,
        ),
      ];
      final after = [
        createMockResult(
          name: "bench1",
          mean: 120.0,
          lowerBound: 115.0,
          upperBound: 130.0,
          allocatedBytes: 1500.0,
          allocatedObjects: 15.0,
          instructions: 600.0,
        ),
      ];

      final comparison = compareResults(before, after);
      expect(comparison.compared.length, 1);
      final c = comparison.compared.first;
      expect(c.name, "bench1");

      expect(c.time.before, 100.0);
      expect(c.time.after, 120.0);
      expect(c.time.diff, 20.0);
      expect(c.time.percentDiff, 20.0);

      expect(c.allocatedBytes!.before, 1000.0);
      expect(c.allocatedBytes!.after, 1500.0);
      expect(c.allocatedBytes!.diff, 500.0);
      expect(c.allocatedBytes!.percentDiff, 50.0);

      expect(c.allocatedObjects!.before, 10.0);
      expect(c.allocatedObjects!.after, 15.0);
      expect(c.allocatedObjects!.diff, 5.0);
      expect(c.allocatedObjects!.percentDiff, 50.0);

      expect(c.instructions!.before, 500.0);
      expect(c.instructions!.after, 600.0);
      expect(c.instructions!.diff, 100.0);
      expect(c.instructions!.percentDiff, 20.0);
    });

    test("Correct detection of CI overlap (significance)", () {
      // Overlapping CIs:
      // before: [90, 110]
      // after: [100, 120]
      // Overlap is [100, 110] -> Not significant
      final beforeOverlapping = [
        createMockResult(
          name: "bench1",
          mean: 100.0,
          lowerBound: 90.0,
          upperBound: 110.0,
        ),
      ];
      final afterOverlapping = [
        createMockResult(
          name: "bench1",
          mean: 110.0,
          lowerBound: 100.0,
          upperBound: 120.0,
        ),
      ];

      final comparison1 = compareResults(beforeOverlapping, afterOverlapping);
      expect(comparison1.compared.first.timeSignificant, false);

      // Non-overlapping CIs:
      // before: [90, 105]
      // after: [110, 125]
      // No overlap -> Significant
      final beforeNonOverlapping = [
        createMockResult(
          name: "bench1",
          mean: 100.0,
          lowerBound: 90.0,
          upperBound: 105.0,
        ),
      ];
      final afterNonOverlapping = [
        createMockResult(
          name: "bench1",
          mean: 120.0,
          lowerBound: 110.0,
          upperBound: 125.0,
        ),
      ];

      final comparison2 = compareResults(
        beforeNonOverlapping,
        afterNonOverlapping,
      );
      expect(comparison2.compared.first.timeSignificant, true);
    });

    test("Handling of added/removed benchmarks", () {
      final before = [
        createMockResult(
          name: "bench1",
          mean: 100.0,
          lowerBound: 90.0,
          upperBound: 105.0,
        ),
        createMockResult(
          name: "bench2",
          mean: 200.0,
          lowerBound: 190.0,
          upperBound: 210.0,
        ),
      ];
      final after = [
        createMockResult(
          name: "bench2",
          mean: 200.0,
          lowerBound: 190.0,
          upperBound: 210.0,
        ),
        createMockResult(
          name: "bench3",
          mean: 300.0,
          lowerBound: 290.0,
          upperBound: 310.0,
        ),
      ];

      final comparison = compareResults(before, after);
      expect(comparison.compared.length, 1);
      expect(comparison.compared.first.name, "bench2");
      expect(comparison.removed, ["bench1"]);
      expect(comparison.added, ["bench3"]);
    });

    test(
      "Graceful handling of missing optional metrics (memory, instructions)",
      () {
        final before = [
          createMockResult(
            name: "bench1",
            mean: 100.0,
            lowerBound: 90.0,
            upperBound: 110.0,
          ),
        ];
        final after = [
          createMockResult(
            name: "bench1",
            mean: 100.0,
            lowerBound: 90.0,
            upperBound: 110.0,
          ),
        ];

        final comparison = compareResults(before, after);
        final c = comparison.compared.first;
        expect(c.allocatedBytes, null);
        expect(c.allocatedObjects, null);
        expect(c.instructions, null);

        final table = comparison.toMarkdownTable();
        expect(table, contains("Benchmark"));
        expect(table, contains("Time (before)"));
        expect(table, isNot(contains("Memory (before)")));
        expect(table, isNot(contains("Instructions (before)")));
      },
    );

    test("Markdown table formatting with all metrics", () {
      final before = [
        createMockResult(
          name: "bench1",
          mean: 100.0,
          lowerBound: 90.0,
          upperBound: 105.0,
          allocatedBytes: 1000.0,
          allocatedObjects: 10.0,
          instructions: 500.0,
        ),
      ];
      final after = [
        createMockResult(
          name: "bench1",
          mean: 120.0,
          lowerBound: 115.0,
          upperBound: 130.0,
          allocatedBytes: 1500.0,
          allocatedObjects: 15.0,
          instructions: 600.0,
        ),
      ];

      final comparison = compareResults(before, after);
      final table = comparison.toMarkdownTable();
      expect(table, contains("Memory (before)"));
      expect(table, contains("Instructions (before)"));
      expect(table, contains("bench1"));
      expect(table, contains("100.00 ns"));
      expect(table, contains("120.00 ns"));
      expect(table, contains("+20.00 ns (+20.00%)"));
      expect(table, contains("Yes")); // Significant
      expect(table, contains("1000.0 B"));
      expect(table, contains("1.5 KB"));
      expect(table, contains("+500.0 B (+50.00%)"));
      expect(table, contains("10"));
      expect(table, contains("15"));
      expect(table, contains("+5 (+50.00%)"));
      expect(table, contains("500"));
      expect(table, contains("600"));
      expect(table, contains("+100 (+20.00%)"));
    });

    test(
      "Markdown table formatting with added, removed, cycles metrics, and unit formatting",
      () {
        final before = [
          createMockResult(
            name: "bench1",
            mean: 1500.0, // 1.50 μs
            lowerBound: 1400.0,
            upperBound: 1600.0,
            allocatedBytes: 15.0 * 1024 * 1024, // 15.0 MB
            allocatedObjects: 1500000.0, // 1,500,000
            cycles: 250000.0,
          ),
          createMockResult(
            name: "removed_bench",
            mean: 2500000.0, // 2.50 ms
            lowerBound: 2400000.0,
            upperBound: 2600000.0,
          ),
        ];
        final after = [
          createMockResult(
            name: "bench1",
            mean: 3500000000.0, // 3.50 s
            lowerBound: 3400000000.0,
            upperBound: 3600000000.0,
            allocatedBytes: 5.0 * 1024 * 1024, // -10.0 MB
            allocatedObjects: 500000.0,
            cycles: 200000.0,
          ),
          createMockResult(
            name: "added_bench",
            mean: 100.0,
            lowerBound: 90.0,
            upperBound: 110.0,
          ),
        ];

        final comparison = compareResults(before, after);
        expect(comparison.removed, contains("removed_bench"));
        expect(comparison.added, contains("added_bench"));

        final table = comparison.toMarkdownTable();
        expect(table, contains("Cycles (before)"));
        expect(table, contains("Cycles (after)"));
        expect(table, contains("### Removed Benchmarks"));
        expect(table, contains("- removed_bench"));
        expect(table, contains("### Added Benchmarks"));
        expect(table, contains("- added_bench"));
        expect(table, contains("1.50 μs"));
        expect(table, contains("3.50 s"));
        expect(table, contains("15.0 MB"));
        expect(table, contains("1,500,000"));
        expect(table, contains("-50,000 (-20.00%)"));
      },
    );

    test("Markdown table formatting with platform and parameter columns", () {
      final r1 = BenchmarkResult(
        name: "fib",
        iterations: 100,
        platform: "jit",
        parameterValue: 10,
        primary: MeasurementResult(
          sampleTimes: [10000000.0], // 10.00 ms
          mean: 10000000.0,
          median: 10000000.0,
          stdDev: 0.0,
          meanCI: ConfidenceInterval(
            lowerBound: 9000000.0,
            upperBound: 11000000.0,
          ),
          medianCI: ConfidenceInterval(
            lowerBound: 9000000.0,
            upperBound: 11000000.0,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
      );
      final r2 = BenchmarkResult(
        name: "fib",
        iterations: 100,
        platform: "jit",
        parameterValue: 10,
        primary: MeasurementResult(
          sampleTimes: [12000000.0], // 12.00 ms
          mean: 12000000.0,
          median: 12000000.0,
          stdDev: 0.0,
          meanCI: ConfidenceInterval(
            lowerBound: 11000000.0,
            upperBound: 13000000.0,
          ),
          medianCI: ConfidenceInterval(
            lowerBound: 11000000.0,
            upperBound: 13000000.0,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
      );

      final comparison = compareResults([r1], [r2]);
      final table = comparison.toMarkdownTable();
      expect(table, contains("Platform"));
      expect(table, contains("Parameter"));
      expect(table, contains("jit"));
      expect(table, contains("10"));
      expect(table, contains("10.00 ms"));
      expect(table, contains("12.00 ms"));
    });

    test("loadResults and formatResults serialization helpers", () {
      expect(() => loadResults('{"not": "a list"}'), throwsFormatException);
      expect(
        () => loadResults('["string instead of map"]'),
        throwsFormatException,
      );

      final r = createMockResult(
        name: "bench",
        mean: 100.0,
        lowerBound: 90.0,
        upperBound: 110.0,
      );
      final formatted = formatResults([r]);
      expect(formatted, contains('"name": "bench"'));

      final loaded = loadResults(formatted);
      expect(loaded, hasLength(1));
      expect(loaded.first.name, equals("bench"));
    });

    test("compareResults respects net results and shifts CI by noOp mean", () {
      final before = [
        BenchmarkResult(
          name: "bench_net",
          iterations: 100,
          primary: MeasurementResult(
            sampleTimes: [100.0],
            mean: 100.0,
            median: 100.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 95.0, upperBound: 105.0),
            medianCI: ConfidenceInterval(lowerBound: 95.0, upperBound: 105.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            memory: MemoryResult(
              allocatedBytesPerIteration: 1000.0,
              allocatedObjectsPerIteration: 10.0,
              rssDeltaBytes: 0,
            ),
            instructions: InstructionResult(instructionsPerIteration: 500.0),
            cyclesPerIteration: 800.0,
          ),
          noOp: MeasurementResult(
            sampleTimes: [20.0],
            mean: 20.0,
            median: 20.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 18.0, upperBound: 22.0),
            medianCI: ConfidenceInterval(lowerBound: 18.0, upperBound: 22.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
          net: NetResult(
            timeNs: 80.0,
            allocatedBytes: 800.0,
            allocatedObjects: 8.0,
            instructions: 400.0,
            cycles: 600.0,
          ),
        ),
      ];

      final after = [
        BenchmarkResult(
          name: "bench_net",
          iterations: 100,
          primary: MeasurementResult(
            sampleTimes: [120.0],
            mean: 120.0,
            median: 120.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 115.0, upperBound: 125.0),
            medianCI: ConfidenceInterval(lowerBound: 115.0, upperBound: 125.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
            memory: MemoryResult(
              allocatedBytesPerIteration: 1200.0,
              allocatedObjectsPerIteration: 12.0,
              rssDeltaBytes: 0,
            ),
            instructions: InstructionResult(instructionsPerIteration: 600.0),
            cyclesPerIteration: 1000.0,
          ),
          noOp: MeasurementResult(
            sampleTimes: [20.0],
            mean: 20.0,
            median: 20.0,
            stdDev: 0.0,
            meanCI: ConfidenceInterval(lowerBound: 18.0, upperBound: 22.0),
            medianCI: ConfidenceInterval(lowerBound: 18.0, upperBound: 22.0),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
          net: NetResult(
            timeNs: 100.0,
            allocatedBytes: 900.0,
            allocatedObjects: 9.0,
            instructions: 450.0,
            cycles: 700.0,
          ),
        ),
      ];

      final comparison = compareResults(before, after);
      expect(comparison.compared.length, 1);
      final c = comparison.compared.first;

      expect(c.time.before, 80.0);
      expect(c.time.after, 100.0);
      expect(c.time.diff, 20.0);
      expect(c.timeSignificant, isTrue);

      expect(c.allocatedBytes!.before, 800.0);
      expect(c.allocatedBytes!.after, 900.0);
      expect(c.allocatedObjects!.before, 8.0);
      expect(c.allocatedObjects!.after, 9.0);
      expect(c.instructions!.before, 400.0);
      expect(c.instructions!.after, 450.0);
      expect(c.cycles!.before, 600.0);
      expect(c.cycles!.after, 700.0);
    });
    test("MetricComparison.percentDiff when before == 0", () {
      final zeroDiff = MetricComparison(0.0, 0.0);
      expect(zeroDiff.percentDiff, equals(0.0));

      final posDiff = MetricComparison(0.0, 10.0);
      expect(posDiff.percentDiff, equals(double.infinity));

      final negDiff = MetricComparison(0.0, -10.0);
      expect(negDiff.percentDiff, equals(double.negativeInfinity));
    });

    test("Formatting comparison table with infinite percent diff", () {
      final r1 = createMockResult(
        name: "bench_inf",
        mean: 100.0,
        lowerBound: 90.0,
        upperBound: 110.0,
        instructions: 0.0,
      );
      final r2 = createMockResult(
        name: "bench_inf",
        mean: 100.0,
        lowerBound: 90.0,
        upperBound: 110.0,
        instructions: 50.0,
      );
      final comp = compareResults([r1], [r2]);
      final table = comp.toMarkdownTable();
      expect(table, contains("+∞%"));
    });

    test("BenchmarkComparison toJson and fromJson roundtrip", () {
      final comp = BenchmarkComparison(
        name: "test_bench",
        platform: "vm",
        parameterValue: 42,
        time: MetricComparison(100.0, 110.0),
        timeSignificant: true,
        pValue: 0.012,
        withinNoiseThreshold: false,
        allocatedBytes: MetricComparison(1000.0, 1200.0),
        allocatedObjects: MetricComparison(10.0, 12.0),
        instructions: MetricComparison(500.0, 550.0),
        cycles: MetricComparison(800.0, 900.0),
      );

      final json = comp.toJson();
      expect(json['name'], equals('test_bench'));
      expect(json['platform'], equals('vm'));
      expect(json['parameterValue'], equals(42));
      expect(json['timeSignificant'], isTrue);
      expect(json['pValue'], equals(0.012));
      expect(json['withinNoiseThreshold'], isFalse);
      expect(json['allocatedBytes']['before'], equals(1000.0));

      final restored = BenchmarkComparison.fromJson(json);
      expect(restored.name, equals(comp.name));
      expect(restored.platform, equals(comp.platform));
      expect(restored.parameterValue, equals(comp.parameterValue));
      expect(restored.time.before, equals(comp.time.before));
      expect(restored.time.after, equals(comp.time.after));
      expect(restored.timeSignificant, equals(comp.timeSignificant));
      expect(restored.pValue, equals(comp.pValue));
      expect(restored.withinNoiseThreshold, equals(comp.withinNoiseThreshold));
      expect(
        restored.allocatedBytes!.before,
        equals(comp.allocatedBytes!.before),
      );
      expect(
        restored.allocatedBytes!.after,
        equals(comp.allocatedBytes!.after),
      );
      expect(
        restored.allocatedObjects!.before,
        equals(comp.allocatedObjects!.before),
      );
      expect(restored.instructions!.before, equals(comp.instructions!.before));
      expect(restored.cycles!.before, equals(comp.cycles!.before));
    });

    test("noiseThreshold suppresses significant regressions within threshold", () {
      // 0.5% difference: 100.0 -> 100.5
      final before = [
        BenchmarkResult(
          name: "subtle_change",
          iterations: 100,
          primary: MeasurementResult(
            sampleTimes: [99.9, 100.0, 100.1, 100.0],
            mean: 100.0,
            median: 100.0,
            stdDev: 0.1,
            meanCI: ConfidenceInterval(lowerBound: 99.8, upperBound: 100.2),
            medianCI: ConfidenceInterval(lowerBound: 99.8, upperBound: 100.2),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
        ),
      ];
      final after = [
        BenchmarkResult(
          name: "subtle_change",
          iterations: 100,
          primary: MeasurementResult(
            sampleTimes: [100.4, 100.5, 100.6, 100.5],
            mean: 100.5,
            median: 100.5,
            stdDev: 0.1,
            meanCI: ConfidenceInterval(lowerBound: 100.3, upperBound: 100.7),
            medianCI: ConfidenceInterval(lowerBound: 100.3, upperBound: 100.7),
            outliers: OutlierAnalysis(
              lowSevere: 0,
              lowMild: 0,
              highMild: 0,
              highSevere: 0,
              outlierVariancePercentage: 0.0,
            ),
          ),
        ),
      ];

      // With default noiseThreshold = 0.01 (1%), 0.5% change is within noise threshold.
      final compNoise = compareResults(before, after, noiseThreshold: 0.01);
      final cNoise = compNoise.compared.first;
      expect(cNoise.withinNoiseThreshold, isTrue);
      expect(cNoise.timeSignificant, isFalse);
      expect(compNoise.regressions, isEmpty);
      expect(compNoise.toMarkdownTable(), contains("No change (noise)"));

      // With noiseThreshold = 0.001 (0.1%), 0.5% change exceeds noise threshold.
      final compStrict = compareResults(before, after, noiseThreshold: 0.001);
      final cStrict = compStrict.compared.first;
      expect(cStrict.withinNoiseThreshold, isFalse);
      expect(cStrict.timeSignificant, isTrue);
      expect(compStrict.regressions, hasLength(1));
      expect(compStrict.toMarkdownTable(), contains("Yes"));
    });

    test(
      "two-sample bootstrap p-value computation handles distinct and identical distributions",
      () {
        // Very distinct distributions
        final beforeDistinct = [
          BenchmarkResult(
            name: "bench_distinct",
            iterations: 100,
            primary: MeasurementResult(
              sampleTimes: [10.0, 10.1, 10.2, 10.1, 10.0],
              mean: 10.08,
              median: 10.1,
              stdDev: 0.08,
              meanCI: ConfidenceInterval(lowerBound: 9.9, upperBound: 10.2),
              medianCI: ConfidenceInterval(lowerBound: 9.9, upperBound: 10.2),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
            ),
          ),
        ];
        final afterDistinct = [
          BenchmarkResult(
            name: "bench_distinct",
            iterations: 100,
            primary: MeasurementResult(
              sampleTimes: [20.0, 20.1, 20.2, 20.1, 20.0],
              mean: 20.08,
              median: 20.1,
              stdDev: 0.08,
              meanCI: ConfidenceInterval(lowerBound: 19.9, upperBound: 20.2),
              medianCI: ConfidenceInterval(lowerBound: 19.9, upperBound: 20.2),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
            ),
          ),
        ];
        final compDistinct = compareResults(beforeDistinct, afterDistinct);
        expect(compDistinct.compared.first.pValue, isNotNull);
        expect(compDistinct.compared.first.pValue!, lessThan(0.01));
        expect(compDistinct.compared.first.timeSignificant, isTrue);

        // Overlapping noisy distributions: p-value should be higher
        final beforeSimilar = [
          BenchmarkResult(
            name: "bench_similar",
            iterations: 100,
            primary: MeasurementResult(
              sampleTimes: [100.0, 105.0, 95.0, 102.0, 98.0],
              mean: 100.0,
              median: 100.0,
              stdDev: 3.8,
              meanCI: ConfidenceInterval(lowerBound: 95.0, upperBound: 105.0),
              medianCI: ConfidenceInterval(lowerBound: 95.0, upperBound: 105.0),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
            ),
          ),
        ];
        final afterSimilar = [
          BenchmarkResult(
            name: "bench_similar",
            iterations: 100,
            primary: MeasurementResult(
              sampleTimes: [101.0, 104.0, 96.0, 103.0, 99.0],
              mean: 100.6,
              median: 101.0,
              stdDev: 3.3,
              meanCI: ConfidenceInterval(lowerBound: 96.0, upperBound: 105.0),
              medianCI: ConfidenceInterval(lowerBound: 96.0, upperBound: 105.0),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
            ),
          ),
        ];
        final compSimilar = compareResults(beforeSimilar, afterSimilar);
        expect(compSimilar.compared.first.pValue, isNotNull);
        expect(compSimilar.compared.first.pValue!, greaterThan(0.5));
        expect(compSimilar.compared.first.timeSignificant, isFalse);
      },
    );

    test(
      "Benjamini-Hochberg FDR suppresses marginal p-values in multi-benchmark suites while preserving true regressions",
      () {
        BenchmarkResult withSamples(
          String name,
          List<double> samples,
          double mean,
        ) {
          return BenchmarkResult(
            name: name,
            iterations: 100,
            primary: MeasurementResult(
              sampleTimes: samples,
              mean: mean,
              median: mean,
              stdDev: 1.0,
              meanCI: ConfidenceInterval(
                lowerBound: mean - 1.0,
                upperBound: mean + 1.0,
              ),
              medianCI: ConfidenceInterval(
                lowerBound: mean - 1.0,
                upperBound: mean + 1.0,
              ),
              outliers: OutlierAnalysis(
                lowSevere: 0,
                lowMild: 0,
                highMild: 0,
                highSevere: 0,
                outlierVariancePercentage: 0.0,
              ),
            ),
          );
        }

        // Marginal benchmark with p ~ 0.02-0.03 (significant alone at alpha = 0.05,
        // but exceeds (1 / 20) * 0.05 = 0.0025 when tested alongside 19 unchanged
        // benchmarks).
        final marginalBefore = withSamples("marginal", [
          98.0,
          99.0,
          100.0,
          101.0,
          102.0,
        ], 100.0);
        final marginalAfter = withSamples("marginal", [
          100.2,
          101.2,
          102.2,
          103.2,
          104.2,
        ], 102.2);

        // Alone (m = 1): threshold is 0.05, so p < 0.05 is significant.
        final soloComp = compareResults([marginalBefore], [marginalAfter]);
        expect(soloComp.compared.single.pValue!, lessThan(0.05));
        expect(soloComp.compared.single.pValue!, greaterThan(0.005));
        expect(soloComp.compared.single.timeSignificant, isTrue);

        // In a 20-benchmark suite where the other 19 benchmarks have p > 0.5:
        // BH rank-1 threshold is 0.05 / 20 = 0.0025, so the marginal p-value
        // is suppressed as a false discovery.
        final suiteBefore = <BenchmarkResult>[
          marginalBefore,
          for (var i = 0; i < 19; i++)
            withSamples("unchanged_$i", [
              100.0,
              102.0,
              98.0,
              101.0,
              99.0,
            ], 100.0),
        ];
        final suiteAfter = <BenchmarkResult>[
          marginalAfter,
          for (var i = 0; i < 19; i++)
            withSamples("unchanged_$i", [
              100.2,
              101.8,
              98.2,
              100.8,
              99.2,
            ], 100.04),
        ];

        final suiteComp = compareResults(suiteBefore, suiteAfter);
        final marginalInSuite = suiteComp.compared.firstWhere(
          (c) => c.name == "marginal",
        );
        expect(marginalInSuite.timeSignificant, isFalse);

        // Adding a genuine large regression (p == 0.0 < 0.05 / 21) is still
        // detected in the same suite.
        final suiteWithRealRegBefore = [
          ...suiteBefore,
          withSamples("real_regression", [10.0, 10.1, 9.9, 10.0, 10.0], 10.0),
        ];
        final suiteWithRealRegAfter = [
          ...suiteAfter,
          withSamples("real_regression", [20.0, 20.1, 19.9, 20.0, 20.0], 20.0),
        ];
        final suiteWithRealRegComp = compareResults(
          suiteWithRealRegBefore,
          suiteWithRealRegAfter,
        );
        final realInSuite = suiteWithRealRegComp.compared.firstWhere(
          (c) => c.name == "real_regression",
        );
        expect(realInSuite.timeSignificant, isTrue);
      },
    );
  });
}
