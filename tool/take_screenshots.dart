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
import 'package:puppeteer/puppeteer.dart';
import 'package:path/path.dart' as p;

void main() async {
  var reportPath = p.absolute('benchmark/screenshots_report/index.html');
  if (!File(reportPath).existsSync()) {
    reportPath = p.absolute('benchmark/report/index.html');
  }
  if (!File(reportPath).existsSync()) {
    print('Report not found at $reportPath');
    exit(1);
  }

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
    await Future.delayed(Duration(milliseconds: 500));
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
    await Future.delayed(Duration(milliseconds: 500));
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
    await Future.delayed(Duration(milliseconds: 500));
    final cpuCard = await page.$('#cpu-profile-card');
    final bytes = await cpuCard.screenshot();
    File(p.join(outputDir.path, 'cpu_profile.png')).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take CPU profile screenshot: $e');
  }

  // 4. Parameterized Chart (Click "Enable Parameters View")
  try {
    print('Taking parameterized chart screenshot...');
    await page.goto(
      'file://$reportPath?animate=false',
      wait: Until.networkIdle,
    );
    await Future.delayed(Duration(milliseconds: 500));
    final paramCheckbox = await page.$('#parameters-mode');
    await paramCheckbox.click();
    await Future.delayed(Duration(milliseconds: 500));
    final paramView = await page.$('#parameters-view');
    final bytes = await paramView.screenshot();
    File(
      p.join(outputDir.path, 'parameterized_chart.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take parameterized chart screenshot: $e');
  }

  // 5. Variants Comparison (Click "Enable Variants View")
  try {
    print('Taking variants comparison screenshot...');
    await page.goto(
      'file://$reportPath?animate=false',
      wait: Until.networkIdle,
    );
    await Future.delayed(Duration(milliseconds: 500));
    final variantsCheckbox = await page.$('#variants-mode');
    await variantsCheckbox.click();
    await Future.delayed(Duration(milliseconds: 500));
    final variantsView = await page.$('#variants-view');
    final bytes = await variantsView.screenshot();
    File(
      p.join(outputDir.path, 'variants_comparison.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take variants comparison screenshot: $e');
  }

  // 6. Historical Performance Trends (Click "Enable History View")
  try {
    print('Taking history timeline screenshot...');
    await page.goto(
      'file://$reportPath?animate=false&history=true',
      wait: Until.networkIdle,
    );
    await Future.delayed(Duration(milliseconds: 500));
    final historyView = await page.$('#history-view');
    final bytes = await historyView.screenshot();
    File(
      p.join(outputDir.path, 'history_timeline.png'),
    ).writeAsBytesSync(bytes);
  } catch (e) {
    print('Failed to take history timeline screenshot: $e');
  }

  await browser.close();
  print('Done! Screenshots saved to ${outputDir.path}');
}
