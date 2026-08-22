import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/features/settings/settings_screen.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// Tanda PO 2026-08-22: confirmación al reiniciar el tutorial y hold de 5 s
/// para borrar la cuenta. (Que "Cerrar sesión" ya no esté en Ajustes y sí al
/// final del menú del avatar lo fija `profile_avatar_button_test.dart`;
/// `SettingsScreen` entera no se puede montar en un test porque su `build`
/// toca `Supabase.instance`.)
void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('confirmResetGuides', () {
    testWidgets('Cancelar devuelve false', (t) async {
      bool? r;
      await t.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => r = await confirmResetGuides(ctx),
          child: const Text('abrir'),
        ),
      )));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text('¿Reiniciar el tutorial?'), findsOneWidget);

      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(r, isFalse);
    });

    testWidgets('"Sí, reiniciar" devuelve true', (t) async {
      bool? r;
      await t.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => r = await confirmResetGuides(ctx),
          child: const Text('abrir'),
        ),
      )));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sí, reiniciar'));
      await t.pumpAndSettle();
      expect(r, isTrue);
    });
  });

  testWidgets('hold de 5 s: a los 2,5 s (el hold normal) NO confirma',
      (t) async {
    var confirmado = 0;
    await t.pumpWidget(host(HoldToConfirmButton(
      duration: const Duration(seconds: 5),
      label: 'Mantén pulsado 5 segundos',
      onConfirmed: () async => confirmado++,
    )));

    final g = await t.startGesture(
        t.getCenter(find.byType(HoldToConfirmButton)));
    await t.pump(); // resuelve la arena de gestos antes de saltar el reloj
    await t.pump(JayaloMotion.holdConfirm + const Duration(milliseconds: 100));
    expect(confirmado, 0, reason: 'confirmó con el tiempo del hold normal');

    await t.pump(const Duration(milliseconds: 2500));
    expect(confirmado, 1, reason: 'a los 5 s tiene que confirmar');
    await g.up();
  });
}
