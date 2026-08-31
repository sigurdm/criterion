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

import 'package:criterion/src/dart_environment.dart';
import 'package:test/test.dart';

void main() {
  group('dart_environment', () {
    test('dartDefineFlags emits expected environment define flags', () {
      final flags = dartDefineFlags(
        platform: 'jit',
        os: 'linux',
        dartSdkVersion: '3.14.0',
        json: true,
      );

      expect(flags, [
        '-Dcriterion.platform=jit',
        '-Dcriterion.os=linux',
        '-Dcriterion.dart_sdk_version=3.14.0',
        '-Dcriterion.json=true',
      ]);
    });

    test('dartDefineFlags handles false json flag and custom values', () {
      final flags = dartDefineFlags(
        platform: 'wasm',
        os: 'macos',
        dartSdkVersion: '3.12.0',
        json: false,
      );

      expect(flags, [
        '-Dcriterion.platform=wasm',
        '-Dcriterion.os=macos',
        '-Dcriterion.dart_sdk_version=3.12.0',
        '-Dcriterion.json=false',
      ]);
    });
  });
}
