import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';

void main() {
  test('provider CON negocio → provider', () {
    expect(roleFrom(accountType: 'provider', hasBusiness: true), RoleState.provider);
  });

  // El caso real hallado en el E2E (mentekruel@gmail.com): account_type
  // 'provider' pero 0 negocios y 0 wallet. Mandarlo a /provider lo deja
  // atrapado en una bandeja vacía sin poder ofertar (spec §4).
  test('provider SIN negocio → needsOnboarding (proveedor a medias)', () {
    expect(roleFrom(accountType: 'provider', hasBusiness: false),
        RoleState.needsOnboarding);
  });

  test('consumer → consumer (no necesita negocio)', () {
    expect(roleFrom(accountType: 'consumer', hasBusiness: false), RoleState.consumer);
  });

  test('account_type NULL → needsOnboarding', () {
    expect(roleFrom(accountType: null, hasBusiness: false), RoleState.needsOnboarding);
  });

  test('account_type desconocido → needsOnboarding', () {
    expect(roleFrom(accountType: 'otro', hasBusiness: true), RoleState.needsOnboarding);
  });
}
