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

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as dart_isolate;
import 'package:vm_service/vm_service.dart';
import 'dart:async';
import 'package:vm_service/vm_service_io.dart';
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

      final states = <dynamic>[];
      if (setup != null) {
        for (var i = 0; i < iterations; i++) {
          final state = setup();
          states.add(state is Future ? await state : state);
        }
      }

      // 3. Trigger GC and reset allocation accumulators for baseline
      final baseline = await service.getAllocationProfile(
        isolateId,
        gc: true,
        reset: true,
      );
      final baselineRss = ProcessInfo.currentRss;

      // 4. Run the benchmark function M times
      for (var i = 0; i < iterations; i++) {
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

      // 6. Calculate delta in accumulated bytes and instances
      int totalAllocatedBytes = 0;
      int totalAllocatedInstances = 0;

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

        if (diffBytes > 0) {
          totalAllocatedBytes += diffBytes;
        }
        if (diffInstances > 0) {
          totalAllocatedInstances += diffInstances;
        }
      }

      final allocatedBytesPerIteration = totalAllocatedBytes / iterations;
      final allocatedObjectsPerIteration = totalAllocatedInstances / iterations;
      final rssDeltaBytes = endRss - baselineRss;

      return MemoryResult(
        allocatedBytesPerIteration: allocatedBytesPerIteration,
        allocatedObjectsPerIteration: allocatedObjectsPerIteration,
        rssDeltaBytes: rssDeltaBytes,
      );
    } catch (e) {
      // Fall back to measuring only RSS delta
      try {
        final states = <dynamic>[];
        if (setup != null) {
          for (var i = 0; i < iterations; i++) {
            final state = setup();
            states.add(state is Future ? await state : state);
          }
        }
        final baselineRss = ProcessInfo.currentRss;
        for (var i = 0; i < iterations; i++) {
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
        return MemoryResult(
          allocatedBytesPerIteration: null,
          allocatedObjectsPerIteration: null,
          rssDeltaBytes: endRss - baselineRss,
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
