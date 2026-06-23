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

import 'dart:io';
import 'package:path/path.dart' as p;

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

  final chromePath = '/usr/bin/google-chrome'; // Found in previous step
  final htmlUrl = 'file://${reportHtml.absolute.path}';

  print('Generating single report screenshot...');
  final singleResult = await Process.run(chromePath, [
    '--headless',
    '--disable-gpu',
    '--screenshot=${p.join(docImagesDir.path, 'single_report.png')}',
    '--window-size=1280,1080',
    '$htmlUrl?animate=false&bench=0',
  ]);
  if (singleResult.exitCode != 0) {
    stderr.writeln(
      'Failed to generate single report screenshot: ${singleResult.stderr}',
    );
  } else {
    print('Saved to doc/images/single_report.png');
  }

  print('Generating comparison report screenshot...');
  final compareResult = await Process.run(chromePath, [
    '--headless',
    '--disable-gpu',
    '--screenshot=${p.join(docImagesDir.path, 'comparison_report.png')}',
    '--window-size=1280,1080',
    '$htmlUrl?animate=false&compare=true&select=0,1',
  ]);
  if (compareResult.exitCode != 0) {
    stderr.writeln(
      'Failed to generate comparison report screenshot: ${compareResult.stderr}',
    );
  } else {
    print('Saved to doc/images/comparison_report.png');
  }
}
