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
  });
}
