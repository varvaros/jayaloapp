import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/provider/opened_requests.dart';

/// Regla del PO (2026-08-22): «debe ser "lo que no has abierto"; si tiene una
/// actualización que no has abierto, cuenta». Por eso el store guarda la
/// VERSIÓN vista (el `updated_at` de la fila al abrirla) y no un simple "ya
/// abierta": eso apagaba la marca para siempre.
void main() {
  final t1 = DateTime.utc(2026, 8, 22, 10);
  final t2 = DateTime.utc(2026, 8, 22, 11);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    openedRequestsStore.reset();
  });

  test('nunca abierta = tiene algo sin ver', () async {
    await openedRequestsStore.ensureLoaded();
    expect(openedRequestsStore.hasUnseen('a', t1), isTrue);
  });

  test('abierta y sin cambios = vista', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    expect(openedRequestsStore.hasUnseen('a', t1), isFalse);
  });

  test('CAMBIADA después de verla = vuelve a tener algo sin ver', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    expect(openedRequestsStore.hasUnseen('a', t2), isTrue,
        reason: 'esta es la regla entera: una actualización la reactiva');
  });

  test('y al volver a abrirla se apaga otra vez', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    openedRequestsStore.markSeen('a', t2);
    expect(openedRequestsStore.hasUnseen('a', t2), isFalse);
  });

  test('sin updated_at no se puede saber: lo visto sigue visto', () async {
    // La consulta es best-effort. Se cree lo que se sabe.
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    expect(openedRequestsStore.hasUnseen('a', null), isFalse);
    expect(openedRequestsStore.hasUnseen('sin_abrir', null), isTrue);
  });

  test('marcar avisa AL INSTANTE, sin esperar al disco', () async {
    await openedRequestsStore.ensureLoaded();
    var avisos = 0;
    void oyente() => avisos++;
    openedRequestsStore.addListener(oyente);
    addTearDown(() => openedRequestsStore.removeListener(oyente));

    openedRequestsStore.markSeen('a', t1);

    expect(avisos, 1, reason: 'el badge baja en el mismo frame');
  });

  test('remarcar la MISMA versión no vuelve a avisar', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    var avisos = 0;
    void oyente() => avisos++;
    openedRequestsStore.addListener(oyente);
    addTearDown(() => openedRequestsStore.removeListener(oyente));

    openedRequestsStore.markSeen('a', t1);

    expect(avisos, 0, reason: 'idempotente: repintar de balde es ruido');
  });

  test('una versión VIEJA no pisa a una más nueva ya vista', () async {
    // Dos pantallas compitiendo, o una carga rezagada: lo visto no retrocede.
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t2);
    openedRequestsStore.markSeen('a', t1);
    expect(openedRequestsStore.hasUnseen('a', t2), isFalse);
  });

  test('lo visto sobrevive al reinicio', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    await Future<void>.delayed(Duration.zero);

    openedRequestsStore.reset();
    await openedRequestsStore.ensureLoaded();

    expect(openedRequestsStore.hasUnseen('a', t1), isFalse);
    expect(openedRequestsStore.hasUnseen('a', t2), isTrue);
  });

  test('la vista de lo visto es de SOLO LECTURA', () async {
    await openedRequestsStore.ensureLoaded();
    openedRequestsStore.markSeen('a', t1);
    expect(() => openedRequestsStore.seen['b'] = t1, throwsUnsupportedError);
  });
}
