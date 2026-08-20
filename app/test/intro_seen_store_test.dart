// La marca de «el intro ya se vio EN ESTE TELÉFONO» (PO 2026-08-20).
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';
import 'package:jayalo_app/features/auth/intro_seen_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin marca previa devuelve false', () async {
    expect(await IntroSeenStore().read(), isFalse);
  });

  test('markSeen deja la marca puesta', () async {
    await IntroSeenStore().markSeen();
    expect(await IntroSeenStore().read(), isTrue);
  });

  test('markSeen dos veces sigue siendo true (idempotente)', () async {
    await IntroSeenStore().markSeen();
    await IntroSeenStore().markSeen();
    expect(await IntroSeenStore().read(), isTrue);
  });

  test('la clave NO lleva sufijo de usuario: es POR DISPOSITIVO', () {
    // Si llevara uid, el segundo usuario del mismo teléfono volvería a ver el
    // intro — que es justo lo contrario de lo que pidió el PO.
    expect(IntroSeenStore.kKey, 'intro_seen_v1');
  });

  test('la marca es INDEPENDIENTE de la elección de rol', () async {
    // `IntroRoleStore` SÍ se consume y se borra en el alta; ésta no. Borrar
    // una no puede arrastrar a la otra, o el intro reaparecería tras el alta.
    await IntroSeenStore().markSeen();
    await IntroRoleStore().save(IntroRole.provider);
    await IntroRoleStore().clear();
    expect(await IntroSeenStore().read(), isTrue);
  });
}
