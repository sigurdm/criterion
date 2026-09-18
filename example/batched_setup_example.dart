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

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:criterion/criterion.dart';

/// Represents a large buffer allocation that would cause memory exhaustion
/// if pre-allocated for all benchmark iterations simultaneously.
class LargeBuffer {
  final List<double> data;

  LargeBuffer(int size) : data = List<double>.filled(size, 1.0);

  void mutate() {
    for (var i = 0; i < data.length; i++) {
      data[i] += 0.5;
    }
  }
}

void main() async {
  final criterion = Criterion();

  // By default, when a setup callback is provided, Criterion uses
  // BatchSize.smallInput (batches of 1000) to keep memory usage bounded.
  criterion.bench<List<int>>(
    'Sort List (Default Batched Setup)',
    (list) => list.sort(),
    setup: () => [5, 2, 8, 1, 9, 3, 7, 4, 6, 0],
  );

  // For native resources (e.g. allocating FFI memory pointers),
  // BatchSize.perIteration (batch size of 1) combined with teardown cleanly
  // frees the pointer after each iteration outside the measured timing loop.
  criterion.bench<Pointer<Uint8>>(
    'Native Memory Buffer (BatchSize.perIteration + teardown)',
    (Pointer<Uint8> ptr) {
      ptr.asTypedList(1024).fillRange(0, 1024, 42);
    },
    setup: () => calloc<Uint8>(1024),
    teardown: calloc.free,
    batchSize: BatchSize.perIteration,
  );

  // For large objects (e.g. allocating huge matrices or buffers),
  // BatchSize.largeInput (batch size of 1) allocates 1 state per batch
  // timer start/stop, preventing heap exhaustion on high iteration counts.
  criterion.bench<LargeBuffer>(
    'Mutate Large Buffer (BatchSize.largeInput)',
    (buffer) => buffer.mutate(),
    setup: () => LargeBuffer(100000),
    batchSize: BatchSize.largeInput,
  );

  // Custom batch sizes can be configured using BatchSize.numIterations(n).
  criterion.bench<int>(
    'Parse Integer (Custom Batch Size 50)',
    (val) => int.parse(val.toString()),
    setup: () => 42,
    batchSize: BatchSize.numIterations(50),
  );

  await criterion.run();
}
