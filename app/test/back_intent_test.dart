import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/back_intent.dart';

void main() {
  group('homePathFor', () {
    test('proveedor va a /provider', () {
      expect(homePathFor(provider: true), '/provider');
    });
    test('cliente va a /client', () {
      expect(homePathFor(provider: false), '/client');
    });
  });

  group('backActionFor', () {
    test('fuera del home: ATRÁS lleva al home', () {
      expect(
        backActionFor(location: '/client/create', homePath: '/client', atTop: true),
        BackAction.goHome,
      );
      expect(
        backActionFor(
            location: '/provider/request/abc',
            homePath: '/provider',
            atTop: false),
        BackAction.goHome,
      );
      expect(
        backActionFor(location: '/settings', homePath: '/client', atTop: true),
        BackAction.goHome,
      );
    });

    test('dentro de una conversación: ATRÁS va a la lista de conversaciones',
        () {
      expect(
        backActionFor(
            location: '/messages/abc-123', homePath: '/client', atTop: true),
        BackAction.goMessages,
      );
      expect(
        backActionFor(
            location: '/messages/abc-123', homePath: '/provider', atTop: false),
        BackAction.goMessages,
      );
      // La LISTA (/messages, sin id) no es una conversación: sigue la regla
      // general (fuera del home → home).
      expect(
        backActionFor(location: '/messages', homePath: '/client', atTop: true),
        BackAction.goHome,
      );
    });

    test('dentro de un producto del catálogo: ATRÁS va al catálogo', () {
      // Pedido PO 2026-08-03: el atrás sacaba a "Solicitudes" desde el detalle
      // de un producto, cuando el usuario venía del catálogo. Mismo criterio
      // que las conversaciones: se vuelve a la LISTA de donde saliste.
      expect(
        backActionFor(location: '/catalog/p1', homePath: '/client', atTop: true),
        BackAction.goCatalog,
      );
      expect(
        backActionFor(
            location: '/catalog/p1', homePath: '/provider', atTop: false),
        BackAction.goCatalog,
      );
      // La LISTA (/catalog, sin id) es una pestaña raíz: sigue la regla general.
      expect(
        backActionFor(location: '/catalog', homePath: '/client', atTop: true),
        BackAction.goHome,
      );
    });

    test(
        'dentro del detalle de producto abierto desde la TIENDA: ATRÁS hace '
        'un pop real (cae en la tienda de la que se vino)', () {
      // Pedido PO 2026-08-09: a diferencia de `/catalog/p1`, `/product/:id`
      // no tiene un único destino fijo (la tienda se abre desde varios
      // lugares) — por eso necesita `canPop` en vez de una ruta hardcodeada.
      expect(
        backActionFor(
            location: '/product/p1',
            homePath: '/client',
            atTop: true,
            canPop: true),
        BackAction.popCurrent,
      );
      expect(
        backActionFor(
            location: '/product/p1',
            homePath: '/provider',
            atTop: false,
            canPop: true),
        BackAction.popCurrent,
      );
    });

    test(
        'detalle de producto SIN nada debajo (canPop=false): sigue la regla '
        'general en vez de quedar atrapado', () {
      expect(
        backActionFor(
            location: '/product/p1',
            homePath: '/client',
            atTop: true,
            canPop: false),
        BackAction.goHome,
      );
    });

    test('en el home con scroll: ATRÁS sube al tope', () {
      expect(
        backActionFor(location: '/client', homePath: '/client', atTop: false),
        BackAction.scrollTop,
      );
      expect(
        backActionFor(location: '/provider', homePath: '/provider', atTop: false),
        BackAction.scrollTop,
      );
    });

    test('en el home y en el tope: ATRÁS pregunta si cerrar', () {
      expect(
        backActionFor(location: '/client', homePath: '/client', atTop: true),
        BackAction.confirmExit,
      );
      expect(
        backActionFor(location: '/provider', homePath: '/provider', atTop: true),
        BackAction.confirmExit,
      );
    });
  });
}
