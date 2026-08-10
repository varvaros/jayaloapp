import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/provider/hidden_requests_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hide/contains/unhide: idempotente y notifica', () async {
    SharedPreferences.setMockInitialValues({});
    final store = HiddenRequestsStore();
    await store.ensureLoaded();
    var avisos = 0;
    store.addListener(() => avisos++);

    expect(store.contains('a'), false);
    store.hide('a');
    expect(store.contains('a'), true);
    expect(avisos, 1);

    store.hide('a'); // repetir no re-notifica
    expect(avisos, 1);

    store.unhide('a');
    expect(store.contains('a'), false);
    expect(avisos, 2);

    store.unhide('a'); // quitar lo que no está tampoco
    expect(avisos, 2);
  });

  test('ensureLoaded lee el set persistido', () async {
    SharedPreferences.setMockInitialValues({
      'hidden_requests': ['req-x'],
    });
    final store = HiddenRequestsStore();
    await store.ensureLoaded();
    expect(store.contains('req-x'), true);
    expect(store.contains('req-y'), false);
  });

  test('hide persiste para el próximo arranque', () async {
    SharedPreferences.setMockInitialValues({});
    final a = HiddenRequestsStore();
    await a.ensureLoaded();
    a.hide('req-z');
    // La persistencia es fire-and-forget: dar un turno al event loop.
    await Future<void>.delayed(Duration.zero);

    final b = HiddenRequestsStore();
    await b.ensureLoaded();
    expect(b.contains('req-z'), true);
  });
}
