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
