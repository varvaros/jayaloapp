import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/provider/opened_requests.dart';

/// Pedido PO 2026-08-22: "solicitudes tiene una notificación de 3, ya abrí
/// todas las ventanas y sigue ahí". El badge del proveedor contaba el
/// INVENTARIO de "Para ti", no la novedad — no existía nada que marcara una
/// solicitud como vista. Este store es ese "nada" que faltaba.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    openedRequestsStore.reset();
  });

  test('recién nacido no conoce ninguna solicitud', () async {
    await openedRequestsStore.ensureLoaded();
    expect(openedRequestsStore.ids, isEmpty);
    expect(openedRequestsStore.contains('a'), isFalse);
  });

  test('marcar abierta avisa AL INSTANTE, sin esperar al disco', () async {
    await openedRequestsStore.ensureLoaded();
    var avisos = 0;
    void oyente() => avisos++;
    openedRequestsStore.addListener(oyente);
    addTearDown(() => openedRequestsStore.removeListener(oyente));

    openedRequestsStore.markOpened('a');

    // Sin `await`: el badge tiene que bajar en el mismo frame en que se abre
    // la solicitud; persistir va detrás.
    expect(avisos, 1);
    expect(openedRequestsStore.contains('a'), isTrue);
  });

  test('marcar dos veces la misma NO vuelve a avisar', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markOpened('a');
    var avisos = 0;
    void oyente() => avisos++;
    openedRequestsStore.addListener(oyente);
    addTearDown(() => openedRequestsStore.removeListener(oyente));

    openedRequestsStore.markOpened('a');

    expect(avisos, 0, reason: 'idempotente: repintar de balde es ruido');
    expect(openedRequestsStore.ids, {'a'});
  });

  test('lo abierto sobrevive al reinicio', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markOpened('a');
    openedRequestsStore.markOpened('b');
    // Deja que el guardado en segundo plano llegue al disco.
    await Future<void>.delayed(Duration.zero);

    openedRequestsStore.reset();
    await openedRequestsStore.ensureLoaded();

    expect(openedRequestsStore.ids, {'a', 'b'});
  });

  test('sin persistencia arranca vacío en vez de reventar', () async {
    // Todas cuentan como sin abrir, que es el estado de antes de esta tanda:
    // el badge exagera, pero la bandeja nunca se cae.
    openedRequestsStore.reset();
    await openedRequestsStore.ensureLoaded();
    expect(openedRequestsStore.ids, isEmpty);
  });

  test('la vista de ids es de SOLO LECTURA', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markOpened('a');
    expect(() => openedRequestsStore.ids.add('b'), throwsUnsupportedError);
  });
}
