import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// El kit consolida los patrones visuales aprobados en /notifications; estos
/// tests fijan el CONTRATO (tonos por fase, estados, tap), no los píxeles.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: jayaloTheme(brightness),
        home: Scaffold(body: Center(child: child)),
      );

  group('toneFor', () {
    testWidgets('mapea cada fase a su tono de la web (claro)', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      expect(toneFor(ctx, RequestPhase.waiting), JayaloStatus.pendingLight);
      expect(toneFor(ctx, RequestPhase.withOffers), JayaloStatus.respondedLight);
      expect(toneFor(ctx, RequestPhase.accepted), JayaloStatus.acceptedLight);
      expect(toneFor(ctx, RequestPhase.unlocked), JayaloStatus.unlockedLight);
      expect(toneFor(ctx, RequestPhase.completed), JayaloStatus.completedLight);
    });

    testWidgets('en oscuro usa la variante dark', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          host(Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }), brightness: Brightness.dark));
      expect(toneFor(ctx, RequestPhase.waiting), JayaloStatus.pendingDark);
      expect(toneFor(ctx, RequestPhase.unlocked), JayaloStatus.unlockedDark);
    });
  });

  group('StatusChip', () {
    testWidgets('pinta el label con la tinta del tono sobre su fondo',
        (tester) async {
      await tester.pumpWidget(host(const StatusChip(
          label: 'Con ofertas', tone: JayaloStatus.respondedLight)));
      expect(find.text('Con ofertas'), findsOneWidget);
      final box = tester.widget<Container>(find
          .ancestor(of: find.text('Con ofertas'), matching: find.byType(Container))
          .first);
      expect((box.decoration! as BoxDecoration).color,
          JayaloStatus.respondedLight.bg);
      expect(tester.widget<Text>(find.text('Con ofertas')).style?.color,
          JayaloStatus.respondedLight.ink);
    });

    testWidgets('muestra el ícono opcional', (tester) async {
      await tester.pumpWidget(host(const StatusChip(
          label: 'Desbloqueado',
          tone: JayaloStatus.unlockedLight,
          icon: Icons.lock_open)));
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });
  });

  group('JayaloCard', () {
    testWidgets('dispara onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(JayaloCard(
          onTap: () => taps++, child: const Text('hola'))));
      await tester.tap(find.text('hola'));
      expect(taps, 1);
    });

    testWidgets('con tinte usa ese fondo; sin tinte, superficie de card',
        (tester) async {
      await tester.pumpWidget(host(Column(children: const [
        JayaloCard(tint: Color(0xFFEDEBFF), child: Text('viva')),
        JayaloCard(child: Text('neutra')),
      ])));
      AnimatedContainer boxOf(String text) => tester.widget<AnimatedContainer>(
          find.ancestor(
              of: find.text(text), matching: find.byType(AnimatedContainer)));
      expect((boxOf('viva').decoration! as BoxDecoration).color,
          const Color(0xFFEDEBFF));
      expect((boxOf('neutra').decoration! as BoxDecoration).color,
          JayaloColors.card);
    });
  });

  group('EmptyState', () {
    testWidgets('muestra mensaje y CTA cuando se pasa', (tester) async {
      var pressed = false;
      await tester.pumpWidget(host(EmptyState(
        message: 'Aún no hay nada',
        ctaLabel: 'Crear',
        onCta: () => pressed = true,
      )));
      expect(find.text('Aún no hay nada'), findsOneWidget);
      await tester.tap(find.text('Crear'));
      expect(pressed, isTrue);
    });

    testWidgets('sin CTA no muestra botón', (tester) async {
      await tester.pumpWidget(host(const EmptyState(message: 'Vacío')));
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ErrorRetry', () {
    testWidgets('muestra mensaje y reintentar llama al callback',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(host(ErrorRetry(onRetry: () async {
        retries++;
      })));
      expect(find.text('No se pudo cargar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
    });
  });
}
