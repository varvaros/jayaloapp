import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';

void main() {
  test('sin sesión → /login', () {
    expect(redirectTarget(loggedIn: false, role: RoleState.unknown, location: '/client'),
        '/login');
  });
  test('sin sesión en /login se queda', () {
    expect(
        redirectTarget(loggedIn: false, role: RoleState.unknown, location: '/login'), isNull);
  });
  test('login con sesión → /gate', () {
    expect(
        redirectTarget(loggedIn: true, role: RoleState.consumer, location: '/login'), '/gate');
  });
  test('rol desconocido fuera de /gate → /gate', () {
    expect(
        redirectTarget(loggedIn: true, role: RoleState.unknown, location: '/client'), '/gate');
  });
  test('needsOnboarding NO alcanza el shell', () {
    expect(
        redirectTarget(loggedIn: true, role: RoleState.needsOnboarding, location: '/provider'),
        '/onboarding');
  });
  test('needsOnboarding puede estar en onboarding', () {
    expect(
        redirectTarget(
            loggedIn: true, role: RoleState.needsOnboarding, location: '/onboarding/consumer'),
        isNull);
  });

  // Bug hallado en el device (2026-07-17): el gate resolvía needsOnboarding y
  // devolvía null estando en /gate → el usuario quedaba ATRAPADO en el spinner
  // para siempre. El gate solo retiene mientras el rol es unknown.
  test('needsOnboarding en /gate SALE al selector (no se queda en el spinner)', () {
    expect(redirectTarget(loggedIn: true, role: RoleState.needsOnboarding, location: '/gate'),
        '/onboarding');
  });
  test('consumer no entra a onboarding → /client', () {
    expect(redirectTarget(loggedIn: true, role: RoleState.consumer, location: '/onboarding'),
        '/client');
  });
  test('provider saliendo del gate → /provider', () {
    expect(redirectTarget(loggedIn: true, role: RoleState.provider, location: '/gate'),
        '/provider');
  });
  test('provider puede navegar el shell libremente', () {
    expect(
        redirectTarget(loggedIn: true, role: RoleState.provider, location: '/client'), isNull);
  });
}
