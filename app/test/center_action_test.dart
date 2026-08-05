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
    centerActionOwner.value = null;
    centerActionRoute.value = null;
    centerActionLabel.value = null;
    centerActionMenu.value = null;
  });

  group('store', () {
    test('tomar y soltar deja el centro como estaba', () {
      void action() {}
      expect(centerAction.value, isNull);

      takeCenterAction(owner: action, icon: Icons.photo_camera_outlined, action: action);
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

      takeCenterAction(owner: saliente, icon: Icons.photo_camera_outlined, action: saliente);
      // La pantalla nueva se monta y toma el botón…
      takeCenterAction(owner: entrante, icon: Icons.photo_camera_outlined, action: entrante);
      // …y recién ahí la vieja se destruye y suelta LO SUYO.
      releaseCenterAction(saliente);

      expect(centerAction.value, same(entrante),
          reason: 'la acción de la pantalla al frente debe sobrevivir');
      expect(centerActionIcon.value, isNotNull);
    });

    test('un menú se registra y se suelta por su DUEÑO, no por su acción', () {
      final owner = Object();
      void nada() {}
      final menu = [
        CenterMenuItem(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: nada),
        CenterMenuItem(icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: nada),
      ];

      takeCenterAction(
        owner: owner,
        icon: Icons.library_add_outlined,
        label: 'Cargar',
        route: '/provider/request/abc',
        menu: menu,
      );

      expect(centerActionOwner.value, same(owner));
      expect(centerActionMenu.value, menu);
      expect(centerActionLabel.value, 'Cargar');
      expect(centerActionRoute.value, '/provider/request/abc');
      expect(centerAction.value, isNull, reason: 'un menú no tiene acción directa');

      releaseCenterAction(owner);
      expect(centerActionOwner.value, isNull);
      expect(centerActionMenu.value, isNull);
      expect(centerActionLabel.value, isNull);
      expect(centerActionRoute.value, isNull);
      expect(centerActionIcon.value, isNull);
    });

    test('soltar con un dueño AJENO no roba el botón', () {
      final saliente = Object();
      final entrante = Object();
      void nada() {}
      final menu = [
        CenterMenuItem(icon: Icons.storefront_outlined, label: 'Mi tienda', onTap: nada),
      ];

      takeCenterAction(owner: saliente, icon: Icons.library_add_outlined, menu: menu);
      takeCenterAction(owner: entrante, icon: Icons.library_add_outlined, menu: menu);
      releaseCenterAction(saliente);

      expect(centerActionOwner.value, same(entrante),
          reason: 'el dueño al frente debe sobrevivir al dispose del saliente');
      expect(centerActionMenu.value, isNotNull);
    });

    test('reasignar un menú EQUIVALENTE no notifica (el formulario se '
        'reconstruye con cada tecla del campo de precio)', () {
      final owner = Object();
      void nada() {}
      List<CenterMenuItem> build({required bool enabled}) => [
            CenterMenuItem(
                icon: Icons.photo_camera_outlined,
                label: 'Cámara',
                onTap: nada,
                enabled: enabled),
          ];

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: true));

      var avisos = 0;
      void contar() => avisos++;
      centerActionMenu.addListener(contar);
      addTearDown(() => centerActionMenu.removeListener(contar));

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: true));
      expect(avisos, 0, reason: 'misma lista por VALOR: no debe repintar la barra');

      takeCenterAction(owner: owner, icon: Icons.library_add_outlined, menu: build(enabled: false));
      expect(avisos, 1, reason: 'cambió `enabled`: eso SÍ tiene que repintarse');
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
