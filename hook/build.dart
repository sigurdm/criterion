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

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetArch = input.config.code.targetArchitecture;
    if (targetArch != Architecture.x64 && targetArch != Architecture.arm64) {
      return;
    }

    final cbuilder = CBuilder.library(
      name: 'cycle_counter',
      assetName: 'src/cycle_counter/vm.dart',
      sources: ['lib/src/cycle_counter/cycle_counter.c'],
    );

    try {
      await cbuilder.run(input: input, output: output);
    } catch (_) {
      // If no C toolchain is installed, build hook succeeds without failing.
    }
  });
}
