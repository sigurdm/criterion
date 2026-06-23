// Copyright 2026 Sigurd Meldgaard
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

import 'dart:convert';
import 'dart:io';
import '../config.dart';
import '../result.dart';

/// Generates reports (JSON and HTML) from benchmark results.
final class ReportGenerator {
  /// The configuration options.
  final CriterionConfig config;

  /// Creates a new [ReportGenerator].
  ReportGenerator(this.config);

  /// Generates the enabled reports for the given [results].
  Future<void> generate(List<BenchmarkResult> results) async {
    if (!config.exportJson && !config.generateHtmlReport) {
      return;
    }

    final directory = Directory(config.reportDir);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    if (config.exportJson) {
      await _exportJson(results, directory);
    }

    if (config.generateHtmlReport) {
      await _generateHtml(results, directory);
    }
  }

  Future<void> _exportJson(
    List<BenchmarkResult> results,
    Directory directory,
  ) async {
    final file = File('${directory.path}/results.json');
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(results.map((r) => r.toJson()).toList());
    await file.writeAsString(jsonString);
    print('Exported JSON results to: ${file.path}');
  }

  Future<void> _generateHtml(
    List<BenchmarkResult> results,
    Directory directory,
  ) async {
    final file = File('${directory.path}/index.html');
    final htmlContent = _buildHtml(results);
    await file.writeAsString(htmlContent);
    print('Generated HTML report at: ${file.path}');
  }

  String _buildHtml(List<BenchmarkResult> results) {
    final jsonResults = jsonEncode(results.map((r) => r.toJson()).toList());

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Criterion Benchmark Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            margin: 0;
            padding: 20px;
            background-color: #f5f7fa;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        header {
            margin-bottom: 30px;
            border-bottom: 1px solid #e1e4e8;
            padding-bottom: 20px;
        }
        h1 {
            margin: 0;
            color: #24292e;
        }
        .grid {
            display: grid;
            grid-template-columns: 250px 1fr;
            gap: 20px;
        }
        .sidebar {
            background: #fff;
            padding: 20px;
            border-radius: 6px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .main-content {
            background: #fff;
            padding: 20px;
            border-radius: 6px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .card {
            background: #fff;
            border: 1px solid #e1e4e8;
            border-radius: 6px;
            padding: 15px;
            margin-bottom: 20px;
        }
        .card h3 {
            margin-top: 0;
        }
        .chart-container {
            position: relative;
            margin: auto;
            height: 400px;
            width: 100%;
        }
        .benchmark-select {
            width: 100%;
            padding: 8px;
            margin-bottom: 10px;
            border: 1px solid #d1d5da;
            border-radius: 3px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #e1e4e8;
        }
        th {
            background-color: #f6f8fa;
        }
        .metric-value {
            font-family: monospace;
            font-weight: bold;
        }
        .checkbox-group {
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #d1d5da;
            padding: 10px;
            border-radius: 3px;
            margin-bottom: 15px;
        }
        .checkbox-item {
            display: flex;
            align-items: center;
            margin-bottom: 5px;
        }
        .checkbox-item input {
            margin-right: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Criterion Benchmark Report</h1>
            <p>Generated on ${DateTime.now().toLocal().toString()}</p>
        </header>
        <div class="grid">
            <div class="sidebar">
                <h3>Benchmarks</h3>
                <div class="checkbox-group" id="benchmark-list">
                    <!-- Dynamic benchmark list -->
                </div>
                <h3>Comparison Mode</h3>
                <label>
                    <input type="checkbox" id="compare-mode"> Enable Comparison
                </label>
                
                <div id="variants-mode-container" style="display:none; margin-top: 15px;">
                    <h3>Variants Mode</h3>
                    <label>
                        <input type="checkbox" id="variants-mode"> Enable Variants View
                    </label>
                </div>
            </div>
            <div class="main-content">
                <div id="single-view">
                    <h2 id="active-benchmark-name">Select a benchmark</h2>
                    
                    <div class="card">
                        <h3>Summary</h3>
                        <table id="summary-table">
                            <!-- Dynamic summary -->
                        </table>
                    </div>

                    <div class="card">
                        <h3>Time Distribution (Kernel Density Estimation)</h3>
                        <div class="chart-container">
                            <canvas id="kdeChart"></canvas>
                        </div>
                    </div>

                    <div class="card">
                        <h3>Iteration Variance (Scatter)</h3>
                        <div class="chart-container">
                            <canvas id="scatterChart"></canvas>
                        </div>
                    </div>

                    <div class="card" id="memory-card" style="display:none;">
                        <h3>Memory Analysis</h3>
                        <div class="chart-container">
                            <canvas id="memoryChart"></canvas>
                        </div>
                    </div>

                    <div class="card" id="ffi-card" style="display:none;">
                        <h3>FFI Overhead Analysis</h3>
                        <div class="chart-container">
                            <canvas id="ffiChart"></canvas>
                        </div>
                    </div>
                </div>
                
                <div id="comparison-view" style="display:none;">
                    <h2>Benchmark Comparison</h2>
                    <div class="card">
                        <h3>Overlapping Kernel Density Estimation (Time Distribution)</h3>
                        <div class="chart-container">
                            <canvas id="compareKdeChart"></canvas>
                        </div>
                    </div>
                    <div class="card">
                        <h3>Performance Comparison</h3>
                        <div class="chart-container">
                            <canvas id="compareBarChart"></canvas>
                        </div>
                    </div>
                </div>
                
                <div id="variants-view" style="display:none;">
                    <h2>Variant Groups Comparison</h2>
                    <div id="variant-groups-container">
                        <!-- Dynamic variant groups charts will be inserted here -->
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        const data = $jsonResults;
        console.log("Loaded data:", data);

        // Helper functions
        function formatDuration(ns) {
            if (ns < 1.0) return (ns * 1000).toFixed(2) + ' ps';
            if (ns < 1000.0) return ns.toFixed(2) + ' ns';
            const us = ns / 1000.0;
            if (us < 1000.0) return us.toFixed(2) + ' μs';
            const ms = us / 1000.0;
            if (ms < 1000.0) return ms.toFixed(2) + ' ms';
            const s = ms / 1000.0;
            return s.toFixed(2) + ' s';
        }

        function formatBytes(bytes) {
            if (bytes < 1024) return bytes.toFixed(1) + ' B';
            const kb = bytes / 1024;
            if (kb < 1024) return kb.toFixed(1) + ' KB';
            const mb = kb / 1024;
            return mb.toFixed(1) + ' MB';
        }

        function formatCount(count) {
            return Math.round(count).toLocaleString();
        }

        // KDE Math
        function stdDev(values) {
            const mean = values.reduce((a, b) => a + b) / values.length;
            const variance = values.map(x => (x - mean) ** 2).reduce((a, b) => a + b) / (values.length - 1);
            return Math.sqrt(variance);
        }

        function silvermanBandwidth(values) {
            const sigma = stdDev(values);
            const n = values.length;
            if (sigma === 0 || n === 0) return 1;
            return sigma * Math.pow(4 / (3 * n), 0.2);
        }

        function gaussianKernel(x) {
            return Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math.PI);
        }

        function getKdeData(values) {
            const bandwidth = silvermanBandwidth(values);
            const min = Math.min(...values);
            const max = Math.max(...values);
            const range = max - min;
            
            // Generate points
            const steps = 100;
            const points = [];
            const start = min - 3 * bandwidth;
            const end = max + 3 * bandwidth;
            const step = (end - start) / steps;
            for (let i = 0; i <= steps; i++) {
                points.push(start + i * step);
            }

            const n = values.length;
            const densities = points.map(x => {
                let sum = 0;
                for (let i = 0; i < n; i++) {
                    sum += gaussianKernel((x - values[i]) / bandwidth);
                }
                return sum / (n * bandwidth);
            });

            return points.map((x, i) => ({ x: x, y: densities[i] }));
        }

        // State
        let activeBenchmark = null;
        let selectedBenchmarks = [];
        let compareMode = false;

        // Chart instances
        let kdeChart = null;
        let scatterChart = null;
        let memoryChart = null;
        let ffiChart = null;
        let compareKdeChart = null;
        let compareBarChart = null;
        const variantCharts = [];

        // Colors
        const colors = [
            'rgba(54, 162, 235, 1)',
            'rgba(255, 99, 132, 1)',
            'rgba(75, 192, 192, 1)',
            'rgba(255, 206, 86, 1)',
            'rgba(153, 102, 255, 1)',
            'rgba(255, 159, 64, 1)'
        ];
        const bgColors = [
            'rgba(54, 162, 235, 0.2)',
            'rgba(255, 99, 132, 0.2)',
            'rgba(75, 192, 192, 0.2)',
            'rgba(255, 206, 86, 0.2)',
            'rgba(153, 102, 255, 0.2)',
            'rgba(255, 159, 64, 0.2)'
        ];

        function getColors(count) {
            const result = [];
            for (let i = 0; i < count; i++) {
                result.push(colors[i % colors.length]);
            }
            return result;
        }
        function getBgColors(count) {
            const result = [];
            for (let i = 0; i < count; i++) {
                result.push(bgColors[i % bgColors.length]);
            }
            return result;
        }

        // Detect variants
        const variantGroups = {};
        data.forEach(bench => {
            if (bench.variantGroup) {
                if (!variantGroups[bench.variantGroup]) {
                    variantGroups[bench.variantGroup] = [];
                }
                variantGroups[bench.variantGroup].push(bench);
            }
        });
        const hasVariants = Object.keys(variantGroups).length > 0;

        // Init
        const benchmarkList = document.getElementById('benchmark-list');
        data.forEach((bench, index) => {
            const div = document.createElement('div');
            div.className = 'checkbox-item';
            div.innerHTML = `
                <input type="checkbox" id="bench-\${index}" value="\${bench.name}">
                <label for="bench-\${index}">\${bench.name}</label>
            `;
            benchmarkList.appendChild(div);
            
            // Handle selection
            const checkbox = div.querySelector('input');
            checkbox.addEventListener('change', (e) => {
                if (compareMode) {
                    if (e.target.checked) {
                        selectedBenchmarks.push(bench);
                    } else {
                        selectedBenchmarks = selectedBenchmarks.filter(b => b.name !== bench.name);
                    }
                    updateComparisonView();
                } else {
                    // Single mode: uncheck others, set active
                    if (e.target.checked) {
                        data.forEach((_, i) => {
                            if (i !== index) {
                                document.getElementById(`bench-\${i}`).checked = false;
                            }
                        });
                        selectedBenchmarks = [bench];
                        activeBenchmark = bench;
                        updateSingleView();
                    } else {
                        activeBenchmark = null;
                        selectedBenchmarks = [];
                        // Clear view
                    }
                }
            });
        });

        if (hasVariants) {
            document.getElementById('variants-mode-container').style.display = 'block';
        }

        const variantsModeCheckbox = document.getElementById('variants-mode');
        let variantsMode = false;
        let variantChartsGenerated = false;

        const compareModeCheckbox = document.getElementById('compare-mode');
        compareModeCheckbox.addEventListener('change', (e) => {
            compareMode = e.target.checked;
            if (compareMode && hasVariants) {
                variantsModeCheckbox.checked = false;
                variantsMode = false;
                document.getElementById('variants-view').style.display = 'none';
            }
            // Reset selections
            data.forEach((_, i) => {
                document.getElementById(`bench-\${i}`).checked = false;
            });
            selectedBenchmarks = [];
            activeBenchmark = null;
            
            if (compareMode) {
                document.getElementById('single-view').style.display = 'none';
                document.getElementById('comparison-view').style.display = 'block';
                updateComparisonView();
            } else {
                document.getElementById('single-view').style.display = 'block';
                document.getElementById('comparison-view').style.display = 'none';
                updateSingleView();
            }
        });

        variantsModeCheckbox.addEventListener('change', (e) => {
            variantsMode = e.target.checked;
            if (variantsMode) {
                compareModeCheckbox.checked = false;
                compareMode = false;
                data.forEach((_, i) => {
                    document.getElementById(`bench-\${i}`).checked = false;
                });
                selectedBenchmarks = [];
                activeBenchmark = null;
                
                document.getElementById('single-view').style.display = 'none';
                document.getElementById('comparison-view').style.display = 'none';
                document.getElementById('variants-view').style.display = 'block';
                if (!variantChartsGenerated) {
                    generateVariantCharts();
                    variantChartsGenerated = true;
                }
            } else {
                document.getElementById('single-view').style.display = 'block';
                document.getElementById('variants-view').style.display = 'none';
                if (data.length > 0) {
                    document.getElementById('bench-0').checked = true;
                    selectedBenchmarks = [data[0]];
                    activeBenchmark = data[0];
                    updateSingleView();
                }
            }
        });

        // URL Parameter handling for automation/screenshots
        const urlParams = new URLSearchParams(window.location.search);
        
        // Disable animations if requested
        if (urlParams.get('animate') === 'false') {
            Chart.defaults.animation = false;
        }

        const benchParam = urlParams.get('bench');
        const compareParam = urlParams.get('compare');
        const selectParam = urlParams.get('select');

        if (compareParam === 'true') {
            compareModeCheckbox.checked = true;
            compareMode = true;
            document.getElementById('single-view').style.display = 'none';
            document.getElementById('comparison-view').style.display = 'block';
            
            if (selectParam) {
                const indices = selectParam.split(',').map(s => s.trim());
                indices.forEach(idxOrName => {
                    let index = parseInt(idxOrName, 10);
                    if (isNaN(index)) {
                        index = data.findIndex(b => b.name === idxOrName);
                    }
                    if (index >= 0 && index < data.length) {
                        document.getElementById(`bench-\${index}`).checked = true;
                        selectedBenchmarks.push(data[index]);
                    }
                });
                updateComparisonView();
            }
        } else if (benchParam) {
            let index = parseInt(benchParam, 10);
            if (isNaN(index)) {
                index = data.findIndex(b => b.name === benchParam);
            }
            if (index >= 0 && index < data.length) {
                document.getElementById(`bench-\${index}`).checked = true;
                selectedBenchmarks = [data[index]];
                activeBenchmark = data[index];
                updateSingleView();
            }
        } else {
            // Default to select first benchmark if nothing specified
            if (data.length > 0) {
                document.getElementById('bench-0').checked = true;
                selectedBenchmarks = [data[0]];
                activeBenchmark = data[0];
                updateSingleView();
            }
        }

        function updateSingleView() {
            if (!activeBenchmark) {
                document.getElementById('active-benchmark-name').innerText = 'Select a benchmark';
                return;
            }

            document.getElementById('active-benchmark-name').innerText = activeBenchmark.name;
            
            // Fill table
            const primary = activeBenchmark.primary;
            let html = `
                <tr><th>Metric</th><th>Value</th><th>95% Confidence Interval</th></tr>
                <tr><td>Mean Time</td><td class="metric-value">\${formatDuration(primary.mean)}</td><td>[\${formatDuration(primary.meanCI.lowerBound)}, \${formatDuration(primary.meanCI.upperBound)}]</td></tr>
                <tr><td>Median Time</td><td class="metric-value">\${formatDuration(primary.median)}</td><td>[\${formatDuration(primary.medianCI.lowerBound)}, \${formatDuration(primary.medianCI.upperBound)}]</td></tr>
                <tr><td>Std Dev</td><td class="metric-value">\${formatDuration(primary.stdDev)}</td><td>-</td></tr>
                <tr><td>Outliers</td><td>\${primary.outliers.lowSevere + primary.outliers.lowMild + primary.outliers.highMild + primary.outliers.highSevere} / \${primary.sampleTimes.length}</td><td>Variance: \${primary.outliers.outlierVariancePercentage.toFixed(1)}%</td></tr>
            `;
            
            if (primary.memory) {
                if (primary.memory.allocatedBytesPerIteration !== null && primary.memory.allocatedBytesPerIteration !== undefined) {
                    html += `
                        <tr><td>Allocated Bytes</td><td class="metric-value">\${formatBytes(primary.memory.allocatedBytesPerIteration)}</td><td>-</td></tr>
                        <tr><td>Allocated Objects</td><td class="metric-value">\${formatCount(primary.memory.allocatedObjectsPerIteration)}</td><td>-</td></tr>
                    `;
                }
                html += `
                    <tr><td>RSS Delta</td><td class="metric-value">\${formatBytes(primary.memory.rssDeltaBytes)}</td><td>-</td></tr>
                `;
            }
            if (primary.instructions) {
                html += `
                    <tr><td>Instructions</td><td class="metric-value">\${formatCount(primary.instructions.instructionsPerIteration)}</td><td>-</td></tr>
                `;
            }
            if (activeBenchmark.throughput) {
                const tp = activeBenchmark.throughput;
                const meanSec = primary.mean / 1e9;
                const rate = tp.count / meanSec;
                const rateStr = tp.unit === 'bytes' ? formatBytes(rate) + '/s' : formatCount(rate) + ' elements/s';
                html += `<tr><td>Throughput</td><td class="metric-value">\${rateStr}</td><td>-</td></tr>`;
            }
            document.getElementById('summary-table').innerHTML = html;

            // KDE Chart
            const kdeData = getKdeData(primary.sampleTimes);
            if (kdeChart) kdeChart.destroy();
            kdeChart = new Chart(document.getElementById('kdeChart'), {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'KDE',
                        data: kdeData,
                        borderColor: colors[0],
                        backgroundColor: bgColors[0],
                        fill: true,
                        pointRadius: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'linear',
                            title: { display: true, text: 'Time' },
                            ticks: { callback: value => formatDuration(value) }
                        },
                        y: { title: { display: true, text: 'Density' } }
                    }
                }
            });

            // Scatter Chart
            const scatterData = primary.sampleTimes.map((t, i) => ({ x: i + 1, y: t }));
            if (scatterChart) scatterChart.destroy();
            scatterChart = new Chart(document.getElementById('scatterChart'), {
                type: 'scatter',
                data: {
                    datasets: [{
                        label: 'Iteration Time',
                        data: scatterData,
                        backgroundColor: colors[0]
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: { title: { display: true, text: 'Iteration' } },
                        y: {
                            title: { display: true, text: 'Time' },
                            ticks: { callback: value => formatDuration(value) }
                        }
                    }
                }
            });

            // Memory Chart
            const memoryCard = document.getElementById('memory-card');
            if (primary.memory) {
                memoryCard.style.display = 'block';
                if (memoryChart) memoryChart.destroy();
                
                const labels = [];
                const datasetData = [];
                if (primary.memory.allocatedBytesPerIteration !== null && primary.memory.allocatedBytesPerIteration !== undefined) {
                    labels.push('Allocated Bytes');
                    datasetData.push(primary.memory.allocatedBytesPerIteration);
                }
                labels.push('RSS Delta');
                datasetData.push(primary.memory.rssDeltaBytes);
                
                memoryChart = new Chart(document.getElementById('memoryChart'), {
                    type: 'bar',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'Bytes',
                            data: datasetData,
                            backgroundColor: bgColors.slice(0, labels.length),
                            borderColor: colors.slice(0, labels.length),
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                ticks: { callback: value => formatBytes(value) }
                            }
                        }
                    }
                });
            } else {
                memoryCard.style.display = 'none';
            }

            // FFI Chart
            const ffiCard = document.getElementById('ffi-card');
            if (activeBenchmark.noOp && activeBenchmark.net) {
                ffiCard.style.display = 'block';
                if (ffiChart) ffiChart.destroy();

                ffiChart = new Chart(document.getElementById('ffiChart'), {
                    type: 'bar',
                    data: {
                        labels: ['Time (ns)'],
                        datasets: [
                            {
                                label: 'Total',
                                data: [activeBenchmark.primary.mean],
                                backgroundColor: bgColors[0],
                                borderColor: colors[0],
                                borderWidth: 1
                            },
                            {
                                label: 'Overhead',
                                data: [activeBenchmark.noOp.mean],
                                backgroundColor: bgColors[1],
                                borderColor: colors[1],
                                borderWidth: 1
                            },
                            {
                                label: 'Net',
                                data: [activeBenchmark.net.timeNs],
                                backgroundColor: bgColors[2],
                                borderColor: colors[2],
                                borderWidth: 1
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                ticks: { callback: value => formatDuration(value) }
                            }
                        }
                    }
                });
            } else {
                ffiCard.style.display = 'none';
            }
        }

        function updateComparisonView() {
            if (selectedBenchmarks.length === 0) {
                if (compareKdeChart) compareKdeChart.destroy();
                if (compareBarChart) compareBarChart.destroy();
                return;
            }

            // Compare KDE
            const kdeDatasets = selectedBenchmarks.map((bench, i) => {
                const kdeData = getKdeData(bench.primary.sampleTimes);
                return {
                    label: bench.name,
                    data: kdeData,
                    borderColor: colors[i % colors.length],
                    backgroundColor: bgColors[i % bgColors.length],
                    fill: false,
                    pointRadius: 0
                };
            });

            if (compareKdeChart) compareKdeChart.destroy();
            compareKdeChart = new Chart(document.getElementById('compareKdeChart'), {
                type: 'line',
                data: { datasets: kdeDatasets },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'linear',
                            title: { display: true, text: 'Time' },
                            ticks: { callback: value => formatDuration(value) }
                        },
                        y: { title: { display: true, text: 'Density' } }
                    }
                }
            });

            // Compare Bar
            if (compareBarChart) compareBarChart.destroy();
            compareBarChart = new Chart(document.getElementById('compareBarChart'), {
                type: 'bar',
                data: {
                    labels: selectedBenchmarks.map(b => b.name),
                    datasets: [{
                        label: 'Mean Time',
                        data: selectedBenchmarks.map(b => b.primary.mean),
                        backgroundColor: bgColors.slice(0, selectedBenchmarks.length),
                        borderColor: colors.slice(0, selectedBenchmarks.length),
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: {
                            ticks: { callback: value => formatDuration(value) }
                        }
                    }
                }
            });
        }

        function generateVariantCharts() {
            const container = document.getElementById('variant-groups-container');
            container.innerHTML = '';
            variantCharts.forEach(chart => chart.destroy());
            variantCharts.length = 0;

            Object.entries(variantGroups).forEach(([groupName, benches], groupIndex) => {
                const card = document.createElement('div');
                card.className = 'card';
                card.innerHTML = `
                    <h3>\${groupName}</h3>
                    <div class="chart-container">
                        <canvas id="variant-chart-\${groupIndex}"></canvas>
                    </div>
                `;
                container.appendChild(card);

                const ctx = document.getElementById(`variant-chart-\${groupIndex}`).getContext('2d');
                const labels = benches.map(b => b.variantName || b.name);
                const chartData = benches.map(b => b.primary.mean);

                const chart = new Chart(ctx, {
                    type: 'bar',
                    data: {
                        labels: labels,
                        datasets: [{
                            label: 'Mean Time',
                            data: chartData,
                            backgroundColor: getBgColors(benches.length),
                            borderColor: getColors(benches.length),
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                ticks: { callback: value => formatDuration(value) }
                            }
                        }
                    }
                });
                variantCharts.push(chart);
            });
        }
    </script>
</body>
</html>
''';
  }
}
