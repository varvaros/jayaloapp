import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/core/motion.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shared/moneda.dart';

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
      // "Oferta aceptada" = azul claro (pedido PO 2026-07-21), ya no el ámbar.
      expect(toneFor(ctx, RequestPhase.accepted), JayaloStatus.offerAcceptedLight);
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
      // Se recorre un ciclo completo (1800ms) en pasos chicos para cruzar
      // tanto la fase de barrido como la pausa en que no se pinta ShaderMask.
      var sawSweep = false;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        if (find.byType(ShaderMask).evaluate().isNotEmpty) sawSweep = true;
      }
      expect(tester.takeException(), isNull);
      expect(sawSweep, isTrue,
          reason: 'la banda de luz debe pintarse en algún punto del ciclo');
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
      // Sin movimiento no se monta el ShaderMask del barrido en NINGÚN frame
      // del ciclo (antes esto miraba `Animate`, que ya no se usa acá).
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(ShaderMask), findsNothing);
      }
    });

    // ── El SALUDO del borde de "sin ver" (PO 2026-08-19/20) ────────────
    //
    // El contrato que fijan estos tests es lo que hace que la marca signifique
    // algo: el borde ARRANCA y TERMINA lleno (nunca desaparece, porque es
    // información), respira un número FINITO de veces (un bucle sería la única
    // animación perpetua de la app, y encima dentro de una lista) y cada
    // respiro se apaga menos que el anterior — se asienta, no se corta.

    test('pulseOpacity arranca y termina en el borde LLENO', () {
      expect(JayaloMotion.pulseOpacity(0), 1);
      expect(JayaloMotion.pulseOpacity(1), closeTo(1, 1e-9));
      // Fuera de rango tampoco se rompe: la marca sigue entera.
      expect(JayaloMotion.pulseOpacity(-1), 1);
      expect(JayaloMotion.pulseOpacity(2), closeTo(1, 1e-9));
    });

    test('pulseOpacity: el borde nunca se apaga del todo', () {
      for (var i = 0; i <= 200; i++) {
        final o = JayaloMotion.pulseOpacity(i / 200);
        expect(o, greaterThanOrEqualTo(JayaloMotion.pulseDepth - 1e-9),
            reason: 'en t=${i / 200} el borde bajó del suelo');
        expect(o, lessThanOrEqualTo(1 + 1e-9));
      }
    });

    test('pulseOpacity: cada respiro se apaga MENOS que el anterior', () {
      // El fondo de cada valle cae en el centro de su respiro.
      final fondos = [
        for (var i = 0; i < JayaloMotion.pulseBreaths; i++)
          JayaloMotion.pulseOpacity((i + 0.5) / JayaloMotion.pulseBreaths),
      ];
      expect(fondos.first, closeTo(JayaloMotion.pulseDepth, 1e-9),
          reason: 'el primer respiro es el más hondo');
      expect(fondos.last, closeTo(JayaloMotion.pulseDepthLast, 1e-9),
          reason: 'el último apenas se nota, pero se nota');
      for (var i = 1; i < fondos.length; i++) {
        expect(fondos[i], greaterThan(fondos[i - 1]),
            reason: 'el respiro $i debe apagarse menos que el anterior');
      }
    });

    /// Opacidad del borde que está saludando en este preciso frame.
    double pulseAlpha(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(find.byKey(kPulseBorderKey));
      return ((box.decoration as BoxDecoration).border! as Border).top.color.a;
    }

    Widget tarjeta({
      required bool saluda,
      Widget? hijo,
      Key? key,
      Color color = const Color(0xFF7147F2),
    }) =>
        JayaloCard(
          key: key,
          border: Border.all(color: color, width: 2),
          pulseBorder: saluda,
          child: hijo ?? const SizedBox(width: 200, height: 60),
        );

    testWidgets('JayaloCard saluda: el borde respira y acaba lleno',
        (tester) async {
      await tester.pumpWidget(host(tarjeta(saluda: true)));
      expect(pulseAlpha(tester), closeTo(1, 1e-3),
          reason: 'entra con el borde lleno');

      var masTenue = 1.0;
      const paso = Duration(milliseconds: 80);
      final pasos = (JayaloMotion.pulseCycle * JayaloMotion.pulseBreaths)
              .inMilliseconds ~/
          paso.inMilliseconds;
      for (var i = 0; i < pasos; i++) {
        await tester.pump(paso);
        final a = pulseAlpha(tester);
        if (a < masTenue) masTenue = a;
        expect(a, greaterThanOrEqualTo(JayaloMotion.pulseDepth - 1e-3),
            reason: 'el borde no puede desaparecer: es información');
      }
      expect(masTenue, lessThan(.5),
          reason: 'si nunca se apagó de verdad, no respiró');

      await tester.pumpAndSettle();
      expect(pulseAlpha(tester), closeTo(1, 1e-3),
          reason: 'aterriza en el borde lleno de siempre');
    });

    testWidgets('el saludo NO desplaza el contenido ni un píxel',
        (tester) async {
      // El borde visible se pinta en una capa ENCIMA, pero el grosor se
      // reserva igual abajo. Lo que hay que medir es el TAMAÑO de la tarjeta
      // contra una que no saluda.
      //
      // TRES formulaciones que parecían obvias y NO sirven — las tres
      // comprobadas por mutación, pasando con el bug puesto:
      //  1. medir "durante" contra "después" en la misma tarjeta: el grosor
      //     reservado es constante en el tiempo, no hay nada que cambie;
      //  2. mirar la esquina del hijo: el `Center` del host desplaza la
      //     tarjeta media diferencia y cancela exactamente los 2 px;
      //  3. remontar sin `key`: se reusa el elemento y el `AnimatedContainer`
      //     sigue interpolando la decoración vieja 300 ms, así que devuelve el
      //     tamaño anterior.
      Future<Size> tamano({required bool saluda, required String k}) async {
        await tester
            .pumpWidget(host(tarjeta(saluda: saluda, key: ValueKey(k))));
        return tester.getSize(find.byType(JayaloCard));
      }

      final quieta = await tamano(saluda: false, k: 'quieta');
      final saludando = await tamano(saluda: true, k: 'saludando');
      expect(saludando, quieta,
          reason: 'el grosor debe reservarse abajo, o el contenido salta 2px');
    });

    testWidgets('el saludo NO estrecha la tarjeta (ni a las que no saludan)',
        (tester) async {
      // La regresión que esto vigila fue GLOBAL y ningún test la veía: envolver
      // siempre en `Stack` hacía que su `StackFit.loose` aflojara las
      // constraints, y toda tarjeta cuyo hijo no estira por sí mismo (un
      // `Column` de textos, sin `Row(max)` ni `Expanded`) encogía contra su
      // texto — medido, 368px → 38px. Lo pagaban las 31 tarjetas de la app.
      const hijo = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('x'), Text('un poco más largo')],
      );
      // OJO con qué caja se mide: `find.byType(JayaloCard)` es el `Padding`
      // exterior, que recibe constraints AJUSTADAS del `SizedBox` y devuelve
      // 400 siempre — pasa en verde con el bug puesto (comprobado por
      // mutación). Lo que encoge es el FONDO pintado, o sea el
      // `AnimatedContainer` de dentro.
      Future<double> anchoDelFondo(
          {required bool saluda, required String k}) async {
        await tester.pumpWidget(host(SizedBox(
          width: 400,
          child: tarjeta(saluda: saluda, hijo: hijo, key: ValueKey(k)),
        )));
        return tester
            .getSize(find.descendant(
              of: find.byType(JayaloCard),
              matching: find.byType(AnimatedContainer),
            ))
            .width;
      }

      // 400 menos el margen horizontal de 16×2 de la tarjeta.
      expect(await anchoDelFondo(saluda: false, k: 'a'), 368,
          reason: 'la tarjeta quieta ocupa su ranura');
      expect(await anchoDelFondo(saluda: true, k: 'b'), 368,
          reason: 'la que saluda también: el Stack no puede aflojar el ancho');
    });

    testWidgets('cambiar de tema con una tarjeta saludando no revienta',
        (tester) async {
      // `SingleTickerProviderStateMixin` prohíbe un segundo ticker aunque el
      // primero esté disposed, y el borde es `cs.primary`, que CAMBIA al pasar
      // a oscuro → `didUpdateWidget` recrea el controlador → reventaba con
      // "multiple tickers were created". Camino bien vivo, no hipotético.
      await tester.pumpWidget(host(tarjeta(saluda: true)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(host(
        tarjeta(saluda: true, color: const Color(0xFF845EF5)),
        brightness: Brightness.dark,
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pasar a "sin ver" con la lista montada SÍ saluda',
        (tester) async {
      // `didChangeDependencies` no se vuelve a llamar en una actualización en
      // sitio, así que el controlador nuevo se quedaba en 0 para siempre: sin
      // defecto visible (borde lleno) pero sin saludo justo cuando una fila
      // PASA a estar sin ver, que es cuando más quieres que salude.
      await tester.pumpWidget(host(tarjeta(saluda: false)));
      expect(find.byKey(kPulseBorderKey), findsNothing);

      await tester.pumpWidget(host(tarjeta(saluda: true)));
      await tester.pump(const Duration(milliseconds: 16));
      var masTenue = 1.0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 80));
        final a = pulseAlpha(tester);
        if (a < masTenue) masTenue = a;
      }
      expect(masTenue, lessThan(.9),
          reason: 'el controlador nuevo tiene que arrancar, no quedarse en 0');
      await tester.pumpAndSettle();
    });

    testWidgets('con "reducir animaciones" el borde aparece lleno y quieto',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: tarjeta(saluda: true)),
        ),
      ));
      // Se apaga el MOVIMIENTO, nunca el borde: la marca es información.
      for (var i = 0; i < 20; i++) {
        expect(pulseAlpha(tester), closeTo(1, 1e-3));
        await tester.pump(const Duration(milliseconds: 250));
      }
    });

    testWidgets('sin pulseBorder no se monta la capa del saludo',
        (tester) async {
      await tester.pumpWidget(host(tarjeta(saluda: false)));
      expect(find.byKey(kPulseBorderKey), findsNothing);
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

    // El tono PAGADO lleva la MONEDA desde el 2026-08-23 (pedido PO: la moneda
    // donde se dice o se cobra "N créditos"). Sostener este botón es pagar, y
    // el símbolo de pagar es la moneda, no un candado genérico.
    testWidgets('tono pagado (default): moneda + copy de desbloqueo',
        (tester) async {
      await tester
          .pumpWidget(host(HoldToConfirmButton(onConfirmed: () async {})));
      expect(find.byType(MonedaJayalo), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing,
          reason: 'el candado se fue: lo que se sostiene es un cobro');
      expect(find.text('Mantén presionado para desbloquear'), findsOneWidget);
    });

    testWidgets('tono gratis: cotejo + copy de aceptar', (tester) async {
      await tester.pumpWidget(host(HoldToConfirmButton(
          tone: HoldToConfirmTone.free, onConfirmed: () async {})));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Mantén presionado para aceptar'), findsOneWidget);
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

  /// Cabeceras de sección con ícono vivo (PO 2026-09-04). El contrato que
  /// importa es que el ícono sea OPCIONAL: Reputación y el resto de pantallas
  /// siguen pasando solo `text` y no deben ganar una pastilla que nadie pidió.
  group('SectionHeader', () {
    testWidgets('sin glyph es el eyebrow pelado de siempre', (tester) async {
      await tester.pumpWidget(host(const SectionHeader(text: 'TU NEGOCIO')));
      await tester.pumpAndSettle();

      expect(find.text('TU NEGOCIO'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('con glyph dibuja su ícono junto al rótulo', (tester) async {
      await tester.pumpWidget(host(const SectionHeader(
          text: 'COMO COMPRADOR', glyph: SectionGlyph.bolsa)));
      await tester.pumpAndSettle();

      expect(find.text('COMO COMPRADOR'), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    });

    testWidgets('cada glyph trae su propio ícono', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        SectionHeader(text: 'A', glyph: SectionGlyph.estrella),
        SectionHeader(text: 'B', glyph: SectionGlyph.tienda),
      ])));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('pulsar el mando no rompe nada ni deja timers vivos',
        (tester) async {
      // Bajo `flutter test` el pop no arranca (mismo gotcha de
      // `conversations_screen.dart`): lo que se fija aquí es que pulsar sea
      // inofensivo, porque es puro adorno — no navega ni recarga.
      final pulse = SectionPulse();
      addTearDown(pulse.dispose);

      await tester.pumpWidget(host(SectionHeader(
          text: 'CÓMO TE CALIFICAN',
          glyph: SectionGlyph.estrella,
          pulse: pulse)));
      await tester.pumpAndSettle();

      pulse.pop();
      pulse.pop();
      await tester.pumpAndSettle();

      expect(find.text('CÓMO TE CALIFICAN'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });
  });
}
