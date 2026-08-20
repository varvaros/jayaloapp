import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  test('sin elección → se queda en ChooseRoleScreen', () {
    expect(
        introRoleRedirect(role: RoleState.needsOnboarding, choice: null),
        isNull);
  });

  test('eligió cliente → /onboarding/consumer', () {
    expect(
        introRoleRedirect(
            role: RoleState.needsOnboarding, choice: IntroRole.consumer),
        '/onboarding/consumer');
  });

  test('eligió proveedor → /onboarding/provider', () {
    expect(
        introRoleRedirect(
            role: RoleState.needsOnboarding, choice: IntroRole.provider),
        '/onboarding/provider');
  });

  // Caso borde obligatorio del brief: eligió "Vendo algo" en el intro pero su
  // cuenta de Google ya existe como cliente. El rol real manda; meterlo en el
  // alta de proveedor sería un error.
  test('rol real ya resuelto con elección contraria → null (rol real gana)',
      () {
    expect(
        introRoleRedirect(
            role: RoleState.consumer, choice: IntroRole.provider),
        isNull);
  });

  test('rol real ya resuelto como proveedor, eligió cliente → null', () {
    expect(
        introRoleRedirect(
            role: RoleState.provider, choice: IntroRole.consumer),
        isNull);
  });

  test('rol desconocido (gate aún no resolvió) → null', () {
    expect(
        introRoleRedirect(role: RoleState.unknown, choice: IntroRole.consumer),
        isNull);
  });

  // Ruling A6: predicado puro que decide cuándo hay que borrar la elección
  // guardada aunque nunca pase por /onboarding (cuenta ya existente).
  group('introChoiceShouldClear (Ruling A6)', () {
    test('consumer resuelto → true', () {
      expect(introChoiceShouldClear(RoleState.consumer), isTrue);
    });
    test('provider resuelto → true', () {
      expect(introChoiceShouldClear(RoleState.provider), isTrue);
    });
    test('needsOnboarding → false (la consume /onboarding, no aquí)', () {
      expect(introChoiceShouldClear(RoleState.needsOnboarding), isFalse);
    });
    test('unknown → false', () {
      expect(introChoiceShouldClear(RoleState.unknown), isFalse);
    });
  });
}
