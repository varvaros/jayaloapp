import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

class FakeRepo implements OnboardingRepo {
  FakeRepo({
    this.remote = const {},
    this.throwOnFetch = false,
    this.loggedIn = true,
    this.currentUserId = 'u1',
  });
  Set<String> remote;
  bool throwOnFetch;
  bool loggedIn;
  @override
  String? currentUserId;
  final List<String> marked = [];

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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  test('coordinador: solo una guia activa a la vez', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    expect(store.acquire('a'), isTrue);
    expect(store.acquire('b'), isFalse);
    expect(store.acquire('a'), isTrue); // reentrante para la misma clave
    store.release('a');
    expect(store.acquire('b'), isTrue);
  });

  test('reload limpia el coordinador: una guia activa no queda trabada', () async {
    final store = OnboardingStore.forTest(FakeRepo());
    await store.ensureLoaded();
    expect(store.acquire('a'), isTrue); // queda "mostrándose" para el usuario 1

    await store.reload(); // p. ej. cambio de sesión (auth signedIn)

    expect(store.acquire('b'), isTrue); // no debe quedar bloqueado por 'a'
  });
}
