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
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

void main(List<String> args) async {
  final skipRun = args.contains('--skip-run');

  final gitRoot = Directory.current.path;
  final reportHtml = File(p.join(gitRoot, 'benchmark/report/index.html'));

  if (!skipRun) {
    print('Running sample suite to generate report...');
    final runResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/run.dart',
      'benchmark/sample_suite.dart',
    ]);
    if (runResult.exitCode != 0) {
      stderr.writeln('Error running sample suite:');
      stderr.writeln(runResult.stdout);
      stderr.writeln(runResult.stderr);
      exit(1);
    }
    print('Report generated.');
  }

  if (!reportHtml.existsSync()) {
    stderr.writeln('Error: Report file not found at ${reportHtml.path}');
    exit(1);
  }

  final docImagesDir = Directory(p.join(gitRoot, 'doc/images'));
  if (!docImagesDir.existsSync()) {
    docImagesDir.createSync(recursive: true);
  }

  final htmlUrl = 'file://${reportHtml.absolute.path}';

  print('Launching Puppeteer browser...');
  // This will download Chromium if it's not already downloaded.
  final browser = await puppeteer.launch();
  print('Browser launched.');

  try {
    print('Generating single report screenshot...');
    final page1 = await browser.newPage();
    await page1.setViewport(DeviceViewport(width: 1280, height: 1080));
    await page1.goto(
      '$htmlUrl?animate=false&bench=0',
      wait: Until.networkAlmostIdle,
    );
    // Wait a small bit for JS to render charts just in case
    await Future.delayed(const Duration(milliseconds: 500));
    final singleFile = File(p.join(docImagesDir.path, 'single_report.jpg'));
    final singleBytes = await page1.screenshot(
      fullPage: false,
      format: ScreenshotFormat.jpeg,
    );
    await singleFile.writeAsBytes(singleBytes);
    print('Saved to ${singleFile.path}');

    print('Generating comparison report screenshot...');
    final page2 = await browser.newPage();
    await page2.setViewport(DeviceViewport(width: 1280, height: 1080));
    await page2.goto(
      '$htmlUrl?animate=false&compare=true&select=0,1',
      wait: Until.networkAlmostIdle,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    final compareFile = File(
      p.join(docImagesDir.path, 'comparison_report.jpg'),
    );
    final compareBytes = await page2.screenshot(
      fullPage: false,
      format: ScreenshotFormat.jpeg,
    );
    await compareFile.writeAsBytes(compareBytes);
    print('Saved to ${compareFile.path}');
  } catch (e, stack) {
    stderr.writeln('Error generating screenshots: $e');
    stderr.writeln(stack);
  } finally {
    await browser.close();
  }
}
