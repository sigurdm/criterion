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
  group("JSON Serialization", () {
    test("HostEnvironment toJson / fromJson", () {
      final env = HostEnvironment(os: "linux", dartSdkVersion: "3.12.0");
      final jsonMap = env.toJson();
      expect(jsonMap["os"], equals("linux"));
      expect(jsonMap["dartSdkVersion"], equals("3.12.0"));

      final decoded = HostEnvironment.fromJson(jsonMap);
      expect(decoded.os, equals("linux"));
      expect(decoded.dartSdkVersion, equals("3.12.0"));
    });

    test("BenchmarkResult toJson / fromJson roundtrip", () async {
      final c = Criterion();
      c.bench(
        "test_bench",
        () {},
        samples: 5,
        warmupDuration: const Duration(milliseconds: 5),
      );
      final results = await c.run();
      expect(results.length, equals(1));
      final result = results.first;

      final jsonMap = result.toJson();
      expect(jsonMap["name"], equals("test_bench"));
      expect(jsonMap["hostEnvironment"], isNotNull);
      expect(jsonMap["platform"], equals("jit"));
      expect(jsonMap["timestamp"], isNotNull);

      final decoded = BenchmarkResult.fromJson(jsonMap);
      expect(decoded.name, equals(result.name));
      expect(decoded.iterations, equals(result.iterations));
      expect(decoded.platform, equals(result.platform));
      expect(
        decoded.timestamp.toIso8601String(),
        equals(result.timestamp.toIso8601String()),
      );
      expect(decoded.hostEnvironment.os, equals(result.hostEnvironment.os));
      expect(
        decoded.hostEnvironment.dartSdkVersion,
        equals(result.hostEnvironment.dartSdkVersion),
      );
      expect(decoded.primary.mean, closeTo(result.primary.mean, 0.0001));
    });
  });
}
