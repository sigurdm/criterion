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

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Path of the cycle counter C source, relative to the package root.
const _cycleCounterSource = 'lib/src/cycle_counter/cycle_counter.c';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    // Always declare the C source as a dependency, even on the paths where we
    // do not build anything. Without this, a hook run that produced no assets
    // is cached as "no assets, no dependencies" and is never re-run: editing
    // cycle_counter.c, or installing a C toolchain afterwards, would silently
    // keep serving the empty result.
    output.dependencies.add(input.packageRoot.resolve(_cycleCounterSource));

    final targetArch = input.config.code.targetArchitecture;
    if (targetArch != Architecture.x64 && targetArch != Architecture.arm64) {
      return;
    }

    final cbuilder = CBuilder.library(
      name: 'cycle_counter',
      assetName: 'src/cycle_counter/vm.dart',
      sources: [_cycleCounterSource],
    );

    try {
      await cbuilder.run(input: input, output: output);
    } catch (e) {
      // `native_toolchain_c` reports "there is no usable C toolchain on this
      // host" as a `ToolError`, and a failing compile/link invocation as a
      // `ProcessException`. Only the former is an acceptable, expected
      // degradation (the cycle counter then falls back to its Dart
      // implementation); a compile error is a real bug and must not be hidden.
      if (!_isMissingToolchain(e)) rethrow;
      final configured = input.config.code.cCompiler?.compiler;
      stderr.writeln(
        'criterion: no usable C toolchain found '
        '(input.config.code.cCompiler.compiler = ${configured ?? 'not set'}); '
        'skipping the native cycle_counter asset. Hardware cycle counting will '
        'be unavailable. Install a C compiler (clang, gcc or MSVC) and re-run '
        'to enable it. Underlying error: $e',
      );
    }
  });
}

/// Whether [error] is `native_toolchain_c`'s `ToolError`, i.e. no C toolchain
/// could be resolved on this host.
///
/// `ToolError` is not exported from `package:native_toolchain_c`, so it cannot
/// be caught by type; matching on the runtime type name is the only option
/// short of treating every failure as a missing toolchain.
bool _isMissingToolchain(Object error) =>
    error is Error && error.runtimeType.toString() == 'ToolError';
