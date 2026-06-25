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

import "dart:io";
import "package:criterion/criterion.dart";

void main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln("Usage: compare <before.json> <after.json>");
    exit(1);
  }

  final beforeFile = File(args[0]);
  final afterFile = File(args[1]);

  if (!await beforeFile.exists()) {
    stderr.writeln("Error: File not found: ${beforeFile.path}");
    exit(1);
  }
  if (!await afterFile.exists()) {
    stderr.writeln("Error: File not found: ${afterFile.path}");
    exit(1);
  }

  List<BenchmarkResult> beforeResults;
  List<BenchmarkResult> afterResults;

  try {
    beforeResults = loadResults(await beforeFile.readAsString());
  } catch (e) {
    stderr.writeln("Error parsing ${beforeFile.path}: $e");
    exit(1);
  }

  try {
    afterResults = loadResults(await afterFile.readAsString());
  } catch (e) {
    stderr.writeln("Error parsing ${afterFile.path}: $e");
    exit(1);
  }

  final comparison = compareResults(beforeResults, afterResults);
  stdout.write(comparison.toMarkdownTable());
}
