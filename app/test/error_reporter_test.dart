import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/error_reporter.dart';

void main() {
  test('shouldSend deduplica dentro de 60s', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    expect(shouldSend('E|boom', t0), isTrue);
    expect(shouldSend('E|boom', t0.add(const Duration(seconds: 30))), isFalse);
    expect(shouldSend('E|boom', t0.add(const Duration(seconds: 61))), isTrue);
  });
}
