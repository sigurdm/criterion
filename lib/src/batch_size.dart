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

/// Controls how state generation from a setup function is batched during
/// benchmarking.
///
/// When a setup function generates states that allocate significant memory or
/// when the benchmark iteration count scales to high numbers, pre-allocating all
/// states at once causes memory exhaustion (O(iterations) memory usage) and CPU
/// cache eviction.
///
/// Batching executes the measurement loop in smaller increments of
/// [batchSizeFor] iterations, generating and discarding states per batch
/// (O(batch) memory usage) while accumulating total stopwatch ticks, hardware
/// instructions, and memory allocation profiles.
///
/// Example usage:
/// ```dart
/// c.benchState<List<int>>(
///   'sort buffer',
///   (list) => list.sort(),
///   setup: () => [5, 2, 8, 1, 9],
///   batchSize: BatchSize.numIterations(50),
/// );
/// ```
///
/// A complete runnable program covering every batch mode:
///
/// {@example /example/batched_setup_example.dart#batch-modes}
sealed class BatchSize {
  const BatchSize();

  /// Allocates states in batches of 1000 iterations per timer start/stop.
  ///
  /// This is the default batch mode when a setup function is provided.
  /// It is ideal for small to medium inputs (like primitives, records, or
  /// small objects) that allocate minimal memory, bounding heap usage while
  /// introducing negligible stopwatch start/stop overhead (< 0.02 ns/iter).
  static const BatchSize smallInput = _FixedBatchSize(1000, 'smallInput');

  /// Allocates a single state per timer start/stop (batch size of 1).
  ///
  /// Suitable for large inputs (like vectors, matrices, image buffers, or FFI
  /// allocations) that allocate large amounts of memory or where every setup
  /// state must immediately be freed after one iteration.
  static const BatchSize largeInput = _FixedBatchSize(1, 'largeInput');

  /// Allocates a single state per timer start/stop (alias for [largeInput]).
  static const BatchSize perIteration = _FixedBatchSize(1, 'perIteration');

  /// Allocates all states for a measurement run in a single unbatched pass.
  ///
  /// This disables batching and pre-allocates O(iterations) states before
  /// timing the loop.
  static const BatchSize unbatched = _Unbatched('unbatched');

  /// Allocates all states for a measurement run in a single unbatched pass
  /// (alias for [unbatched]).
  static const BatchSize all = _Unbatched('all');

  /// Creates a custom batch size that allocates [n] states per timer start/stop.
  ///
  /// Preconditions:
  /// * [n] must be greater than 0.
  ///
  /// Throws [ArgumentError] if [n] is less than or equal to 0.
  factory BatchSize.numIterations(int n) {
    if (n <= 0) {
      throw ArgumentError.value(n, 'n', 'Batch size must be greater than 0.');
    }
    return _FixedBatchSize(n, 'numIterations($n)');
  }

  /// Calculates the number of iterations to run in the next batch given the
  /// [remainingIterations] left in the current measurement run.
  ///
  /// Preconditions:
  /// * [remainingIterations] must be greater than 0.
  ///
  /// Performance considerations:
  /// * Runs in O(1) time and O(1) space.
  int batchSizeFor(int remainingIterations);
}

final class _FixedBatchSize extends BatchSize {
  final int size;
  final String _label;

  const _FixedBatchSize(this.size, this._label);

  @override
  int batchSizeFor(int remainingIterations) =>
      size < remainingIterations ? size : remainingIterations;

  @override
  String toString() => 'BatchSize.$_label';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _FixedBatchSize && other.size == size);

  @override
  int get hashCode => size.hashCode;
}

final class _Unbatched extends BatchSize {
  final String _label;

  const _Unbatched(this._label);

  @override
  int batchSizeFor(int remainingIterations) => remainingIterations;

  @override
  String toString() => 'BatchSize.$_label';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _Unbatched;

  @override
  int get hashCode => 0;
}
