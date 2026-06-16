import 'package:criterion/criterion.dart';

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

void main() async {
  await criterion('Fibonacci', (c) {
    c.bench('fib(10)', () {
      fib(10);
    });

    c.bench('fib(20)', () {
      fib(20);
    });
  });

  await criterion('String Concatenation', (c) {
    c.group('methods', () {
      c.bench('operator +', () {
        var s = '';
        for (var i = 0; i < 100; i++) {
          s += 'a';
        }
        if (s.isEmpty) throw StateError('must not be empty');
      });

      c.bench('StringBuffer', () {
        final sb = StringBuffer();
        for (var i = 0; i < 100; i++) {
          sb.write('a');
        }
        final s = sb.toString();
        if (s.isEmpty) throw StateError('must not be empty');
      });
    });
  });

  await criterion('FFI Specialization Mock', (c) {
    c.bench(
      'mock_ffi_call',
      () {
        // Mock FFI call doing some work
        var sum = 0;
        for (var i = 0; i < 50; i++) {
          sum += i;
        }
        if (sum == 0) throw StateError('must not be 0');
      },
      noOp: () {
        // Mock FFI call boundary overhead (no-op)
      },
    );
  });
}
