import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/shared/hold_tutorial_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isDone es falso por defecto para ambos gestos', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    expect(s.isDone('accept'), isFalse);
    expect(s.isDone('unlock'), isFalse);
  });

  test('markDone vuelve isDone verdadero solo para ese gesto', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    s.markDone('accept');
    expect(s.isDone('accept'), isTrue);
    expect(s.isDone('unlock'), isFalse);
  });

  test('markDone notifica a los oyentes una sola vez (idempotente)', () async {
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    var notifications = 0;
    s.addListener(() => notifications++);
    s.markDone('unlock');
    s.markDone('unlock');
    expect(notifications, 1);
  });

  test('ensureLoaded recupera lo persistido de un arranque anterior', () async {
    SharedPreferences.setMockInitialValues({
      'hold_tutorial_done': ['unlock'],
    });
    final s = HoldTutorialStore();
    await s.ensureLoaded();
    expect(s.isDone('unlock'), isTrue);
    expect(s.isDone('accept'), isFalse);
  });
}
