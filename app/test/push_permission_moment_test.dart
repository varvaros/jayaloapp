// CUÁNDO se pide el permiso de notificaciones (PO 2026-08-20): nunca durante
// el intro ni el alta — el diálogo del sistema tapaba los recuadros de rol de
// la primera apertura, que ahora es la única que hay.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/push/push_permission.dart';

class _FakeRole extends ChangeNotifier {
  RoleState value = RoleState.unknown;
  void emit(RoleState v) {
    value = v;
    notifyListeners();
  }
}

void main() {
  group('shouldAskPushPermission', () {
    test('NO con el rol sin resolver: es el gate, no hay pantalla propia', () {
      expect(shouldAskPushPermission(RoleState.unknown), isFalse);
    });

    test('NO mientras falta el alta: ahí vive el intro y el formulario', () {
      expect(shouldAskPushPermission(RoleState.needsOnboarding), isFalse);
    });

    test('SÍ con rol de cliente resuelto', () {
      expect(shouldAskPushPermission(RoleState.consumer), isTrue);
    });

    test('SÍ con rol de proveedor resuelto', () {
      expect(shouldAskPushPermission(RoleState.provider), isTrue);
    });
  });

  group('wirePushPermissionPrompt', () {
    test('no pide nada mientras el rol no se resuelve', () async {
      final role = _FakeRole();
      var asks = 0;
      wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => asks++,
      );

      role.emit(RoleState.needsOnboarding); // usuario nuevo en el alta
      expect(asks, 0);
    });

    test('pide en cuanto el rol queda resuelto', () async {
      final role = _FakeRole();
      var asks = 0;
      wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => asks++,
      );

      role.emit(RoleState.needsOnboarding);
      role.emit(RoleState.consumer);
      expect(asks, 1);
    });

    test('una sola vez por proceso, aunque el rol vuelva a notificar', () async {
      final role = _FakeRole();
      var asks = 0;
      wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => asks++,
      );

      role.emit(RoleState.consumer);
      role.emit(RoleState.unknown); // cerrar sesión
      role.emit(RoleState.provider); // entra otra cuenta
      expect(asks, 1);
    });

    test('arranque en caliente: el rol ya resuelto al cablear también pide', () {
      final role = _FakeRole()..value = RoleState.provider;
      var asks = 0;
      wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => asks++,
      );

      expect(asks, 1);
    });

    test('un fallo de `ask` no propaga: el push es accesorio', () async {
      final role = _FakeRole();
      wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => throw Exception('MIUI se comió el diálogo'),
      );

      role.emit(RoleState.consumer);
      // Sin `unhandled exception` que tumbe el test: si la hubiera, el
      // arranque de la app se llevaría el mismo golpe.
      await Future<void>.delayed(Duration.zero);
    });

    test('el desenganche corta futuras peticiones', () {
      final role = _FakeRole();
      var asks = 0;
      final detach = wirePushPermissionPrompt(
        source: role,
        role: () => role.value,
        ask: () async => asks++,
      );

      detach();
      role.emit(RoleState.consumer);
      expect(asks, 0);
    });
  });
}
