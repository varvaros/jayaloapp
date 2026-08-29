// Tests de `clearAlertNotifications` — la mitad de app del arreglo del globo
// del ícono (2026-08-28). Lo que se protege aquí es la SELECTIVIDAD: el helper
// tiene que llevarse los avisos y dejar vivos los chats sin leer. Un
// `cancelAll()` pasaría igual de verde en un test ingenuo y borraría de la
// bandeja conversaciones que el usuario no ha abierto, así que el test afirma
// sobre QUÉ pares (id, tag) se cancelan, no sobre cuántos.
//
// Se intercepta el MethodChannel del plugin porque no hay Android debajo: las
// notificaciones "vivas" son las que devuelve el mock.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/push/chat_notifications.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Pares (id, tag) que el helper pidió cancelar, en orden.
  late List<Map<String, Object?>> cancelados;

  setUpAll(() {
    // Fuera de un Android real nadie registra la implementación de plataforma
    // (lo hace el registrant nativo) y `flnp` revienta con
    // LateInitializationError — que el helper TRAGA, así que sin esto los
    // tests pasarían en verde sin ejercitar una sola línea. El override de
    // plataforma es igual de portante: `cancel` solo toma la rama que manda el
    // `tag` cuando cree estar en Android, y el tag es lo único que distingue
    // las notificaciones de FCM entre sí.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  /// Instala el mock con [activas] como bandeja del sistema. [alLeer] permite
  /// simular que `getActiveNotifications` LANZA (API < 23).
  void montar(List<Map<String, Object?>> activas, {Object? alLeer}) {
    cancelados = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'getActiveNotifications':
          if (alLeer != null) throw alLeer;
          return activas;
        case 'cancel':
          cancelados.add(Map<String, Object?>.from(call.arguments as Map));
          return null;
        default:
          return null;
      }
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // Retrato de la bandeja REAL del móvil del PO el 2026-08-28, volcada con
  // `adb shell dumpsys notification`: las de FCM llegan con id 0 y un tag
  // propio; la local, con tag null. Por eso cancelar exige la PAREJA.
  List<Map<String, Object?>> bandejaDelPo() => [
        {
          'id': 0,
          'tag': 'FCM-Notification:467916175',
          'channelId': kAlertsChannelId,
          'title': 'Recordatorio de fecha pautada',
        },
        {
          'id': 0,
          'tag': 'FCM-Notification:393657220',
          'channelId': kChatChannelId,
          'title': 'Nuevo mensaje',
        },
        {
          'id': 1067631047,
          'tag': null,
          'channelId': kAlertsChannelId,
          'title': 'Alguien marcó interés en tu producto',
        },
      ];

  test('cancela los avisos y NO toca los mensajes de chat sin leer', () async {
    montar(bandejaDelPo());

    await clearAlertNotifications();

    expect(cancelados, [
      {'id': 0, 'tag': 'FCM-Notification:467916175'},
      {'id': 1067631047, 'tag': null},
    ]);
    // La red de verdad: el chat sigue en la bandeja.
    expect(
      cancelados.any((c) => c['tag'] == 'FCM-Notification:393657220'),
      isFalse,
      reason: 'un cancelAll() se llevaría el chat sin leer por delante',
    );
  });

  test('cancela por PAREJA (id, tag): las de FCM comparten el id 0', () async {
    montar([
      {'id': 0, 'tag': 'FCM-Notification:1', 'channelId': kAlertsChannelId},
      {'id': 0, 'tag': 'FCM-Notification:2', 'channelId': kAlertsChannelId},
    ]);

    await clearAlertNotifications();

    // Dos cancelaciones distintas, no una: el id por sí solo no las distingue.
    expect(cancelados, [
      {'id': 0, 'tag': 'FCM-Notification:1'},
      {'id': 0, 'tag': 'FCM-Notification:2'},
    ]);
  });

  test('sin canal (Android < 8) esa notificacion se respeta, no se arrasa',
      () async {
    // El plugin solo rellena `channelId` en API >= 26; por debajo llega null.
    // Ante la duda, NO se borra: es preferible un globo alto a una bandeja
    // vaciada a ciegas.
    //
    // La de alertas va al lado A PROPÓSITO: sin ella el test afirmaría sobre
    // una lista vacía, que es exactamente lo que produce un helper que reventó
    // y se tragó la excepción. Así el verde exige que el filtro CORRIÓ y
    // discriminó, no solo que no cancelo nada.
    montar([
      {'id': 7, 'tag': null, 'channelId': null},
      {'id': 8, 'tag': null, 'channelId': kAlertsChannelId},
    ]);

    await clearAlertNotifications();

    expect(cancelados, [
      {'id': 8, 'tag': null}
    ]);
  });

  test('si leer la bandeja lanza, no propaga (API < 23)', () async {
    montar(const [], alLeer: PlatformException(code: 'unsupported_os_version'));

    // Best-effort: un fallo aquí nunca debe romper la pantalla que lo llama.
    await expectLater(clearAlertNotifications(), completes);
    expect(cancelados, isEmpty);
  });

  test('bandeja vacía: no llama a cancel ni una vez', () async {
    montar(const []);

    await clearAlertNotifications();

    expect(cancelados, isEmpty);
  });
}
