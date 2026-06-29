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

import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

void main() async {
  final reportDir = Directory('benchmark/screenshots_report');
  await _generateScreenshotsReport(reportDir);

  final reportPath = p.absolute(p.join(reportDir.path, 'index.html'));

  print('Launching browser...');
  Browser browser;
  try {
    browser = await puppeteer.launch();
  } catch (e) {
    print('Failed to launch browser: $e');
    print('Attempting to launch with system chrome...');
    String? chromePath;
    if (Platform.isLinux) {
      chromePath = '/usr/bin/google-chrome';
    }
    if (chromePath != null && File(chromePath).existsSync()) {
      browser = await puppeteer.launch(executablePath: chromePath);
    } else {
      rethrow;
    }
  }

  final page = await browser.newPage();
  await page.setViewport(DeviceViewport(width: 1200, height: 1200));

  final outputDir = Directory('doc/images');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  // 1. Dashboard (Default view, first benchmark)
  try {
    print('Taking dashboard screenshot...');
    await page.goto(
      'file://$reportPath?animate=false',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final dashboardBytes = await page.screenshot(fullPage: true);
    File(
      p.join(outputDir.path, 'dashboard.png'),
    ).writeAsBytesSync(dashboardBytes);
  } catch (e) {
    print('Failed to take dashboard screenshot: $e');
  }

  // 2. Memory Allocations (Select "Memory Allocations" benchmark)
  try {
    print('Taking memory profile screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&bench=Memory Allocations',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final memoryCard = await page.$('#memory-allocations-card');
    final bytes = await memoryCard.screenshot();
    File(p.join(outputDir.path, 'memory_profile.png')).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take memory profile screenshot: $e');
  }

  // 3. CPU Profile (Select "Fibonacci Parameterized / 20")
  try {
    print('Taking CPU profile screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&bench=Fibonacci Parameterized / 20',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final cpuCard = await page.$('#cpu-profile-card');
    final bytes = await cpuCard.screenshot();
    File(p.join(outputDir.path, 'cpu_profile.png')).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take CPU profile screenshot: $e');
  }

  // 4. Parameterized Chart
  try {
    print('Taking parameterized chart screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&parameters=true',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final bytes = await page.screenshot(fullPage: true);
    File(
      p.join(outputDir.path, 'parameterized_chart.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take parameterized chart screenshot: $e');
  }

  // 5. Variants Comparison
  try {
    print('Taking variants comparison screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&variants=true',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final bytes = await page.screenshot(fullPage: true);
    File(
      p.join(outputDir.path, 'variants_comparison.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take variants comparison screenshot: $e');
  }

  // 6. Historical Performance Trends
  try {
    print('Taking history timeline screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&history=true',
      wait: Until.networkIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final bytes = await page.screenshot(fullPage: true);
    File(
      p.join(outputDir.path, 'history_timeline.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take history timeline screenshot: $e');
  }

  await browser.close();
  print('Done! Screenshots saved to ${outputDir.path}');
}

Future<void> _generateScreenshotsReport(Directory reportDir) async {
  if (!reportDir.existsSync()) {
    reportDir.createSync(recursive: true);
  }

  final commits = [
    GitCommit(
      hash: 'a1b2c3d4e5f67890123456789012345678901234',
      shortHash: 'a1b2c3d',
      message: 'Initial implementation',
      timestamp: DateTime.parse('2026-06-01T10:00:00Z'),
    ),
    GitCommit(
      hash: 'b2c3d4e5f678901234567890123456789012345a',
      shortHash: 'b2c3d4e',
      message: 'Optimize memory allocations',
      timestamp: DateTime.parse('2026-06-05T14:30:00Z'),
    ),
    GitCommit(
      hash: 'c3d4e5f678901234567890123456789012345a1b',
      shortHash: 'c3d4e5f',
      message: 'Refactor core loop',
      timestamp: DateTime.parse('2026-06-10T09:15:00Z'),
    ),
    GitCommit(
      hash: 'd4e5f678901234567890123456789012345a1b2c',
      shortHash: 'd4e5f67',
      message: 'Add SIMD vectorization',
      timestamp: DateTime.parse('2026-06-15T16:45:00Z'),
    ),
    GitCommit(
      hash: 'e5f678901234567890123456789012345a1b2c3d',
      shortHash: 'e5f6789',
      message: 'Inline hot methods',
      timestamp: DateTime.parse('2026-06-20T11:20:00Z'),
    ),
  ];

  final fibHistoryMeans = [52.4, 46.0, 42.1, 28.5, 21.8];
  final jsonHistoryMeans = [125.0, 110.2, 98.4, 85.0, 72.1];

  final history = <BenchmarkResult>[];
  for (var i = 0; i < commits.length; i++) {
    final fibMean = fibHistoryMeans[i];
    history.add(
      BenchmarkResult(
        name: 'Fibonacci (Iterative)',
        iterations: 1000,
        platform: 'aot',
        timestamp: commits[i].timestamp,
        gitCommit: commits[i],
        primary: MeasurementResult(
          sampleTimes: List.generate(
            15,
            (idx) => fibMean + (idx % 3 - 1) * 0.5,
          ),
          mean: fibMean,
          median: fibMean,
          stdDev: 0.8,
          meanCI: ConfidenceInterval(
            lowerBound: fibMean - 0.5,
            upperBound: fibMean + 0.5,
          ),
          medianCI: ConfidenceInterval(
            lowerBound: fibMean - 0.5,
            upperBound: fibMean + 0.5,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
      ),
    );

    final jsonMean = jsonHistoryMeans[i];
    history.add(
      BenchmarkResult(
        name: 'JSON Parser',
        iterations: 1000,
        platform: 'aot',
        timestamp: commits[i].timestamp,
        gitCommit: commits[i],
        primary: MeasurementResult(
          sampleTimes: List.generate(
            15,
            (idx) => jsonMean + (idx % 3 - 1) * 1.0,
          ),
          mean: jsonMean,
          median: jsonMean,
          stdDev: 1.5,
          meanCI: ConfidenceInterval(
            lowerBound: jsonMean - 1.0,
            upperBound: jsonMean + 1.0,
          ),
          medianCI: ConfidenceInterval(
            lowerBound: jsonMean - 1.0,
            upperBound: jsonMean + 1.0,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
      ),
    );
  }

  // Current suite benchmark results
  final results = <BenchmarkResult>[
    BenchmarkResult(
      name: 'Memory Allocations',
      iterations: 1000,
      platform: 'aot',
      timestamp: commits.last.timestamp,
      gitCommit: commits.last,
      primary: MeasurementResult(
        sampleTimes: List.generate(15, (i) => 150.0 + i),
        mean: 157.0,
        median: 157.0,
        stdDev: 4.5,
        meanCI: ConfidenceInterval(lowerBound: 155.0, upperBound: 159.0),
        medianCI: ConfidenceInterval(lowerBound: 155.0, upperBound: 159.0),
        outliers: OutlierAnalysis(
          lowSevere: 0,
          lowMild: 0,
          highMild: 0,
          highSevere: 0,
          outlierVariancePercentage: 0.0,
        ),
        memory: MemoryResult(
          allocatedBytesPerIteration: 2048.0,
          allocatedObjectsPerIteration: 12.0,
          rssDeltaBytes: 1024,
          classAllocations: [
            ClassAllocation(
              className: 'MyTestClass',
              libraryUri: 'package:criterion_test/my_test_class.dart',
              bytes: 7700000,
              instances: 504500,
            ),
            ClassAllocation(
              className: '_List',
              libraryUri: 'dart:core',
              bytes: 6800000,
              instances: 26061,
            ),
            ClassAllocation(
              className: '_OneByteString',
              libraryUri: 'dart:core',
              bytes: 6500000,
              instances: 140916,
            ),
            ClassAllocation(
              className: '_Uint32List',
              libraryUri: 'dart:typed_data',
              bytes: 1500000,
              instances: 15858,
            ),
            ClassAllocation(
              className: '_Map',
              libraryUri: 'dart:_compact_hash',
              bytes: 991100,
              instances: 15858,
            ),
          ],
        ),
      ),
    ),
    BenchmarkResult(
      name: 'Fibonacci Parameterized / 20',
      iterations: 1000,
      platform: 'aot',
      parameterGroup: 'Fibonacci Parameterized',
      parameterValue: 20,
      timestamp: commits.last.timestamp,
      gitCommit: commits.last,
      primary: MeasurementResult(
        sampleTimes: List.generate(15, (i) => 21.0 + (i % 3 - 1) * 0.2),
        mean: 21.0,
        median: 21.0,
        stdDev: 0.3,
        meanCI: ConfidenceInterval(lowerBound: 20.8, upperBound: 21.2),
        medianCI: ConfidenceInterval(lowerBound: 20.8, upperBound: 21.2),
        outliers: OutlierAnalysis(
          lowSevere: 0,
          lowMild: 0,
          highMild: 0,
          highSevere: 0,
          outlierVariancePercentage: 0.0,
        ),
        cpuProfile: CpuProfileResult(
          sampleCount: 12,
          samplePeriod: 1000,
          functions: [
            CpuProfileFunction(
              name: 'List.generate',
              resolvedUrl: 'dart:core-patch/growable_array.dart',
              exclusiveTicks: 4,
              inclusiveTicks: 6,
            ),
            CpuProfileFunction(
              name: 'generate',
              resolvedUrl: 'dart:array-patch/array.dart',
              exclusiveTicks: 3,
              inclusiveTicks: 4,
            ),
            CpuProfileFunction(
              name: 'collect',
              resolvedUrl: 'package:criterion/src/cpu_profiler/vm.dart',
              exclusiveTicks: 2,
              inclusiveTicks: 3,
            ),
            CpuProfileFunction(
              name: 'main.<fn>',
              resolvedUrl: 'package:criterion_test/main.dart',
              exclusiveTicks: 1,
              inclusiveTicks: 12,
            ),
          ],
        ),
      ),
    ),
  ];

  // Add Parameterized benchmarks (n = 5, 10, 15, 20)
  for (final n in [5, 10, 15, 20]) {
    results.add(
      BenchmarkResult(
        name: 'Fibonacci Parameterized / $n',
        iterations: 1000,
        platform: 'aot',
        parameterGroup: 'Fibonacci Parameterized',
        parameterValue: n,
        timestamp: commits.last.timestamp,
        gitCommit: commits.last,
        primary: MeasurementResult(
          sampleTimes: List.generate(15, (i) => (n * 1.05) + i * 0.1),
          mean: n * 1.05,
          median: n * 1.05,
          stdDev: 0.5,
          meanCI: ConfidenceInterval(lowerBound: n * 1.0, upperBound: n * 1.1),
          medianCI: ConfidenceInterval(
            lowerBound: n * 1.0,
            upperBound: n * 1.1,
          ),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
      ),
    );
  }

  // Add Variant benchmarks (tryParse vs parse)
  results.add(
    BenchmarkResult(
      name: 'Integer Parsing / tryParse',
      iterations: 1000,
      platform: 'aot',
      variantGroup: 'Integer Parsing',
      variantName: 'tryParse',
      timestamp: commits.last.timestamp,
      gitCommit: commits.last,
      primary: MeasurementResult(
        sampleTimes: List.generate(15, (i) => 6.36 + (i % 3 - 1) * 0.1),
        mean: 6.36,
        median: 6.36,
        stdDev: 0.2,
        meanCI: ConfidenceInterval(lowerBound: 6.3, upperBound: 6.4),
        medianCI: ConfidenceInterval(lowerBound: 6.3, upperBound: 6.4),
        outliers: OutlierAnalysis(
          lowSevere: 0,
          lowMild: 0,
          highMild: 0,
          highSevere: 0,
          outlierVariancePercentage: 0.0,
        ),
      ),
    ),
  );
  results.add(
    BenchmarkResult(
      name: 'Integer Parsing / parse',
      iterations: 1000,
      platform: 'aot',
      variantGroup: 'Integer Parsing',
      variantName: 'parse',
      timestamp: commits.last.timestamp,
      gitCommit: commits.last,
      primary: MeasurementResult(
        sampleTimes: List.generate(15, (i) => 9.20 + (i % 3 - 1) * 0.1),
        mean: 9.20,
        median: 9.20,
        stdDev: 0.3,
        meanCI: ConfidenceInterval(lowerBound: 9.1, upperBound: 9.3),
        medianCI: ConfidenceInterval(lowerBound: 9.1, upperBound: 9.3),
        outliers: OutlierAnalysis(
          lowSevere: 0,
          lowMild: 0,
          highMild: 0,
          highSevere: 0,
          outlierVariancePercentage: 0.0,
        ),
      ),
    ),
  );

  final config = CriterionConfig(
    reportDir: reportDir.path,
    generateHtmlReport: true,
    exportJson: false,
  );

  await ReportGenerator(config).generate(results, history: history);
}
