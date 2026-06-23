import 'dart:async';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Setup/Teardown', () {
    test('State isolation and passing', () async {
      final statesCreated = <int>[];
      final statesReceived = <int>[];
      var counter = 0;

      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );
      c.bench<int>(
        'setup_bench',
        (int state) {
          statesReceived.add(state);
        },
        setup: () {
          counter++;
          statesCreated.add(counter);
          return counter;
        },
        samples: 5,
        warmupDuration: const Duration(milliseconds: 10),
      );

      await c.run();

      // Ensure setup was called and states were passed
      expect(statesCreated, isNotEmpty);
      expect(statesReceived, isNotEmpty);
      expect(statesReceived.length, statesCreated.length);

      // Check that each iteration got a unique state in increasing order
      for (var i = 0; i < statesReceived.length; i++) {
        expect(statesReceived[i], statesCreated[i]);
      }

      // Check that states are unique (isolation)
      expect(statesReceived.toSet().length, statesReceived.length);
    });

    test('Async setup and async fn', () async {
      final statesCreated = <int>[];
      final statesReceived = <int>[];
      var counter = 0;

      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );
      c.bench<int>(
        'async_setup_bench',
        (int state) async {
          await Future.delayed(const Duration(milliseconds: 1));
          statesReceived.add(state);
        },
        setup: () async {
          await Future.delayed(const Duration(milliseconds: 1));
          counter++;
          statesCreated.add(counter);
          return counter;
        },
        samples: 5,
        warmupDuration: const Duration(milliseconds: 10),
      );

      await c.run();

      expect(statesCreated, isNotEmpty);
      expect(statesReceived, isNotEmpty);
      expect(statesReceived.length, statesCreated.length);
      for (var i = 0; i < statesReceived.length; i++) {
        expect(statesReceived[i], statesCreated[i]);
      }
    });
  });
}
