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

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as dart_isolate;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../batch_size.dart';
import '../result.dart';

/// Helper to perform memory measurements using the VM Service.
final class MemoryMeasurer {
  /// Performs memory measurement for [fn] over [iterations] runs.
  ///
  /// Returns `null` if measurement fails.
  static Future<MemoryResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    BatchSize? batchSize,
  }) async {
    VmService? service;
    try {
      // 1. Enable and connect to VM Service
      final info = await developer.Service.controlWebServer(enable: true);
      final uri = info.serverUri;
      if (uri == null) {
        throw Exception('VM Service not available');
      }
      final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
      service = await vmServiceConnectUri(wsUri.toString());

      // 2. Find current isolate ID
      final isolateId = developer.Service.getIsolateId(
        dart_isolate.Isolate.current,
      );
      if (isolateId == null) {
        throw Exception('Isolate ID not found');
      }

      final mode =
          batchSize ??
          (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
      int totalAllocatedBytes = 0;
      int totalAllocatedInstances = 0;
      final classAllocationsMap = <String, ClassAllocation>{};
      int rssDeltaSum = 0;

      var remaining = iterations;
      while (remaining > 0) {
        final batch = mode.batchSizeFor(remaining);
        final states = <dynamic>[];
        if (setup != null) {
          for (var i = 0; i < batch; i++) {
            final state = setup();
            states.add(state is Future ? await state : state);
          }
        }

        // 3. Trigger GC and reset allocation accumulators for baseline BEFORE running fn
        final baseline = await service.getAllocationProfile(
          isolateId,
          gc: true,
          reset: true,
        );
        final baselineRss = ProcessInfo.currentRss;

        // 4. Run the benchmark function batch times
        for (var i = 0; i < batch; i++) {
          if (setup != null) {
            final r = fn(states[i]);
            if (r is Future) {
              await r;
            }
          } else {
            final r = fn();
            if (r is Future) {
              await r;
            }
          }
        }

        // 5. Record end RSS and query end allocation profile
        final endRss = ProcessInfo.currentRss;
        final endProfile = await service.getAllocationProfile(isolateId);

        rssDeltaSum += endRss - baselineRss;

        // 6. Calculate delta in accumulated bytes and instances
        final baselineMembers = {
          for (var member in baseline.members ?? <ClassHeapStats>[])
            member.classRef!.id: member,
        };

        for (final endMember in endProfile.members ?? <ClassHeapStats>[]) {
          final classId = endMember.classRef!.id;
          final baselineMember = baselineMembers[classId];

          final endBytes = endMember.accumulatedSize ?? 0;
          final endInstances = endMember.instancesAccumulated ?? 0;

          final baselineBytes = baselineMember?.accumulatedSize ?? 0;
          final baselineInstances = baselineMember?.instancesAccumulated ?? 0;

          final diffBytes = endBytes - baselineBytes;
          final diffInstances = endInstances - baselineInstances;

          if (diffBytes > 0 || diffInstances > 0) {
            if (diffBytes > 0) {
              totalAllocatedBytes += diffBytes;
            }
            if (diffInstances > 0) {
              totalAllocatedInstances += diffInstances;
            }
            final className = endMember.classRef!.name ?? 'Unknown';
            final libraryUri = endMember.classRef!.library?.uri ?? 'Unknown';
            final key = '$libraryUri::$className';
            final existing = classAllocationsMap[key];
            if (existing != null) {
              classAllocationsMap[key] = ClassAllocation(
                className: existing.className,
                libraryUri: existing.libraryUri,
                bytes: existing.bytes + (diffBytes > 0 ? diffBytes : 0),
                instances:
                    existing.instances +
                    (diffInstances > 0 ? diffInstances : 0),
              );
            } else {
              classAllocationsMap[key] = ClassAllocation(
                className: className,
                libraryUri: libraryUri,
                bytes: diffBytes > 0 ? diffBytes : 0,
                instances: diffInstances > 0 ? diffInstances : 0,
              );
            }
          }
        }

        remaining -= batch;
      }

      final allocatedBytesPerIteration = totalAllocatedBytes / iterations;
      final allocatedObjectsPerIteration = totalAllocatedInstances / iterations;

      return MemoryResult(
        allocatedBytesPerIteration: allocatedBytesPerIteration,
        allocatedObjectsPerIteration: allocatedObjectsPerIteration,
        rssDeltaBytes: rssDeltaSum,
        classAllocations: classAllocationsMap.values.toList(),
      );
    } catch (e) {
      // Fall back to measuring only RSS delta
      try {
        final mode =
            batchSize ??
            (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
        int rssDeltaSum = 0;
        var remaining = iterations;
        while (remaining > 0) {
          final batch = mode.batchSizeFor(remaining);
          final states = <dynamic>[];
          if (setup != null) {
            for (var i = 0; i < batch; i++) {
              final state = setup();
              states.add(state is Future ? await state : state);
            }
          }
          final baselineRss = ProcessInfo.currentRss;
          for (var i = 0; i < batch; i++) {
            if (setup != null) {
              final r = fn(states[i]);
              if (r is Future) {
                await r;
              }
            } else {
              final r = fn();
              if (r is Future) {
                await r;
              }
            }
          }
          final endRss = ProcessInfo.currentRss;
          rssDeltaSum += endRss - baselineRss;
          remaining -= batch;
        }
        return MemoryResult(
          allocatedBytesPerIteration: null,
          allocatedObjectsPerIteration: null,
          rssDeltaBytes: rssDeltaSum,
        );
      } catch (_) {
        return null;
      }
    } finally {
      if (service != null) {
        await service.dispose();
      }
    }
  }
}
