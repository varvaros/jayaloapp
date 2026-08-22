import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/features/chat/widgets/composer.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-08-22 (con captura de WhatsApp como referencia): los
/// accesorios del chat viven DENTRO de la misma barra de mensaje —emoji a la
/// izquierda, respuestas rápidas y adjuntar a la derecha— y solo el envío
/// queda fuera, como círculo de acción. Antes los tres iconos colgaban FUERA
/// del campo, por la izquierda, y le comían el ancho.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    // La guía de respuestas rápidas monta un velo que taparía la barra.
    await onboardingStore.markDone('chat.quick_replies.v1');
  });

  final pill = find.byKey(const Key('chat.composer.pill'));

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatComposer(
            isProvider: false,
            sending: false,
            onSendText: (_) async => true,
            onPlusAction: (_) {},
            onQuickItem: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('los tres accesorios van DENTRO de la misma barra que el texto',
      (tester) async {
    await pumpComposer(tester);

    expect(pill, findsOneWidget);
    // El campo de texto y los tres iconos comparten contenedor.
    expect(find.descendant(of: pill, matching: find.byType(TextField)),
        findsOneWidget);
    for (final icon in const [
      Icons.emoji_emotions_outlined,
      Icons.quickreply_outlined,
      Icons.add,
    ]) {
      expect(find.descendant(of: pill, matching: find.byIcon(icon)),
          findsOneWidget,
          reason: 'el icono $icon debe vivir dentro de la barra de mensaje');
    }
  });

  testWidgets('el emoji abre a la IZQUIERDA del texto y adjuntar a la DERECHA',
      (tester) async {
    await pumpComposer(tester);

    final texto = tester.getRect(find.byType(TextField));
    final emoji = tester.getCenter(find.byIcon(Icons.emoji_emotions_outlined));
    final rapidas = tester.getCenter(find.byIcon(Icons.quickreply_outlined));
    final adjuntar = tester.getCenter(find.byIcon(Icons.add));

    expect(emoji.dx, lessThan(texto.left),
        reason: 'el emoji es el prefijo de la barra');
    expect(rapidas.dx, greaterThan(texto.right),
        reason: 'las respuestas rápidas son sufijo, no prefijo');
    expect(adjuntar.dx, greaterThan(rapidas.dx),
        reason: 'adjuntar cierra la barra por la derecha');
  });

  testWidgets('el botón de enviar queda FUERA de la barra, a su derecha',
      (tester) async {
    await pumpComposer(tester);

    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.descendant(of: pill, matching: find.byIcon(Icons.send)),
        findsNothing);
    expect(tester.getCenter(find.byIcon(Icons.send)).dx,
        greaterThan(tester.getRect(pill).right));
  });

  testWidgets('el campo se queda con el ancho: la barra ocupa casi todo',
      (tester) async {
    await pumpComposer(tester);

    final ancho = tester.getSize(find.byType(MaterialApp)).width;
    final barra = tester.getRect(pill).width;
    // Solo el círculo de enviar y los márgenes salen de la barra.
    expect(barra, greaterThan(ancho * 0.80),
        reason: 'la barra de mensaje es la protagonista, no los iconos');
  });
}
