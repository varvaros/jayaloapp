import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';

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

  group('doctrina de movimiento', () {
    testWidgets('JayaloCard se encoge al presionar y vuelve al soltar',
        (tester) async {
      await tester.pumpWidget(host(JayaloCard(
          onTap: () {}, child: const SizedBox(width: 200, height: 60))));

      AnimatedScale scaleOf() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleOf().scale, 1);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(JayaloCard)));
      // El highlight de InkWell tarda un frame corto en activarse.
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf().scale, JayaloMotion.pressedScale,
          reason: 'presionada debe encoger');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf().scale, 1, reason: 'al soltar vuelve suave a 1');
    });

    testWidgets('sin onTap no hay feedback de escala', (tester) async {
      await tester.pumpWidget(
          host(const JayaloCard(child: SizedBox(width: 200, height: 60))));
      await tester
          .startGesture(tester.getCenter(find.byType(JayaloCard)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('cascadeIn respeta "reducir animaciones"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: const Text('hola').cascadeIn(0)),
        ),
      ));
      expect(find.byType(Animate), findsNothing,
          reason: 'con reduce-motion no se envuelve en Animate');
      expect(find.text('hola'), findsOneWidget);
    });

    testWidgets('SkeletonList pinta N tarjetas y brilla sin excepciones',
        (tester) async {
      await tester.pumpWidget(host(const SizedBox(
          height: 400, width: 300, child: SkeletonList(count: 3))));
      expect(find.byType(SkeletonCard), findsNWidgets(3));
      // El shimmer es un loop: se avanza a mano (pumpAndSettle nunca acaba).
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('SkeletonCard queda quieto con "reducir animaciones"',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SkeletonCard()),
        ),
      ));
      expect(find.byType(Animate), findsNothing);
    });
  });

  group('HoldToConfirmButton', () {
    testWidgets('mantener presionado el tiempo completo confirma',
        (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(host(HoldToConfirmButton(
          onConfirmed: () async {
            confirmed++;
          },
          label: 'Mantén presionado')));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(HoldToConfirmButton)));
      // Pump vacío: el down debe resolver la arena de gestos (onTapDown)
      // ANTES de saltar el reloj — un solo pump largo no lo dispara.
      await tester.pump();
      await tester.pump(JayaloMotion.holdConfirm + const Duration(milliseconds: 50));
      expect(confirmed, 1);
      await gesture.up();
    });

    testWidgets('soltar antes de tiempo no confirma', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(host(HoldToConfirmButton(onConfirmed: () async {
        confirmed++;
      })));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(HoldToConfirmButton)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, 0);
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
  group('showJayaloToast', () {
    testWidgets('flotante y con margen inferior que libra la navbar',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      showJayaloToast(ctx, 'Aviso de prueba');
      await tester.pump();
      expect(find.text('Aviso de prueba'), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, SnackBarBehavior.floating);
      final margin = bar.margin!.resolve(TextDirection.ltr);
      expect(margin.bottom,
          greaterThanOrEqualTo(navBarReservedSpace(ctx) + 12));
    });
  });
}
