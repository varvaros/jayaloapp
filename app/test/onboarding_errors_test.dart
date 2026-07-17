import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/onboarding_errors.dart';

void main() {
  test('whatsapp_taken', () => expect(onboardingErrorCopy(Exception('whatsapp_taken')),
      contains('WhatsApp ya está registrado')));
  test('phone_taken', () => expect(onboardingErrorCopy(Exception('phone_taken')),
      contains('teléfono ya está registrado')));
  test('rnc_taken', () => expect(onboardingErrorCopy(Exception('rnc_taken')), contains('RNC')));
  test('23505 con phone (upsert directo del consumidor)', () {
    expect(
        onboardingErrorCopy(Exception(
            'duplicate key value violates unique constraint "profiles_phone_key", code 23505')),
        contains('teléfono ya está registrado'));
  });
  test('not_authenticated', () => expect(onboardingErrorCopy(Exception('not_authenticated')),
      contains('sesión')));
  test('fallback genérico', () => expect(onboardingErrorCopy(Exception('boom')),
      contains('No pudimos completar')));
}
