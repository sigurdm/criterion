import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  test('async benchmark measures elapsed time', () async {
    final c = Criterion(config: const CriterionConfig(useKbssd: false));
    // We need to cast it or use benchAsync if we implement it.
    // For now, let's try to pass it to bench and see what happens.
    c.bench(
      'async_delay',
      () async {
        await Future.delayed(const Duration(milliseconds: 50));
      },
      samples: 5,
      warmupDuration: const Duration(milliseconds: 100),
    );

    final results = await c.run();
    final result = results.first;

    print('Mean time: ${result.primary.mean} ns');
    // 50ms is 50,000,000 ns
    expect(result.primary.mean, greaterThanOrEqualTo(40 * 1000000));
  });
}
