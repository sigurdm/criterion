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

/// Isolated Dart script executed via [dart_isolate.Isolate.spawnUri] in a
/// separate `IsolateGroup` so that WebSocket frames and JSON-RPC decoding do
/// not allocate objects on the benchmarked isolate group's heap.
const String _helperIsolateScript = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

void main(List<String> args, SendPort initReplyPort) async {
  final wsUri = args[0];
  final targetIsolateId = args[1];

  WebSocket? ws;
  final commandPort = ReceivePort();
  try {
    ws = await WebSocket.connect(wsUri);
    var nextRpcId = 1;
    final pending = <int, Completer<Map<String, dynamic>>>{};

    ws.listen(
      (data) {
        final decoded = jsonDecode(data as String) as Map<String, dynamic>;
        final id = decoded['id'];
        if (id is int) {
          final completer = pending.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(decoded);
          }
        }
      },
      onError: (Object error) {
        for (final c in pending.values) {
          if (!c.isCompleted) c.completeError(error);
        }
        pending.clear();
      },
      onDone: () {
        for (final c in pending.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('VM Service WebSocket closed'));
          }
        }
        pending.clear();
      },
    );

    // Bounded wait for a single `getAllocationProfile` reply. The `gc: true`
    // variant forces a full GC of the benchmarked isolate, which can take a
    // while on a large heap, so this is deliberately generous: it only exists
    // so that a wedged VM Service surfaces as an error instead of hanging the
    // benchmark run forever.
    const rpcTimeout = Duration(seconds: 30);

    Future<Map<String, dynamic>> callGetAllocationProfile({
      bool gc = false,
      bool reset = false,
    }) async {
      final id = nextRpcId++;
      final completer = Completer<Map<String, dynamic>>();
      pending[id] = completer;
      final params = <String, dynamic>{
        'isolateId': targetIsolateId,
        if (gc) 'gc': true,
        if (reset) 'reset': true,
      };
      ws!.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': 'getAllocationProfile',
          'params': params,
        }),
      );
      final response = await completer.future.timeout(
        rpcTimeout,
        onTimeout: () {
          pending.remove(id);
          throw TimeoutException(
            'getAllocationProfile did not answer within',
            rpcTimeout,
          );
        },
      );
      if (response.containsKey('error')) {
        throw Exception('VM Service error: ${response['error']}');
      }
      return response['result'] as Map<String, dynamic>;
    }

    // Warm up JSON-RPC + getAllocationProfile before signaling readiness.
    await callGetAllocationProfile();

    initReplyPort.send(commandPort.sendPort);

    var totalBytes = 0;
    var totalInstances = 0;
    final classMap = <String, List<dynamic>>{};
    var baselineMembers = <String, List<int>>{};
    var overheadMembers = <String, List<int>>{};

    await for (final message in commandPort) {
      if (message is! List) continue;
      final command = message[0] as String;
      final replyPort = message.length > 1 ? message[1] as SendPort? : null;

      if (command == 'baseline') {
        final baseline = await callGetAllocationProfile(gc: true, reset: true);
        baselineMembers = <String, List<int>>{};
        final members = baseline['members'] as List<dynamic>? ?? const [];
        for (final raw in members) {
          final m = raw as Map<String, dynamic>;
          final classRef = m['class'] as Map<String, dynamic>?;
          final classId = classRef?['id'] as String?;
          if (classId != null) {
            baselineMembers[classId] = [
              (m['accumulatedSize'] as int?) ?? 0,
              (m['instancesAccumulated'] as int?) ?? 0,
            ];
          }
        }
        replyPort?.send(true);
      } else if (command == 'calibrateEnd') {
        final endProfile = await callGetAllocationProfile();
        overheadMembers = <String, List<int>>{};
        final members = endProfile['members'] as List<dynamic>? ?? const [];
        for (final raw in members) {
          final m = raw as Map<String, dynamic>;
          final classRef = m['class'] as Map<String, dynamic>?;
          final classId = classRef?['id'] as String?;
          if (classId == null) continue;
          final endBytes = (m['accumulatedSize'] as int?) ?? 0;
          final endInstances = (m['instancesAccumulated'] as int?) ?? 0;
          final base = baselineMembers[classId];
          final baseBytes = base != null ? base[0] : 0;
          final baseInstances = base != null ? base[1] : 0;
          final diffB = endBytes - baseBytes;
          final diffI = endInstances - baseInstances;
          if (diffB > 0 || diffI > 0) {
            overheadMembers[classId] = [
              diffB > 0 ? diffB : 0,
              diffI > 0 ? diffI : 0,
            ];
          }
        }
        replyPort?.send(true);
      } else if (command == 'endBatch') {
        final endProfile = await callGetAllocationProfile();
        final members = endProfile['members'] as List<dynamic>? ?? const [];
        for (final raw in members) {
          final m = raw as Map<String, dynamic>;
          final classRef = m['class'] as Map<String, dynamic>?;
          final classId = classRef?['id'] as String?;
          if (classId == null) continue;

          final endBytes = (m['accumulatedSize'] as int?) ?? 0;
          final endInstances = (m['instancesAccumulated'] as int?) ?? 0;
          final base = baselineMembers[classId];
          final baseBytes = base != null ? base[0] : 0;
          final baseInstances = base != null ? base[1] : 0;
          final ovh = overheadMembers[classId];
          final ovhBytes = ovh != null ? ovh[0] : 0;
          final ovhInstances = ovh != null ? ovh[1] : 0;

          final diffBytes = (endBytes - baseBytes) - ovhBytes;
          final diffInstances = (endInstances - baseInstances) - ovhInstances;
          if (diffBytes > 0 || diffInstances > 0) {
            if (diffBytes > 0) totalBytes += diffBytes;
            if (diffInstances > 0) totalInstances += diffInstances;
            final className = (classRef?['name'] as String?) ?? 'Unknown';
            final libRef = classRef?['library'] as Map<String, dynamic>?;
            final libraryUri = (libRef?['uri'] as String?) ?? 'Unknown';
            final key = '$libraryUri::$className';
            final existing = classMap[key];
            if (existing != null) {
              existing[2] = (existing[2] as int) + (diffBytes > 0 ? diffBytes : 0);
              existing[3] =
                  (existing[3] as int) + (diffInstances > 0 ? diffInstances : 0);
            } else {
              classMap[key] = [
                className,
                libraryUri,
                diffBytes > 0 ? diffBytes : 0,
                diffInstances > 0 ? diffInstances : 0,
              ];
            }
          }
        }
        replyPort?.send(true);
      } else if (command == 'getTotals') {
        replyPort?.send([totalBytes, totalInstances, classMap.values.toList()]);
      } else if (command == 'dispose') {
        await ws.close();
        // Acknowledge only after the WebSocket is actually closed, so the
        // parent knows the VM Service connection is gone before it kills us.
        replyPort?.send(true);
        commandPort.close();
        return;
      }
    }
  } catch (e) {
    initReplyPort.send('ERROR: $e');
  } finally {
    try {
      await ws?.close();
    } catch (_) {}
    commandPort.close();
  }
}
''';

/// Maximum time to wait for the helper isolate to report readiness.
///
/// Startup covers spawning an isolate in a fresh isolate group, compiling the
/// helper script, opening a WebSocket to the VM Service and performing one
/// warm-up `getAllocationProfile`. On a cold, heavily loaded machine that can
/// take a few seconds, so the bound is deliberately generous: it exists only
/// to turn "the helper died and nobody noticed" into a prompt, diagnosable
/// failure instead of a benchmark run that hangs forever.
const Duration _helperStartupTimeout = Duration(seconds: 60);

/// Maximum time to wait for the helper isolate to answer a single command.
///
/// The slowest command is `baseline`, which forces a full GC of the
/// benchmarked isolate before reading the allocation profile; on a large heap
/// that is seconds, not milliseconds.
const Duration _helperCommandTimeout = Duration(seconds: 45);

/// Maximum time to wait for the helper isolate to acknowledge `dispose`.
///
/// Closing a WebSocket is quick; this only bounds the case where the helper is
/// already wedged or dead, in which case it is killed instead.
const Duration _helperDisposeTimeout = Duration(seconds: 10);

/// Awaits the helper isolate's reply to [command].
///
/// [helperDown] completes with a human readable reason when the helper isolate
/// has died; the wait is abandoned as soon as that happens.
///
/// Throws a [TimeoutException] if no reply arrives within
/// [_helperCommandTimeout], and a [StateError] if the helper died or closed the
/// response port before replying. Both are far better than reading
/// [StreamIterator.current] without checking [StreamIterator.moveNext]'s
/// result, which fails with an opaque `StateError` only at the point of use.
Future<Object?> _awaitHelperReply(
  StreamIterator<dynamic> responses,
  Future<String> helperDown,
  String command,
) async {
  final bool hasReply;
  try {
    hasReply = await Future.any([
      responses.moveNext(),
      helperDown.then<bool>(
        (reason) => throw StateError(
          'Memory helper isolate died while waiting for a reply to '
          '"$command": $reason.',
        ),
      ),
    ]).timeout(_helperCommandTimeout);
  } on TimeoutException {
    throw TimeoutException(
      'Memory helper isolate did not reply to "$command" within',
      _helperCommandTimeout,
    );
  }
  if (!hasReply) {
    throw StateError(
      'Memory helper isolate closed the response port without replying to '
      '"$command"; it most likely crashed.',
    );
  }
  return responses.current;
}

/// Helper to perform memory measurements using the VM Service.
final class MemoryMeasurer {
  /// Performs memory measurement for [fn] over [iterations] runs.
  ///
  /// Returns `null` if measurement fails.
  static Future<MemoryResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    FutureOr<void> Function(dynamic)? teardown,
    BatchSize? batchSize,
  }) async {
    dart_isolate.Isolate? helperIsolate;
    dart_isolate.ReceivePort? responsePort;
    StreamIterator<dynamic>? responseIterator;
    dart_isolate.SendPort? helperSendPort;

    // Lifetime monitoring for the helper isolate. `onExit`/`onError` are the
    // only way to notice that the helper died: the response ports are owned by
    // *this* isolate, so they never close on their own and a wait for a reply
    // that will never arrive would otherwise hang (or, at best, run into its
    // timeout). Completed with a human readable reason, never with an error,
    // so that nothing here can become an unhandled asynchronous error.
    final helperExitPort = dart_isolate.ReceivePort();
    final helperErrorPort = dart_isolate.ReceivePort();
    final helperDown = Completer<String>();
    helperExitPort.listen((_) {
      if (!helperDown.isCompleted) helperDown.complete('it exited');
    });
    helperErrorPort.listen((error) {
      if (!helperDown.isCompleted) helperDown.complete('it crashed: $error');
    });

    // Cap effective iterations to 500 and per-batch size to 100 so that a single
    // batch does not overflow NewSpace (~16 MB) and trigger a minor GC scavenge
    // before endBatch reads the ClassHeapStats counters.
    final effectiveIterations = iterations.clamp(1, 500);

    try {
      // 1. Enable VM Service web server
      final info = await developer.Service.controlWebServer(enable: true);
      final uri = info.serverUri;
      if (uri == null) {
        throw Exception('VM Service not available');
      }
      final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');

      // 2. Find target (current) isolate ID
      final targetIsolateId = developer.Service.getIsolateId(
        dart_isolate.Isolate.current,
      );
      if (targetIsolateId == null) {
        throw Exception('Isolate ID not found');
      }

      // 3. Spawn helper isolate in a separate IsolateGroup via spawnUri
      // (falls back to Isolate.spawn if spawnUri is unavailable, e.g. in AOT).
      var usedSeparateIsolateGroup = false;
      final initPort = dart_isolate.ReceivePort();
      final Object? initResult;
      try {
        final init = Completer<Object?>();
        initPort.listen((message) {
          if (!init.isCompleted) init.complete(message);
        });
        unawaited(
          helperDown.future.then((reason) {
            if (!init.isCompleted) {
              init.completeError(
                StateError(
                  'Memory helper isolate never signalled readiness: $reason.',
                ),
              );
            }
          }),
        );

        try {
          final dataUri = Uri.dataFromString(
            _helperIsolateScript,
            mimeType: 'application/dart',
          );
          helperIsolate = await dart_isolate.Isolate.spawnUri(
            dataUri,
            [wsUri.toString(), targetIsolateId],
            initPort.sendPort,
            onExit: helperExitPort.sendPort,
            onError: helperErrorPort.sendPort,
          );
          usedSeparateIsolateGroup = true;
        } catch (_) {
          helperIsolate = await dart_isolate.Isolate.spawn(
            _memoryHelperFallbackEntry,
            _HelperInit(
              wsUri: wsUri.toString(),
              targetIsolateId: targetIsolateId,
              replyPort: initPort.sendPort,
            ),
            onExit: helperExitPort.sendPort,
            onError: helperErrorPort.sendPort,
          );
        }

        try {
          initResult = await init.future.timeout(_helperStartupTimeout);
        } on TimeoutException {
          throw TimeoutException(
            'Memory helper isolate did not become ready within',
            _helperStartupTimeout,
          );
        }
      } finally {
        // Closing this on *every* path matters: if both spawn attempts throw,
        // a still-open ReceivePort keeps the event loop alive and the process
        // never exits.
        initPort.close();
      }
      if (initResult is! dart_isolate.SendPort) {
        throw Exception('Helper isolate failed to initialize: $initResult');
      }
      helperSendPort = initResult;
      responsePort = dart_isolate.ReceivePort();
      responseIterator = StreamIterator(responsePort);

      // 4. Perform a 0-iteration calibration round-trip to warm up SendPort/RPC
      // paths and record any fixed message-passing allocation overhead per batch.
      helperSendPort.send(['baseline', responsePort.sendPort]);
      await _awaitHelperReply(responseIterator, helperDown.future, 'baseline');
      helperSendPort.send(['calibrateEnd', responsePort.sendPort]);
      await _awaitHelperReply(
        responseIterator,
        helperDown.future,
        'calibrateEnd',
      );

      final mode =
          batchSize ??
          (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
      int rssDeltaSum = 0;

      var remaining = effectiveIterations;
      while (remaining > 0) {
        final rawBatch = mode.batchSizeFor(remaining);
        final batch = usedSeparateIsolateGroup && rawBatch > 100
            ? 100
            : rawBatch;
        final states = <dynamic>[];
        if (setup != null) {
          for (var i = 0; i < batch; i++) {
            final state = setup();
            states.add(state is Future ? await state : state);
          }
        }

        // Request helper isolate to reset baseline with GC
        helperSendPort.send(['baseline', responsePort.sendPort]);
        await _awaitHelperReply(
          responseIterator,
          helperDown.future,
          'baseline',
        );

        final baselineRss = ProcessInfo.currentRss;

        // Run benchmark function batch times in current isolate
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

        // Request helper isolate to record end batch allocation profile
        helperSendPort.send(['endBatch', responsePort.sendPort]);
        await _awaitHelperReply(
          responseIterator,
          helperDown.future,
          'endBatch',
        );

        if (teardown != null) {
          for (var i = 0; i < batch; i++) {
            final res = teardown(states[i]);
            if (res is Future) await res;
          }
        }

        remaining -= batch;
      }

      // Request totals and class allocations from helper isolate
      helperSendPort.send(['getTotals', responsePort.sendPort]);
      final rawTotals =
          (await _awaitHelperReply(
                responseIterator,
                helperDown.future,
                'getTotals',
              ))
              as List<dynamic>;
      final totalBytes = rawTotals[0] as int;
      final totalInstances = rawTotals[1] as int;
      final rawClassList = rawTotals[2] as List<dynamic>;

      final classAllocations = <ClassAllocation>[];
      for (final item in rawClassList) {
        final row = item as List<dynamic>;
        final className = row[0] as String;
        final libraryUri = row[1] as String;
        final cumBytes = row[2] as int;
        final cumInstances = row[3] as int;
        final perIterBytes = (cumBytes / effectiveIterations).round();
        final perIterInstances = (cumInstances / effectiveIterations).round();
        if (perIterBytes > 0 || perIterInstances > 0) {
          classAllocations.add(
            ClassAllocation(
              className: className,
              libraryUri: libraryUri,
              bytes: perIterBytes,
              instances: perIterInstances,
            ),
          );
        }
      }

      await responseIterator.cancel();
      responsePort.close();
      responsePort = null;
      responseIterator = null;

      final allocatedBytesPerIteration = totalBytes / effectiveIterations;
      final allocatedObjectsPerIteration = totalInstances / effectiveIterations;

      return MemoryResult(
        allocatedBytesPerIteration: allocatedBytesPerIteration,
        allocatedObjectsPerIteration: allocatedObjectsPerIteration,
        rssDeltaBytes: rssDeltaSum,
        classAllocations: classAllocations,
      );
    } catch (e) {
      if (responseIterator != null) {
        await responseIterator.cancel();
      }
      responsePort?.close();
      // Fall back to measuring only RSS delta
      try {
        final mode =
            batchSize ??
            (setup != null ? BatchSize.smallInput : BatchSize.unbatched);
        int rssDeltaSum = 0;
        var remaining = effectiveIterations;
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

          if (teardown != null) {
            for (var i = 0; i < batch; i++) {
              final res = teardown(states[i]);
              if (res is Future) await res;
            }
          }

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
      if (helperSendPort != null && !helperDown.isCompleted) {
        final disposePort = dart_isolate.ReceivePort();
        try {
          helperSendPort.send(['dispose', disposePort.sendPort]);
          await Future.any([
            disposePort.first,
            helperDown.future,
          ]).timeout(_helperDisposeTimeout);
        } catch (_) {
          // Helper is already gone or wedged; kill below will clean it up.
        } finally {
          disposePort.close();
        }
      }
      helperIsolate?.kill(priority: dart_isolate.Isolate.immediate);
      helperExitPort.close();
      helperErrorPort.close();
    }
  }
}

final class _HelperInit {
  final String wsUri;
  final String targetIsolateId;
  final dart_isolate.SendPort replyPort;

  _HelperInit({
    required this.wsUri,
    required this.targetIsolateId,
    required this.replyPort,
  });
}

void _memoryHelperFallbackEntry(_HelperInit init) async {
  const rpcTimeout = Duration(seconds: 30);
  final commandPort = dart_isolate.ReceivePort();
  VmService? service;
  try {
    final s = service = await vmServiceConnectUri(
      init.wsUri,
    ).timeout(rpcTimeout);
    final targetIsolateId = init.targetIsolateId;
    await s.getAllocationProfile(targetIsolateId).timeout(rpcTimeout);
    init.replyPort.send(commandPort.sendPort);

    int totalBytes = 0;
    int totalInstances = 0;
    final classMap = <String, List<dynamic>>{};
    Map<String, ClassHeapStats> baselineMembers = {};
    final overheadMembers = <String, List<int>>{};

    await for (final msg in commandPort) {
      if (msg is! List) continue;
      final command = msg[0] as String;
      final replyPort = msg.length > 1
          ? msg[1] as dart_isolate.SendPort?
          : null;

      if (command == 'baseline') {
        final baseline = await s
            .getAllocationProfile(targetIsolateId, gc: true, reset: true)
            .timeout(rpcTimeout);
        baselineMembers = {
          for (var member in baseline.members ?? <ClassHeapStats>[])
            if (member.classRef?.id != null) member.classRef!.id!: member,
        };
        replyPort?.send(true);
      } else if (command == 'calibrateEnd') {
        final endProfile = await s
            .getAllocationProfile(targetIsolateId)
            .timeout(rpcTimeout);
        overheadMembers.clear();
        for (final endMember in endProfile.members ?? <ClassHeapStats>[]) {
          final classId = endMember.classRef?.id;
          if (classId == null) continue;
          final baselineMember = baselineMembers[classId];
          final endBytes = endMember.accumulatedSize ?? 0;
          final endInstances = endMember.instancesAccumulated ?? 0;
          final baselineBytes = baselineMember?.accumulatedSize ?? 0;
          final baselineInstances = baselineMember?.instancesAccumulated ?? 0;
          final diffB = endBytes - baselineBytes;
          final diffI = endInstances - baselineInstances;
          if (diffB > 0 || diffI > 0) {
            overheadMembers[classId] = [
              diffB > 0 ? diffB : 0,
              diffI > 0 ? diffI : 0,
            ];
          }
        }
        replyPort?.send(true);
      } else if (command == 'endBatch') {
        final endProfile = await s
            .getAllocationProfile(targetIsolateId)
            .timeout(rpcTimeout);
        for (final endMember in endProfile.members ?? <ClassHeapStats>[]) {
          final classId = endMember.classRef?.id;
          if (classId == null) continue;
          final baselineMember = baselineMembers[classId];
          final ovh = overheadMembers[classId];
          final ovhBytes = ovh != null ? ovh[0] : 0;
          final ovhInstances = ovh != null ? ovh[1] : 0;

          final endBytes = endMember.accumulatedSize ?? 0;
          final endInstances = endMember.instancesAccumulated ?? 0;
          final baselineBytes = baselineMember?.accumulatedSize ?? 0;
          final baselineInstances = baselineMember?.instancesAccumulated ?? 0;

          final diffBytes = (endBytes - baselineBytes) - ovhBytes;
          final diffInstances =
              (endInstances - baselineInstances) - ovhInstances;

          if (diffBytes > 0 || diffInstances > 0) {
            if (diffBytes > 0) totalBytes += diffBytes;
            if (diffInstances > 0) totalInstances += diffInstances;
            final className = endMember.classRef?.name ?? 'Unknown';
            final libraryUri = endMember.classRef?.library?.uri ?? 'Unknown';
            final key = '$libraryUri::$className';
            final existing = classMap[key];
            if (existing != null) {
              existing[2] =
                  (existing[2] as int) + (diffBytes > 0 ? diffBytes : 0);
              existing[3] =
                  (existing[3] as int) +
                  (diffInstances > 0 ? diffInstances : 0);
            } else {
              classMap[key] = [
                className,
                libraryUri,
                diffBytes > 0 ? diffBytes : 0,
                diffInstances > 0 ? diffInstances : 0,
              ];
            }
          }
        }
        replyPort?.send(true);
      } else if (command == 'getTotals') {
        replyPort?.send([totalBytes, totalInstances, classMap.values.toList()]);
      } else if (command == 'dispose') {
        service = null;
        await s.dispose().timeout(_helperDisposeTimeout);
        replyPort?.send(true);
        commandPort.close();
        return;
      }
    }
  } catch (e) {
    init.replyPort.send('ERROR: $e');
    commandPort.close();
  } finally {
    if (service != null) {
      try {
        await service.dispose().timeout(_helperDisposeTimeout);
      } catch (_) {}
    }
  }
}
