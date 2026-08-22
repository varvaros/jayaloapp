import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/chat/widgets/composer.dart';
import 'package:jayalo_app/features/shared/onboarding_copy.dart';
import 'package:jayalo_app/features/shared/onboarding_guide.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';

/// Tanda PO 2026-08-22: botones que no se explicaban. Cada guía nueva se
/// cablea con `onboardingCopy['clave']!`, así que una clave mal escrita
/// revienta la pantalla en producción — de ahí el primer test.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
  });

  test('las claves nuevas existen y traen texto', () {
    const nuevas = [
      'chat.menu.provider.v1',
      'chat.menu.client.v1',
      'chat.attach.provider.v1',
      'chat.attach.client.v1',
      'provider.offer_price_mode.v1',
      'provider.offer_reuse_photos.v1',
      'profile.menu.v1',
    ];
    for (final k in nuevas) {
      expect(onboardingCopy.containsKey(k), isTrue, reason: 'falta $k');
      expect(onboardingCopy[k]!.first.message.trim(), isNotEmpty, reason: k);
    }
    // El copy viejo del ⋮ solo nombraba "denunciar" de un menú con hasta 5
    // acciones: si sobreviviera, quien lo vio nunca leería el nuevo.
    expect(onboardingCopy.containsKey('chat.report.v1'), isFalse);
  });

  Widget composer(bool isProvider) => MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            isProvider: isProvider,
            sending: false,
            onSendText: (_) async => true,
            onPlusAction: (_) {},
            onQuickItem: (_) {},
          ),
        ),
      );

  /// El composer encadena dos guías: primero las respuestas rápidas (order 2)
  /// y después el `+` (order 4). Pasar la primera para llegar a la nueva deja
  /// cubierto, de paso, que el turno se cede de verdad.
  Future<void> pasarLaDeRespuestasRapidas(WidgetTester t) async {
    expect(find.textContaining('mensajes predefinidos'), findsOneWidget,
        reason: 'la guía de respuestas rápidas dejó de salir');
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
  }

  testWidgets('el + del chat se explica (cliente)', (t) async {
    await t.pumpWidget(composer(false));
    await t.pumpAndSettle();
    await pasarLaDeRespuestasRapidas(t);
    expect(find.textContaining('tus datos de contacto'), findsOneWidget,
        reason: 'el cliente no ve la guía del +');
  });

  testWidgets('el + del chat se explica con OTRO texto (proveedor)', (t) async {
    await t.pumpWidget(composer(true));
    await t.pumpAndSettle();
    await pasarLaDeRespuestasRapidas(t);
    expect(find.textContaining('artículos de tu tienda'), findsOneWidget,
        reason: 'el proveedor ve el copy del cliente');
  });

  testWidgets('Reiniciar tutorial: una guía ya descartada vuelve a salir',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: OnboardingGuide(
            guideKey: 'x.reinicio.v1',
            steps: [OnboardingStep('Esto se explica una vez')],
            child: SizedBox(width: 120, height: 40, child: Text('destino')),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Esto se explica una vez'), findsOneWidget);

    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    expect(find.text('Esto se explica una vez'), findsNothing,
        reason: 'no se cerró');
    expect(onboardingStore.isDone('x.reinicio.v1'), isTrue);

    // Y ahora el reinicio, SIN desmontar la pantalla. Se usa `reset()` y no
    // `resetAll()` porque este último borra en Supabase, que en un test no
    // está inicializado; el camino completo de `resetAll` (backend + prefs +
    // supresión) lo cubre `onboarding_store_test.dart`. Lo que se mide aquí
    // es lo otro: que la GUÍA reaccione al reinicio.
    onboardingStore.reset();
    await t.pumpAndSettle();
    expect(find.text('Esto se explica una vez'), findsOneWidget,
        reason: 'reiniciar el tutorial no la devolvió');
  });

  testWidgets('cerrar una guía NO la resucita sola (sin reinicio de por medio)',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: OnboardingGuide(
            guideKey: 'x.unavez.v1',
            steps: [OnboardingStep('Solo una vez')],
            child: SizedBox(width: 120, height: 40, child: Text('destino')),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Entendido'));
    await t.pumpAndSettle();
    // Varios frames por si algún notify tardío la reabre.
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Solo una vez'), findsNothing);
  });

  testWidgets('el avatar del encabezado se explica', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          ProfileAvatarButton(
            store: ProfileStore(loader: () async => null),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('Toca tu foto'), findsOneWidget);
  });
}
