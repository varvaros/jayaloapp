import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/features/shell/center_arc_menu.dart';

void main() {
  group('geometría', () {
    test('los cuatro satélites quedan por ENCIMA del centro y simétricos', () {
      final p = arcOffsets(4, kArcRadius);
      expect(p, hasLength(4));
      for (final o in p) {
        expect(o.dy, lessThan(0), reason: 'el arco se abre hacia arriba');
        expect(o.distance, closeTo(kArcRadius, 0.01));
      }
      // Simetría respecto del eje vertical: el primero y el último son espejo.
      expect(p.first.dx, closeTo(-p.last.dx, 0.01));
      // Y sus ETIQUETAS no se solapan — que es la cuenta que de verdad manda,
      // no la de los círculos. Este test es lo que ata el radio al arco: bajar
      // uno sin subir el otro lo pone rojo.
      for (var i = 1; i < p.length; i++) {
        expect((p[i] - p[i - 1]).distance, greaterThan(kSatelliteSlot));
      }
    });

    test('a distancia 0 todos nacen dentro del centro', () {
      for (final o in arcOffsets(4, 0)) {
        expect(o.distance, closeTo(0, 0.01));
      }
    });
  });

  group('widget', () {
    late List<String> elegidos;

    List<CenterMenuItem> items({
      bool tiendaViva = true,
      VoidCallback? onTiendaDisabledTap,
    }) => [
      CenterMenuItem(
        icon: Icons.photo_camera_outlined,
        label: 'Cámara',
        onTap: () {},
      ),
      CenterMenuItem(
        icon: Icons.photo_library_outlined,
        label: 'Galería',
        onTap: () {},
      ),
      CenterMenuItem(
        icon: Icons.storefront_outlined,
        label: 'Mi tienda',
        onTap: () {},
        enabled: tiendaViva,
        onDisabledTap: onTiendaDisabledTap,
      ),
      CenterMenuItem(
        icon: Icons.collections_bookmark_outlined,
        label: 'Trabajos',
        onTap: () {},
      ),
    ];

    Widget host(List<CenterMenuItem> its) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: CenterArcMenu(
            animation: const AlwaysStoppedAnimation(1),
            items: its,
            centerRadius: 28,
            onPick: (it) => elegidos.add(it.label),
          ),
        ),
      ),
    );

    setUp(() => elegidos = []);

    testWidgets('pinta los cuatro íconos y sus cuatro etiquetas', (
      tester,
    ) async {
      await tester.pumpWidget(host(items()));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Mi tienda'), findsOneWidget);
      expect(find.text('Trabajos'), findsOneWidget);
    });

    testWidgets(
      'con el arco abierto, el propio overlay pinta su ✕ — el blob central '
      'tapa la del botón real que queda debajo',
      (tester) async {
        await tester.pumpWidget(host(items()));
        expect(
          find.descendant(
            of: find.byType(CenterArcMenu),
            matching: find.byIcon(Icons.close),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('abierta del todo, la ✕ NO queda a 45° — ahí se vería como un ＋', (
      tester,
    ) async {
      // Lo cazó el smoke en device (2026-08-06): el giro estaba pensado para un
      // ＋ (＋ girado 45° = ✕), pero el glifo TAMBIÉN se cambió a `Icons.close`.
      // Dos transformaciones que dicen "conviértelo en equis" se cancelan y el
      // usuario ve un ＋. Ningún test lo veía: todos afirmaban el TOKEN del
      // icono, que era correcto, no el ángulo con que se pinta.
      // Un cuarto de vuelta sí vale: la ✕ es simétrica a 90°, así que el giro
      // se conserva y el estado final es una ✕ de verdad.
      await tester.pumpWidget(host(items()));
      final giro = tester.widget<RotationTransition>(
        find
            .ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(RotationTransition),
            )
            .first,
      );
      final vueltas = giro.turns.value;
      expect(
        (vueltas * 4) % 1,
        closeTo(0, 0.001),
        reason:
            'con la animación al final el giro debe ser múltiplo de 90°, '
            'no de 45°: a 45° la ✕ se ve como un ＋ (vueltas=$vueltas)',
      );
    });

    testWidgets('elegir uno avisa por onPick', (tester) async {
      await tester.pumpWidget(host(items()));
      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await tester.pump();
      expect(elegidos, ['Mi tienda']);
    });

    testWidgets('deshabilitado CON onDisabledTap: lo dispara, y NO cuenta como '
        'elección (no llama a onPick, así que el arco no se cierra)', (
      tester,
    ) async {
      var avisos = 0;
      await tester.pumpWidget(
        host(items(tiendaViva: false, onTiendaDisabledTap: () => avisos++)),
      );
      await tester.tap(find.byIcon(Icons.storefront_outlined));
      await tester.pump();
      expect(avisos, 1);
      expect(
        elegidos,
        isEmpty,
        reason: 'avisar por qué no es lo mismo que elegir',
      );
    });

    testWidgets(
      'deshabilitado SIN onDisabledTap: el toque queda inerte (apagado '
      'por una operación en curso, no hay nada que avisar)',
      (tester) async {
        await tester.pumpWidget(host(items(tiendaViva: false)));
        await tester.tap(find.byIcon(Icons.storefront_outlined));
        await tester.pump();
        expect(elegidos, isEmpty);
      },
    );

    testWidgets('con la animación en 0 no hay nada tocable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CenterArcMenu(
                animation: const AlwaysStoppedAnimation(0),
                items: items(),
                centerRadius: 28,
                onPick: (it) => elegidos.add(it.label),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byIcon(Icons.storefront_outlined),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        elegidos,
        isEmpty,
        reason: 'cerrado, los satélites están dentro del centro',
      );
    });
  });
}
