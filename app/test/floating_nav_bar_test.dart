import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Ratio de contraste WCAG entre dos colores (fórmula estándar sobre la
/// luminancia relativa que ya calcula `Color.computeLuminance()`).
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Contrato de la barra, no sus píxeles. Lo importante: que solo el activo
/// lleve texto (decisión PO — limpia como la referencia pero el usuario
/// siempre lee dónde está), que TODOS anuncien su nombre a un lector de
/// pantalla, y que el botón central pueda estar activo.
void main() {
  final dests = destinationsFor(RoleState.provider);

  Widget host(int index, {void Function(int)? onSelected, bool reduced = false}) =>
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            bottomNavigationBar: FloatingNavBar(
              destinations: dests,
              currentIndex: index,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );

  /// Igual que [host] pero con el brillo elegido — para probar el color de
  /// la barra en claro y en oscuro (iteración 2: tinte violeta).
  Widget hostBrightness(int index, Brightness brightness) => MaterialApp(
        theme: jayaloTheme(brightness),
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            destinations: dests,
            currentIndex: index,
            onSelected: (_) {},
          ),
        ),
      );

  Icon iconFor(WidgetTester tester, String label) => tester.widget<Icon>(
      find.descendant(
          of: find.bySemanticsLabel(label), matching: find.byType(Icon)));

  testWidgets('solo el destino activo muestra su texto', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(find.text('Solicitudes'), findsOneWidget);
    expect(find.text('Mis ofertas'), findsNothing);
    expect(find.text('Mensajes'), findsNothing);
    expect(find.text('Mi negocio'), findsNothing);
  });

  testWidgets('el texto se mueve al cambiar de destino', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(3));
    await tester.pumpAndSettle();
    expect(find.text('Solicitudes'), findsNothing);
    expect(find.text('Mensajes'), findsOneWidget);
  });

  testWidgets('el botón central también puede estar activo y llevar su texto',
      (tester) async {
    await tester.pumpWidget(host(kCenterIndex));
    await tester.pumpAndSettle();
    expect(find.text('Crear solicitud'), findsOneWidget);
  });

  testWidgets('todos los destinos se anuncian a un lector de pantalla',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    for (final d in dests) {
      expect(find.bySemanticsLabel(d.label), findsOneWidget, reason: d.label);
    }
    handle.dispose();
  });

  testWidgets('tocar un destino avisa con su índice', (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Mi negocio'));
    await tester.pumpAndSettle();
    expect(tocados, [4]);
  });

  testWidgets('tocar el botón central avisa con el índice del centro',
      (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Crear solicitud'));
    await tester.pumpAndSettle();
    expect(tocados, [kCenterIndex]);
  });

  testWidgets('con reducir animaciones no queda nada animando',
      (tester) async {
    await tester.pumpWidget(host(0, reduced: true));
    await tester.pump();
    // Si algo siguiera animando, pumpAndSettle agotaría su presupuesto.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'el nodo de semántica de un destino lateral y el del centro exponen '
      'la acción de tap (esto es lo que activa el doble-tap de un lector '
      'de pantalla; tester.tap() no lo hubiera cazado porque hace hit-test '
      'por coordenadas, no pasa por SemanticsAction)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();

    final lateral = tester
        .getSemantics(find.bySemanticsLabel('Mi negocio'))
        .getSemanticsData();
    expect(lateral.hasAction(SemanticsAction.tap), isTrue,
        reason: 'Mi negocio debe exponer la acción de tap, no solo el label');

    final centro = tester
        .getSemantics(find.bySemanticsLabel('Crear solicitud'))
        .getSemanticsData();
    expect(centro.hasAction(SemanticsAction.tap), isTrue,
        reason:
            'Crear solicitud debe exponer la acción de tap, no solo el label');

    handle.dispose();
  });

  testWidgets(
      'con currentIndex -1 (I2: ninguna pestaña coincide con la ruta, p. ej. '
      '/notifications) no queda nada teñido de primary ni ninguna etiqueta '
      'visible', (tester) async {
    await tester.pumpWidget(host(-1));
    await tester.pumpAndSettle();

    // Ninguno de los 5 destinos muestra su etiqueta: si alguno estuviera
    // "activo" por error, su texto aparecería (regla del PO: el texto solo
    // se ve en el destino activo).
    for (final d in dests) {
      expect(find.text(d.label), findsNothing, reason: d.label);
    }

    // Ningún ícono queda teñido de primary — ni los laterales (_SideItem,
    // que en claro usan onPrimaryContainer/opacidad, iteración 2) ni el
    // círculo central (_CenterButton, cuyo fondo en claro es
    // onPrimaryContainer, no primary; su texto de abajo solo aparece si
    // `active`). Este host es siempre en claro (ver [host]).
    final cs = Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
    final iconos = tester.widgetList<Icon>(find.descendant(
        of: find.byType(FloatingNavBar), matching: find.byType(Icon)));
    for (final icono in iconos) {
      // El ícono del círculo central es cs.onPrimary, no cs.primary: no
      // cuenta como "teñido de primary" en el sentido de la regla lateral.
      expect(icono.color, isNot(cs.primary),
          reason: 'ningún ícono debe quedar teñido de primary sin una '
              'pestaña activa');
    }
  });

  testWidgets(
      'kNavBarReservedSpace cubre el alto real que ocupa la barra al renderizarse',
      (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(FloatingNavBar));
    expect(kNavBarReservedSpace, greaterThanOrEqualTo(size.height),
        reason:
            'kNavBarReservedSpace ($kNavBarReservedSpace) se quedó corto '
            'frente al alto real (${size.height})');
  });

  group('color (iteración 2 — tinte violeta, spec §2)', () {
    // Iteración 2 (spec §3): la píldora dejó de ser un `Container` con
    // `BoxDecoration` — ahora es un `CustomPaint` (`PillNotchPainter`) para
    // poder tallar la muesca cóncava. El punto de verdad del color pasa a
    // ser el campo `color` del painter, no `BoxDecoration.color`; la
    // aserción es la misma (debe seguir viniendo de `cs.primaryContainer`),
    // solo cambia DÓNDE se lee.
    PillNotchPainter pillPainter(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byType(FloatingNavBar), matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<PillNotchPainter>()
        .single;

    testWidgets('la píldora se tiñe con primaryContainer en claro',
        (tester) async {
      await tester.pumpWidget(hostBrightness(0, Brightness.light));
      await tester.pumpAndSettle();
      final cs =
          Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
      final painter = pillPainter(tester);
      expect(painter.color, cs.primaryContainer);
      expect(cs.primaryContainer, JayaloColors.accent,
          reason: 'primaryContainer debe seguir siendo el token accent del '
              'spec §2 en claro');
    });

    testWidgets('la píldora se tiñe con primaryContainer en oscuro',
        (tester) async {
      await tester.pumpWidget(hostBrightness(0, Brightness.dark));
      await tester.pumpAndSettle();
      final cs =
          Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
      final painter = pillPainter(tester);
      expect(painter.color, cs.primaryContainer);
      expect(cs.primaryContainer, JayaloColors.dAccent,
          reason: 'primaryContainer debe seguir siendo el token dAccent del '
              'spec §2 en oscuro');
    });

    testWidgets(
        'el destino lateral activo usa onPrimaryContainer (violeta oscuro) '
        'en claro y dForeground en oscuro', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(hostBrightness(0, brightness));
        await tester.pumpAndSettle();
        final cs = Theme.of(tester.element(find.byType(FloatingNavBar)))
            .colorScheme;
        final icon = iconFor(tester, 'Solicitudes');
        expect(icon.color, cs.onPrimaryContainer,
            reason: 'brillo: $brightness');
      }
    });

    testWidgets(
        'el destino lateral inactivo en claro es el mismo tono atenuado '
        '(onPrimaryContainer con opacidad reducida), no otro color',
        (tester) async {
      await tester.pumpWidget(hostBrightness(0, Brightness.light));
      await tester.pumpAndSettle();
      final cs =
          Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
      final icon = iconFor(tester, 'Mis ofertas'); // índice 1, inactivo
      expect(icon.color, isNot(cs.onPrimaryContainer));
      expect((icon.color as Color).withValues(alpha: 1.0), cs.onPrimaryContainer,
          reason: 'el inactivo debe ser el MISMO tono que el activo, solo '
              'con opacidad reducida — nunca un color distinto');
    });

    testWidgets(
        'el destino lateral inactivo en oscuro usa onSurfaceVariant '
        '(dMutedFg), tal como especifica la tabla del spec §2',
        (tester) async {
      await tester.pumpWidget(hostBrightness(0, Brightness.dark));
      await tester.pumpAndSettle();
      final cs =
          Theme.of(tester.element(find.byType(FloatingNavBar))).colorScheme;
      final icon = iconFor(tester, 'Mis ofertas'); // índice 1, inactivo
      expect(icon.color, cs.onSurfaceVariant);
      expect(cs.onSurfaceVariant, JayaloColors.dMutedFg);
    });

    testWidgets(
        'el círculo central usa onPrimaryContainer (accentFg) en claro y '
        'primary (dPrimary) en oscuro', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(hostBrightness(kCenterIndex, brightness));
        await tester.pumpAndSettle();
        final cs = Theme.of(tester.element(find.byType(FloatingNavBar)))
            .colorScheme;
        final circle = tester
            .widgetList<Material>(find.descendant(
                of: find.bySemanticsLabel('Crear solicitud'),
                matching: find.byType(Material)))
            .firstWhere((m) => m.shape is CircleBorder);
        final expected =
            brightness == Brightness.dark ? cs.primary : cs.onPrimaryContainer;
        expect(circle.color, expected, reason: 'brillo: $brightness');
      }
    });

    testWidgets('el ícono dentro del círculo sigue siendo onPrimary',
        (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(hostBrightness(kCenterIndex, brightness));
        await tester.pumpAndSettle();
        final cs = Theme.of(tester.element(find.byType(FloatingNavBar)))
            .colorScheme;
        final icon = iconFor(tester, 'Crear solicitud');
        expect(icon.color, cs.onPrimary, reason: 'brillo: $brightness');
      }
    });

    test(
        'el inactivo en claro cumple el mínimo WCAG de contraste no-textual '
        '(3:1, SC 1.4.11) sobre el fondo teñido — solo se pinta el ícono, '
        'la etiqueta nunca se muestra en estado inactivo', () {
      final cs = jayaloScheme(Brightness.light);
      final inactive = cs.onPrimaryContainer.withValues(alpha: 0.6);
      final blended = Color.alphaBlend(inactive, cs.primaryContainer);
      final ratio = _contrastRatio(blended, cs.primaryContainer);
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'ratio real: $ratio — ver cálculo en task-1-report.md');
    });

    test(
        'el inactivo en oscuro (onSurfaceVariant/dMutedFg) también cumple '
        'el mínimo WCAG de 3:1 sobre el nuevo fondo teñido (dAccent)', () {
      final cs = jayaloScheme(Brightness.dark);
      final ratio = _contrastRatio(cs.onSurfaceVariant, cs.primaryContainer);
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'ratio real: $ratio — ver cálculo en task-1-report.md');
    });
  });

  group('muesca cóncava (iteración 2 — spec §3)', () {
    // Geometría pura: no hace falta montar ningún widget. Parámetros propios
    // (no los de la barra real) elegidos para que los puntos "de al lado"
    // queden lejos de la muesca Y lejos de las esquinas totalmente
    // redondeadas del estadio (que también recortan el interior cerca de
    // y=0 en los extremos).
    const size = Size(400, 60);
    const centerX = 200.0; // size.width / 2
    const sideOffset = 120.0; // 80 y 320: lejos de la muesca y de las puntas
    const shallowY = 2.0; // muy cerca del borde superior

    test(
        'con radio de muesca > 0, el centro del borde superior queda FUERA '
        'del path mientras los puntos equivalentes de los lados quedan '
        'DENTRO (concavidad real, no una píldora recta)', () {
      final path = buildPillNotchPath(
        size: size,
        notchCenterX: centerX,
        notchCenterY: 0,
        notchRadius: 24,
      );

      expect(path.contains(const Offset(centerX, shallowY)), isFalse,
          reason: 'el centro del borde superior debe estar mordido por la '
              'muesca que abraza al botón');
      expect(
          path.contains(const Offset(centerX - sideOffset, shallowY)), isTrue,
          reason: 'a los lados, lejos de la muesca, el borde debe seguir '
              'lleno (sin curvatura)');
      expect(
          path.contains(const Offset(centerX + sideOffset, shallowY)), isTrue,
          reason: 'a los lados, lejos de la muesca, el borde debe seguir '
              'lleno (sin curvatura)');
    });

    test(
        'sin muesca (radio 0) los tres puntos del borde superior quedan '
        'DENTRO — confirma que la exclusión de arriba la causa la muesca y '
        'no otra cosa (p. ej. redondeo de las puntas)', () {
      final path = buildPillNotchPath(
        size: size,
        notchCenterX: centerX,
        notchCenterY: 0,
        notchRadius: 0,
      );

      expect(path.contains(const Offset(centerX, shallowY)), isTrue);
      expect(
          path.contains(const Offset(centerX - sideOffset, shallowY)), isTrue);
      expect(
          path.contains(const Offset(centerX + sideOffset, shallowY)), isTrue);
    });

    testWidgets(
        'la barra real (host de destinos del proveedor) también dibuja su '
        'píldora con un CustomPaint (PillNotchPainter), no un Container '
        'rectangular', (tester) async {
      await tester.pumpWidget(hostBrightness(0, Brightness.light));
      await tester.pumpAndSettle();
      final painters = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(CustomPaint)))
          .map((w) => w.painter)
          .whereType<PillNotchPainter>();
      expect(painters, hasLength(1));
    });

    testWidgets(
        'en un ancho de teléfono angosto real (390dp) la barra se renderiza '
        'sin excepciones — la muesca usa raíces cuadradas (misma fórmula que '
        'CircularNotchedRectangle) y un ancho angosto es el caso donde esas '
        'cuentas podrían romperse', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(hostBrightness(0, Brightness.light));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FloatingNavBar), findsOneWidget);
    });
  });
}
