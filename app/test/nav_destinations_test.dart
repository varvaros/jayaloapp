import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// La barra tiene 5 destinos: 2 · centro · 2. Desde la iteración 2 el centro
/// es la MISMA acción para los dos roles (crear solicitud, `/client/create`):
/// el PO recordó que un proveedor también puede solicitar. El resto del mapa
/// sí difiere por rol — ver la tabla del PO en
/// `docs/superpowers/plans/2026-07-18-navbar-iteracion-2.md` §0.1.
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

    test('el centro es crear una solicitud para los dos roles', () {
      expect(destinationsFor(RoleState.consumer)[kCenterIndex].route,
          '/client/create');
      expect(destinationsFor(RoleState.provider)[kCenterIndex].route,
          '/client/create');
    });

    test('mapa exacto del cliente (tabla del PO, en orden)', () {
      final d = destinationsFor(RoleState.consumer);
      expect(d[0].route, '/client');
      expect(d[1].route, '/catalog');
      expect(d[2].route, '/client/create');
      expect(d[3].route, '/messages');
      expect(d[4].route, '/client/reputation');
    });

    test('mapa exacto del proveedor (tabla del PO, en orden)', () {
      final d = destinationsFor(RoleState.provider);
      expect(d[0].route, '/provider');
      expect(d[0].label, 'Solicitudes');
      expect(d[1].route, '/provider/offers');
      expect(d[2].route, '/client/create');
      expect(d[3].route, '/messages');
      expect(d[4].route, '/provider/business');
      expect(d[4].label, 'Mi negocio');
    });

    test('/settings y /provider/stats ya no son destinos de la barra', () {
      for (final rol in [RoleState.consumer, RoleState.provider]) {
        final routes = destinationsFor(rol).map((d) => d.route);
        expect(routes, isNot(contains('/settings')), reason: '$rol');
        expect(routes, isNot(contains('/provider/stats')), reason: '$rol');
      }
    });

    test('ningún rol ve rutas exclusivas del otro', () {
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
      for (final rol in [RoleState.consumer, RoleState.provider]) {
        for (final d in destinationsFor(rol)) {
          expect(d.label.trim(), isNotEmpty, reason: '$rol ${d.route}');
        }
      }
    });
  });

  group('activeIndex', () {
    final cliente = destinationsFor(RoleState.consumer);
    final proveedor = destinationsFor(RoleState.provider);

    test('la ruta exacta marca su destino', () {
      expect(activeIndex(cliente, '/client'), 0);
      expect(activeIndex(cliente, '/messages'), 3);
      expect(activeIndex(cliente, '/client/create'), kCenterIndex);
    });

    test(
        'el centro es compartido: /client/create enciende el centro en los '
        'dos roles, no la pestaña lateral cuyo prefijo también calza', () {
      // Para el cliente, '/client' (índice 0) es prefijo de '/client/create'.
      // Gana el prefijo más largo ('/client/create', el centro), no el 0.
      expect(activeIndex(cliente, '/client/create'), kCenterIndex);
      // Para el proveedor no hay ambigüedad de prefijo, pero confirma que
      // comparte el mismo centro que el cliente.
      expect(activeIndex(proveedor, '/client/create'), kCenterIndex);
    });

    test(
        'gana el prefijo MÁS LARGO, no el primero que coincide '
        '(/provider ahora es lateral, no el centro)', () {
      expect(activeIndex(proveedor, '/provider'), 0);
      expect(activeIndex(proveedor, '/provider/offers'), 1);
      expect(activeIndex(proveedor, '/provider/business'), 4);
    });

    test('/provider/stats ya no enciende ninguna pestaña: da -1', () {
      // Su ruta sigue viva (se llega por el avatar) pero salió del mapa.
      expect(activeIndex(proveedor, '/provider/stats'), -1);
    });

    test('/settings ya no enciende ninguna pestaña: da -1', () {
      expect(activeIndex(cliente, '/settings'), -1);
      expect(activeIndex(proveedor, '/settings'), -1);
    });

    test('el detalle de una solicitud hereda la pestaña de su bandeja', () {
      expect(activeIndex(cliente, '/client/request/abc-123'), 0);
      // El detalle de una solicitud del proveedor (`/provider/request/:id`)
      // cuelga de su bandeja (`/provider`, hoy en el puesto 0, "Solicitudes"),
      // así que hereda el 0 — igual que el detalle del cliente hereda el 0
      // de su propia bandeja. La regla del prefijo más largo lo produce sola
      // (ningún otro destino del proveedor empieza por '/provider/request'),
      // y es el resultado correcto: no hay una pestaña más específica a la
      // que deba apuntar.
      expect(activeIndex(proveedor, '/provider/request/abc-123'), 0);
      expect(activeIndex(cliente, '/messages/abc-123'), 3);
    });

    test('el detalle de un producto del catálogo enciende Catálogo', () {
      expect(activeIndex(cliente, '/catalog/xyz'), 1);
    });

    test('una ruta fuera de la barra no enciende ninguna pestaña: da -1', () {
      expect(activeIndex(cliente, '/notifications'), -1);
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
      expect(showsNavBar('/catalog'), isTrue);
      expect(showsNavBar('/catalog/xyz'), isTrue);
      expect(showsNavBar('/provider/business'), isTrue);
      expect(showsNavBar('/settings'), isTrue);
      expect(showsNavBar('/notifications'), isTrue);
      expect(showsNavBar('/client/request/abc-123'), isTrue);
      expect(showsNavBar('/provider/request/abc-123'), isTrue);
    });
  });
}
