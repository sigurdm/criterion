import 'dart:ffi';
import 'package:criterion/criterion.dart';
import 'package:ffi/ffi.dart';

// Pure Dart implementation of absolute value
int labsDart(int n) => n < 0 ? -n : n;

// Non-leaf FFI call to C labs
@Native<Int64 Function(Int64)>(symbol: 'labs')
external int labsNonLeaf(int j);

// Leaf FFI call to C labs (highly optimized transition)
@Native<Int64 Function(Int64)>(symbol: 'labs', isLeaf: true)
external int labsLeaf(int j);

// FFI call to C strlen
@Native<UintPtr Function(Pointer<Char>)>(symbol: 'strlen', isLeaf: true)
external int strlenLeaf(Pointer<Char> s);

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

  await criterion('FFI Transition Overhead', (c) {
    c.bench('labs (Dart)', () {
      labsDart(-100);
    });

    c.bench('labs (FFI Leaf)', () {
      labsLeaf(-100);
    });

    c.bench('labs (FFI Non-Leaf)', () {
      labsNonLeaf(-100);
    });
  });

  // Allocate native memory outside the benchmark loop to avoid measuring allocation cost.
  final str1000 = ('a' * 1000).toNativeUtf8();
  final strEmpty = ''.toNativeUtf8();

  try {
    await criterion('FFI Boundary Calibration', (c) {
      c.bench(
        'strlen (1000 chars)',
        () {
          // Main function: Leaf FFI call with 1000 iterations inside strlen
          strlenLeaf(str1000.cast<Char>());
        },
        noOp: () {
          // Overhead function: Leaf FFI call with 0 iterations (returns immediately)
          strlenLeaf(strEmpty.cast<Char>());
        },
      );
    });
  } finally {
    calloc.free(str1000);
    calloc.free(strEmpty);
  }
}
