import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Contrato del botón central "prestado": dentro de crear solicitud navegar es
/// un no-op, así que la pantalla se apropia del ＋ y lo vuelve una cámara.
void main() {
  final dests = destinationsFor(RoleState.consumer);

  tearDown(() {
    centerAction.value = null;
    centerActionIcon.value = null;
  });

  group('store', () {
    test('tomar y soltar deja el centro como estaba', () {
      void action() {}
      expect(centerAction.value, isNull);

      takeCenterAction(action, Icons.photo_camera_outlined);
      expect(centerAction.value, same(action));
      expect(centerActionIcon.value, Icons.photo_camera_outlined);

      releaseCenterAction(action);
      expect(centerAction.value, isNull);
      expect(centerActionIcon.value, isNull);
    });

    test(
        'soltar con una acción AJENA no roba el botón: el dispose de la pantalla '
        'saliente corre DESPUÉS del initState de la entrante', () {
      void saliente() {}
      void entrante() {}

      takeCenterAction(saliente, Icons.photo_camera_outlined);
      // La pantalla nueva se monta y toma el botón…
      takeCenterAction(entrante, Icons.photo_camera_outlined);
      // …y recién ahí la vieja se destruye y suelta LO SUYO.
      releaseCenterAction(saliente);

      expect(centerAction.value, same(entrante),
          reason: 'la acción de la pantalla al frente debe sobrevivir');
      expect(centerActionIcon.value, isNotNull);
    });
  });

  group('barra', () {
    Widget host({IconData? icon, String? label, VoidCallback? onCenter}) =>
        MaterialApp(
          theme: jayaloTheme(Brightness.light),
          home: Scaffold(
            bottomNavigationBar: FloatingNavBar(
              destinations: dests,
              currentIndex: kCenterIndex,
              centerIconOverride: icon,
              centerLabelOverride: label,
              onSelected: (i) {
                if (i == kCenterIndex) onCenter?.call();
              },
            ),
          ),
        );

    testWidgets('sin override el centro sigue siendo el ＋ de siempre',
        (tester) async {
      await tester.pumpWidget(host());
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
      expect(find.text(dests[kCenterIndex].label), findsOneWidget);
    });

    testWidgets('con override se pinta la cámara y su etiqueta', (tester) async {
      await tester.pumpWidget(
          host(icon: Icons.photo_camera_outlined, label: 'Añadir foto'));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Añadir foto'), findsOneWidget);
      expect(find.text(dests[kCenterIndex].label), findsNothing);
    });

    testWidgets('tocarlo avisa por onSelected con el índice del centro',
        (tester) async {
      var toques = 0;
      await tester.pumpWidget(host(
        icon: Icons.photo_camera_outlined,
        label: 'Añadir foto',
        onCenter: () => toques++,
      ));
      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pump();
      expect(toques, 1);
    });
  });
}
