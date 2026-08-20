import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin elección guardada devuelve null', () async {
    expect(await IntroRoleStore().read(), isNull);
  });

  test('guarda y relee cliente', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.consumer);
    expect(await store.read(), IntroRole.consumer);
  });

  test('guarda y relee proveedor', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.provider);
    expect(await store.read(), IntroRole.provider);
  });

  test('clear borra la elección', () async {
    final store = IntroRoleStore();
    await store.save(IntroRole.provider);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('un valor basura en prefs se trata como sin elección', () async {
    // Defensa contra una versión anterior que hubiera escrito otro formato.
    SharedPreferences.setMockInitialValues({IntroRoleStore.kKey: 'gerente'});
    expect(await IntroRoleStore().read(), isNull);
  });

  test('la clave NO lleva sufijo de usuario', () {
    // En la lámina 1 aún no hay sesión, así que no hay uid que colgarle.
    expect(IntroRoleStore.kKey, 'intro_role_choice');
  });
}
