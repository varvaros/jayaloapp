import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

class FakeRepo implements OnboardingRepo {
  FakeRepo({
    this.remote = const {},
    this.throwOnFetch = false,
    this.loggedIn = true,
    this.currentUserId = 'u1',
    this.throwOnClear = false,
  });
  Set<String> remote;
  bool throwOnFetch;
  bool loggedIn;
  @override
  String? currentUserId;
  final List<String> marked = [];
  int cleared = 0;
  bool throwOnClear;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<Set<String>> fetchCompleted() async {
    if (throwOnFetch) throw Exception('network');
    return {...remote};
  }

  @override
  Future<void> markCompleted(String key) async {
    marked.add(key);
    remote = {...remote, key};
  }

  @override
  Future<void> clearCompleted() async {
    if (throwOnClear) throw Exception('network');
    cleared++;
    remote = {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Reiniciar tutorial (resetAll)', () {
    test('olvida las guías del backend, del cache local y de memoria', () async {
      SharedPreferences.setMockInitialValues({
        'onboarding_guides_u1': ['b'],
        'hold_tutorial_done': ['accept'],
      });
      final repo = FakeRepo(remote: {'a'});
      final store = OnboardingStore.forTest(repo);
      await store.ensureLoaded();
      expect(store.isDone('a'), isTrue);

      await store.resetAll();

      expect(repo.cleared, 1, reason: 'no borró en el backend');
      expect(store.isDone('a'), isFalse);
      expect(store.isDone('b'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('onboarding_guides_u1'), isNull);
      expect(prefs.getStringList('hold_tutorial_done'), isNull,
          reason: 'el flag viejo del gesto revivirá las guías al reimportarse');
    });

    test('levanta la supresión: tras un fallo de red, reiniciar vuelve a mostrar',
        () async {
      final repo = FakeRepo(throwOnFetch: true);
      final store = OnboardingStore.forTest(repo);
      await store.ensureLoaded();
      expect(store.isDone('cualquiera'), isTrue); // suprimido

      await store.resetAll();
      expect(store.isDone('cualquiera'), isFalse);
    });

    test('si el borrado remoto falla, propaga y NO limpia nada', () async {
      final repo = FakeRepo(remote: {'a'}, throwOnClear: true);
      final store = OnboardingStore.forTest(repo);
      await store.ensureLoaded();

      await expectLater(store.resetAll(), throwsException);
      // Limpiar solo el cache local sería mentir: el próximo arranque las
      // vuelve a traer del backend.
      expect(store.isDone('a'), isTrue);
    });
  });

  test('merge de backend y cache local persistido', () async {
    SharedPreferences.setMockInitialValues({'onboarding_guides_u1': ['b']});
    final repo = FakeRepo(remote: {'a'});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('a'), isTrue);
    expect(store.isDone('b'), isTrue);
    expect(store.isDone('c'), isFalse);
  });

  test('fail-safe: backend falla sin cache local suprime todo', () async {
    final repo = FakeRepo(throwOnFetch: true);
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('cualquiera'), isTrue); // suprimido: no muestra guias
  });

  test('fail-safe: backend falla pero hay cache local usa el cache', () async {
    SharedPreferences.setMockInitialValues({'onboarding_guides_u1': ['b']});
    final repo = FakeRepo(throwOnFetch: true);
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('b'), isTrue);
    expect(store.isDone('z'), isFalse);
  });

  test('markDone agrega, marca en repo e idempotente', () async {
    final repo = FakeRepo(remote: {});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    await store.markDone('client.create_request.v1');
    await store.markDone('client.create_request.v1');
    expect(store.isDone('client.create_request.v1'), isTrue);
    expect(repo.marked, ['client.create_request.v1']);
  });

  test('import unico del flag viejo hold_tutorial_done', () async {
    SharedPreferences.setMockInitialValues({'hold_tutorial_done': ['accept', 'unlock']});
    final repo = FakeRepo(remote: {});
    final store = OnboardingStore.forTest(repo);
    await store.ensureLoaded();
    expect(store.isDone('gesture.accept.v1'), isTrue);
    expect(store.isDone('gesture.unlock.v1'), isTrue);
    expect(repo.marked.toSet(), {'gesture.accept.v1', 'gesture.unlock.v1'});
  });

  test('coordinador ordenado: gana la de menor order', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('b', 2);
    store.requestSlot('a', 1);
    store.requestSlot('c', 3);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    expect(store.isActive('b'), isFalse);
    // al liberar 'a', tras re-registrar entra la siguiente de menor orden (b)
    store.release('a');
    store.requestSlot('b', 2);
    store.requestSlot('c', 3);
    store.resolvePending();
    expect(store.isActive('b'), isTrue);
  });

  test('reentrante: pedir turno para la ya activa no la saca', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('a', 0);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    store.requestSlot('a', 0); // no-op
    expect(store.isActive('a'), isTrue);
  });

  test('reload limpia el coordinador: una guia activa no queda trabada', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    store.requestSlot('a', 0);
    store.resolvePending();
    expect(store.isActive('a'), isTrue);
    await store.reload();
    store.requestSlot('b', 0);
    store.resolvePending();
    expect(store.isActive('b'), isTrue);
  });
}
