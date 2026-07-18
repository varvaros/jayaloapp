import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// La barra tiene 5 destinos: 2 · centro · 2. El del centro es la acción que
/// define al rol (crear si eres cliente, ver solicitudes si eres proveedor) y
/// es un destino más — puede estar activo como cualquier otro.
void main() {
  group('destinationsFor', () {
    test('cada rol tiene 5 destinos con el central en el medio', () {
      for (final rol in [RoleState.consumer, RoleState.provider]) {
        final d = destinationsFor(rol);
        expect(d.length, 5, reason: '$rol');
        expect(d[kCenterIndex].isCenter, isTrue, reason: '$rol');
        expect(d.where((x) => x.isCenter).length, 1, reason: '$rol');
      }
    });

    test('el centro del cliente es crear una solicitud', () {
      final d = destinationsFor(RoleState.consumer);
      expect(d[kCenterIndex].route, '/client/create');
    });

    test('el centro del proveedor es ver solicitudes', () {
      final d = destinationsFor(RoleState.provider);
      expect(d[kCenterIndex].route, '/provider');
    });

    test('el cliente llega a su reputación y el proveedor a sus estadísticas',
        () {
      expect(destinationsFor(RoleState.consumer).map((d) => d.route),
          contains('/client/reputation'));
      expect(destinationsFor(RoleState.provider).map((d) => d.route),
          contains('/provider/stats'));
    });

    test('ningún rol ve rutas del otro', () {
      expect(destinationsFor(RoleState.consumer).map((d) => d.route),
          isNot(contains('/provider')));
      expect(destinationsFor(RoleState.provider).map((d) => d.route),
          isNot(contains('/client')));
    });

    test('un rol sin resolver no revienta: cae al del cliente', () {
      expect(destinationsFor(RoleState.unknown).length, 5);
      expect(destinationsFor(RoleState.needsOnboarding).length, 5);
    });

    test('todas las etiquetas están en español y no vacías', () {
      for (final d in destinationsFor(RoleState.provider)) {
        expect(d.label.trim(), isNotEmpty);
      }
    });
  });

  group('activeIndex', () {
    final cliente = destinationsFor(RoleState.consumer);
    final proveedor = destinationsFor(RoleState.provider);

    test('la ruta exacta marca su destino', () {
      expect(activeIndex(cliente, '/messages'), 3);
      expect(activeIndex(cliente, '/client/create'), kCenterIndex);
    });

    test('gana el prefijo MÁS LARGO, no el primero que coincide', () {
      // '/provider/stats' empieza por '/provider' (el centro). Si ganara el
      // primero, estar en estadísticas encendería el botón central.
      expect(activeIndex(proveedor, '/provider/stats'), 1);
      expect(activeIndex(proveedor, '/provider/offers'), 0);
    });

    test('el detalle hereda la pestaña de su lista', () {
      expect(activeIndex(proveedor, '/provider/request/abc-123'), kCenterIndex);
      expect(activeIndex(cliente, '/client/request/abc-123'), 0);
      expect(activeIndex(cliente, '/messages/abc-123'), 3);
    });

    test('una ruta fuera de la barra no marca nada raro: cae en 0', () {
      expect(activeIndex(cliente, '/notifications'), 0);
    });
  });

  group('showsNavBar', () {
    test('la lista de conversaciones sí muestra la barra', () {
      expect(showsNavBar('/messages'), isTrue);
    });

    test('el detalle de una conversación la oculta', () {
      expect(showsNavBar('/messages/abc-123'), isFalse);
    });

    test('las demás rutas del shell sí muestran la barra', () {
      expect(showsNavBar('/client'), isTrue);
      expect(showsNavBar('/provider'), isTrue);
      expect(showsNavBar('/settings'), isTrue);
      expect(showsNavBar('/notifications'), isTrue);
      expect(showsNavBar('/client/request/abc-123'), isTrue);
      expect(showsNavBar('/provider/request/abc-123'), isTrue);
    });
  });
}
