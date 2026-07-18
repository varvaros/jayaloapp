/// E2E del centro de notificaciones CONTRA PRODUCCIÓN, corriendo en el device.
///
/// Por qué existe: MIUI bloquea `adb shell input` (pide el toggle "Depuración
/// USB (Ajustes de seguridad)"), así que los gestos se inyectan por el motor de
/// Flutter. Y `flutter drive` no sirve para las capturas porque su reinstalación
/// del APK choca con `INSTALL_FAILED_USER_RESTRICTED` — por eso el propio test
/// escribe los PNG en la carpeta de la app y luego se sacan con `adb pull`.
///
/// Correr con: `flutter test integration_test/notifications_e2e_test.dart -d ID`
/// Sacar capturas: adb pull /sdcard/Android/data/com.jayalo.app/files/e2e
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/config.dart';
import 'package:jayalo_app/core/router.dart';
import 'package:jayalo_app/features/notifications/notification_bell.dart';
import 'package:jayalo_app/features/shared/jayalo_loader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _shotDir = '/sdcard/Android/data/com.jayalo.app/files/e2e';
final _root = GlobalKey();

Future<void> settle(WidgetTester t, {int ms = 600, int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary =
        _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shotDir).createSync(recursive: true);
    File('$_shotDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('campana -> lista -> swipe -> marcar todas', (t) async {
    await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey);
    // Sin initPush: el push no es parte de este recorrido y pediría permisos.
    await t.pumpWidget(
        RepaintBoundary(key: _root, child: JayaloApp(router: buildRouter())));
    await settle(t, ms: 1000, times: 10); // el gate resuelve el rol y entra

    expect(Supabase.instance.client.auth.currentSession, isNotNull,
        reason: 'necesita sesión iniciada en el teléfono');

    // 1) La campana existe en la pantalla principal del rol.
    expect(find.byType(NotificationBell), findsOneWidget);
    await shot(t, '01-home-campana');

    // 2) Abrir /notifications.
    await t.tap(find.byType(NotificationBell));
    await settle(t, ms: 800, times: 10);
    expect(find.text('Notificaciones'), findsOneWidget);
    await shot(t, '02-lista');

    // Vacío: debe mostrar la mascota (y ahí termina el recorrido).
    if (find.textContaining('Aún no tienes notificaciones').evaluate().isNotEmpty) {
      expect(find.byType(JayaloMascot), findsWidgets);
      await shot(t, '03-vacio-con-mascota');
      return;
    }

    // 3) Swipe sobre la primera tarjeta = marcar leída SIN eliminarla.
    final tarjetas = find.byType(Dismissible);
    expect(tarjetas, findsWidgets);
    final antes = tarjetas.evaluate().length;
    await t.drag(tarjetas.first, const Offset(320, 0));
    await settle(t, ms: 500, times: 8);
    expect(tarjetas.evaluate().length, antes,
        reason: 'la tarjeta NO se elimina al deslizar');
    await shot(t, '04-post-swipe');

    // 4) "Marcar todas", si el AppBar aún lo ofrece.
    final marcarTodas = find.byIcon(Icons.done_all);
    if (marcarTodas.evaluate().isNotEmpty) {
      await t.tap(marcarTodas);
      await settle(t, ms: 500, times: 10);
      await shot(t, '05-marcadas');
    }

    // 5) Volver: la campana debe quedar sin badge.
    await t.pageBack();
    await settle(t, ms: 600, times: 8);
    await shot(t, '06-home-sin-badge');
  });
}
