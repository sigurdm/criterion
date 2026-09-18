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

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as dart_isolate;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../batch_size.dart';
import '../blackhole.dart';
import '../result.dart';

/// Helper to collect CPU profiles using the VM Service.
final class CpuProfiler {
  /// Collects CPU samples during execution of [fn].
  static Future<CpuProfileResult?> collect({
    required Function fn,
    required int iterations,
    Function? setup,
    String? exportPath,
    BatchSize? batchSize,
  }) async {
    VmService? service;
    try {
      final info = await developer.Service.controlWebServer(enable: true);
      final uri = info.serverUri;
      if (uri == null) return null;
      final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
      service = await vmServiceConnectUri(wsUri.toString());

      final isolateId = developer.Service.getIsolateId(
        dart_isolate.Isolate.current,
      );
      if (isolateId == null) return null;

      // Enable profiler if disabled
      try {
        final flagList = await service.getFlagList();
        for (final flag in flagList.flags ?? <Flag>[]) {
          if (flag.name == 'profiler' && flag.valueAsString == 'false') {
            await service.setFlag('profiler', 'true');
          }
        }
      } catch (_) {
        // Ignore
      }

      final mode =
          batchSize ??
          (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
      final intervals = <(int, int)>[];
      final int startTime;
      final int endTime;

      if (setup != null && iterations <= mode.batchSizeFor(iterations)) {
        final batch = iterations;
        final states = <dynamic>[];
        for (var i = 0; i < batch; i++) {
          final state = setup();
          states.add(state is Future ? await state : state);
        }
        startTime = (await service.getVMTimelineMicros()).timestamp!;
        for (var i = 0; i < batch; i++) {
          final r = fn(states[i]);
          final res = r is Future ? await r : r;
          Blackhole.sink = res;
        }
        endTime = (await service.getVMTimelineMicros()).timestamp!;
      } else {
        startTime = (await service.getVMTimelineMicros()).timestamp!;
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

          if (setup != null) {
            final batchStart = developer.Timeline.now;
            for (var i = 0; i < batch; i++) {
              final r = fn(states[i]);
              final res = r is Future ? await r : r;
              Blackhole.sink = res;
            }
            final batchEnd = developer.Timeline.now;
            intervals.add((batchStart, batchEnd));
          } else {
            for (var i = 0; i < batch; i++) {
              final r = fn();
              final res = r is Future ? await r : r;
              Blackhole.sink = res;
            }
          }
          remaining -= batch;
        }
        endTime = (await service.getVMTimelineMicros()).timestamp!;
      }

      final timeSpan = endTime - startTime;
      final cpuSamples = await service.getCpuSamples(
        isolateId,
        startTime,
        timeSpan < 0 ? 0 : timeSpan,
      );

      if (intervals.isNotEmpty && cpuSamples.samples != null) {
        final filteredSamples = cpuSamples.samples!.where((sample) {
          final ts = sample.timestamp;
          if (ts == null) return false;
          for (final interval in intervals) {
            if (ts >= interval.$1 && ts <= interval.$2) {
              return true;
            }
          }
          return false;
        }).toList();

        for (final f in cpuSamples.functions ?? <ProfileFunction>[]) {
          f.exclusiveTicks = 0;
          f.inclusiveTicks = 0;
        }

        final numFunctions = cpuSamples.functions?.length ?? 0;
        for (final sample in filteredSamples) {
          final stack = sample.stack;
          if (stack != null && stack.isNotEmpty) {
            final top = stack.first;
            if (top >= 0 && top < numFunctions) {
              final f = cpuSamples.functions![top];
              f.exclusiveTicks = (f.exclusiveTicks ?? 0) + 1;
            }
            for (final idx in stack.toSet()) {
              if (idx >= 0 && idx < numFunctions) {
                final f = cpuSamples.functions![idx];
                f.inclusiveTicks = (f.inclusiveTicks ?? 0) + 1;
              }
            }
          }
        }

        cpuSamples.samples = filteredSamples;
        cpuSamples.sampleCount = filteredSamples.length;
      }

      if (exportPath != null) {
        try {
          final file = File(exportPath);
          if (!file.parent.existsSync()) {
            file.parent.createSync(recursive: true);
          }
          file.writeAsStringSync(jsonEncode(cpuSamples.toJson()));
        } catch (e) {
          stderr.writeln(
            'Warning: Failed to export CPU profile to $exportPath: $e',
          );
        }
      }

      final functions = <CpuProfileFunction>[];
      for (final f in cpuSamples.functions ?? <ProfileFunction>[]) {
        if ((f.inclusiveTicks ?? 0) > 0 || (f.exclusiveTicks ?? 0) > 0) {
          String funcName = 'Unknown';
          final func = f.function;
          if (func is FuncRef) {
            funcName = func.name ?? 'Unknown';
          } else if (func is Map) {
            final parsed = FuncRef.parse(func.cast<String, dynamic>());
            funcName = parsed?.name ?? 'Unknown';
          } else if (func != null) {
            funcName = func.toString();
          }

          functions.add(
            CpuProfileFunction(
              name: funcName,
              resolvedUrl: f.resolvedUrl ?? 'Unknown',
              inclusiveTicks: f.inclusiveTicks ?? 0,
              exclusiveTicks: f.exclusiveTicks ?? 0,
            ),
          );
        }
      }

      return CpuProfileResult(
        functions: functions,
        sampleCount: cpuSamples.sampleCount ?? 0,
        samplePeriod: cpuSamples.samplePeriod ?? 0,
      );
    } catch (e) {
      return null;
    } finally {
      if (service != null) {
        await service.dispose();
      }
    }
  }
}
