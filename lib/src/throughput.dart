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

/// Represents a throughput metric.
final class Throughput {
  /// The quantity of the metric (e.g., number of bytes or elements).
  final int count;

  /// The unit of the metric.
  final ThroughputUnit unit;

  const Throughput._(this.count, this.unit);

  /// Creates a throughput metric in bytes.
  const Throughput.bytes(int count) : this._(count, ThroughputUnit.bytes);

  /// Creates a throughput metric in elements.
  const Throughput.elements(int count) : this._(count, ThroughputUnit.elements);

  /// Converts this throughput to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {'count': count, 'unit': unit.name};
  }

  /// Creates a [Throughput] from a JSON map.
  factory Throughput.fromJson(Map<String, dynamic> json) {
    final count = json['count'] as int;
    final unitName = json['unit'] as String;
    final unit = ThroughputUnit.values.byName(unitName);
    if (unit == ThroughputUnit.bytes) {
      return Throughput.bytes(count);
    } else {
      return Throughput.elements(count);
    }
  }
}

/// The unit of throughput.
enum ThroughputUnit {
  /// Bytes per second.
  bytes,

  /// Elements per second.
  elements,
}
