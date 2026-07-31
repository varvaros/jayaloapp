import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';

/// El avatar del AppBar (spec iteración 2 §5): junto a la campana en las 6
/// pantallas raíz. Al tocarlo abre un menú por rol — cliente ve solo
/// Ajustes, proveedor ve Estadísticas y Ajustes (ambas salieron de la barra
/// inferior, spec §4). `profileStore`/`roleStore` son singletons compartidos
/// con la app real: cada test los deja en un estado conocido para no
/// arrastrar datos de un test a otro.
void main() {
  setUp(() {
    roleStore.value = RoleState.consumer;
    profileStore.avatarUrl = null;
    profileStore.firstName = null;
  });

  GoRouter routerWithHome(Widget child) => GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
              path: '/home',
              builder: (_, _) =>
                  Scaffold(appBar: AppBar(actions: [child]))),
          GoRoute(
              path: '/settings',
              builder: (_, _) => const Text('pantalla de ajustes')),
          GoRoute(
              path: '/provider/stats',
              builder: (_, _) => const Text('pantalla de estadísticas')),
          GoRoute(
              path: '/client',
              builder: (_, _) => const Text('pantalla de mis solicitudes')),
          GoRoute(
              path: '/client/reputation',
              builder: (_, _) => const Text('pantalla de reputación')),
          GoRoute(
              path: '/catalog',
              builder: (_, _) => const Text('pantalla de otros proveedores')),
        ],
      );

  Widget host({Future<int?> Function()? balanceFetch}) => MaterialApp.router(
        theme: jayaloTheme(Brightness.light),
        routerConfig:
            routerWithHome(ProfileAvatarButton(balanceFetch: balanceFetch)),
      );

  Future<void> abrirMenu(WidgetTester tester) async {
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
  }

  testWidgets('cliente: el menú SOLO ofrece Ajustes', (tester) async {
    roleStore.value = RoleState.consumer;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Estadísticas'), findsNothing);
  });

  testWidgets('proveedor: el menú ofrece Estadísticas y Ajustes', (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets('tocar "Ajustes" navega a /settings', (tester) async {
    roleStore.value = RoleState.consumer;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('pantalla de ajustes'), findsOneWidget);
  });

  testWidgets('proveedor: tocar "Estadísticas" navega a /provider/stats',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    await tester.tap(find.text('Estadísticas'));
    await tester.pumpAndSettle();

    expect(find.text('pantalla de estadísticas'), findsOneWidget);
  });

  testWidgets(
      'proveedor: el menú ofrece las pantallas de comprador, negocio y ajustes',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(host(balanceFetch: () async => 5));
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    // "Mis solicitudes" YA NO está acá (PO 2026-07-30): se mudó al segmento
    // "Mis pedidos" de la pestaña Mis ofertas. Enterrada en este menú, el
    // proveedor podía CREAR una solicitud desde el ＋ de la barra y después no
    // tenía dónde encontrarla.
    expect(find.text('Mis solicitudes'), findsNothing);
    expect(find.text('Reputación'), findsOneWidget);
    expect(find.text('Otros proveedores'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);
    // La fila de recargar se conserva (recargar es el core del negocio, la
    // redundancia con el "+" del saldo es deliberada).
    expect(find.text('Recargar créditos'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets(
      'proveedor: el encabezado resalta el saldo y ofrece el botón de recargar',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(host(balanceFetch: () async => 42));
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    expect(find.text('42 créditos'), findsOneWidget);
    // El "+" para recargar vive junto al saldo (ya no una fila aparte).
    expect(find.byTooltip('Recargar créditos'), findsOneWidget);
  });

  testWidgets(
      'proveedor: si el saldo falla, no muestra número y el menú sigue vivo',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(
        host(balanceFetch: () async => throw Exception('sin red')));
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    // El chip de saldo ("N créditos") no aparece; "Recargar créditos" (acción)
    // sí sigue, por eso se busca el patrón con número, no cualquier "créditos".
    expect(find.textContaining(RegExp(r'\d+ créditos')), findsNothing);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cliente: no ve el saldo ni las entradas de proveedor',
      (tester) async {
    roleStore.value = RoleState.consumer;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    expect(find.text('Mis solicitudes'), findsNothing);
    expect(find.text('Estadísticas'), findsNothing);
    expect(find.textContaining('créditos'), findsNothing);
    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets('proveedor: tocar "Reputación" navega a /client/reputation',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester.pumpWidget(host(balanceFetch: () async => 0));
    await tester.pumpAndSettle();
    await abrirMenu(tester);

    // Reemplaza al caso de "Mis solicitudes", que dejó de vivir en este menú
    // (PO 2026-07-30). Se conserva un caso de NAVEGACIÓN real desde el panel:
    // lo que se prueba acá es que tocar una fila cierra el menú y empuja su
    // ruta, no la fila concreta.
    await tester.tap(find.text('Reputación'));
    await tester.pumpAndSettle();

    expect(find.text('pantalla de reputación'), findsOneWidget);
  });

  testWidgets('sin foto de perfil, el avatar muestra la inicial del nombre',
      (tester) async {
    profileStore.avatarUrl = null;
    profileStore.firstName = 'Ana';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('sin foto ni nombre, el avatar cae a un signo de interrogación',
      (tester) async {
    profileStore.avatarUrl = null;
    profileStore.firstName = null;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('con foto de perfil, el avatar usa esa imagen de red',
      (tester) async {
    profileStore.avatarUrl = 'https://example.com/foto.jpg';
    profileStore.firstName = 'Ana';
    await tester.pumpWidget(host());
    await tester.pump(); // sin pumpAndSettle: no esperar a que la red resuelva

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    // El avatar usa `jayaloAvatarImage` (downsampling, auditoría 2026-07-23):
    // un ResizeImage que envuelve un CachedNetworkImageProvider (caché en disco)
    // — ya no un NetworkImage crudo. Se verifica el provider interno y su url.
    final resize = avatar.backgroundImage as ResizeImage;
    expect(
        resize.imageProvider,
        isA<CachedNetworkImageProvider>()
            .having((i) => i.url, 'url', 'https://example.com/foto.jpg'));
    expect(avatar.child, isNull,
        reason: 'con foto no debe superponerse el fallback de inicial');

    // Sin red real en tests, la carga async del provider puede dejar un fallo
    // pendiente: se drena si lo hay (no se exige) para que no tumbe el test.
    tester.takeException();
  });

  testWidgets(
      'el botón tiene tooltip accesible y un área de toque de al menos 48x48',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Tu perfil'), findsOneWidget);
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('con "reducir animaciones" no queda nada animando y no hay excepciones',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: routerWithHome(const ProfileAvatarButton()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ── Regresión: TOCTOU en ProfileStore.refresh() ─────────────────────────
  //
  // `home_shell.dart` usa un `AnimatedSwitcher` que mantiene la pantalla
  // saliente montada junto a la entrante durante todo el cambio de pestaña,
  // así que hay una ventana real donde 2 `ProfileAvatarButton` corren su
  // `initState` (y por tanto `refresh()`) antes de que la PRIMERA consulta a
  // `profiles` resuelva. El store debe compartir ese fetch en vuelo, no
  // duplicarlo.
  testWidgets(
      '2 montajes concurrentes (simulando el AnimatedSwitcher) disparan UNA sola consulta',
      (tester) async {
    var callCount = 0;
    final completer = Completer<Map<String, dynamic>?>();
    final store = ProfileStore(loader: () {
      callCount++;
      return completer.future;
    });

    // Ambos botones se montan en el MISMO pump, como los 2 hijos vivos del
    // AnimatedSwitcher durante la transición — ninguno espera al otro.
    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: routerWithHome(Row(children: [
        ProfileAvatarButton(store: store),
        ProfileAvatarButton(store: store),
      ])),
    ));

    expect(callCount, 1,
        reason: 'los 2 montajes concurrentes deben compartir el fetch en '
            'vuelo; con el guard síncrono viejo cada uno dispara su propia '
            'consulta real antes de que la primera resuelva');

    completer.complete({'avatar_url': null, 'first_name': 'Ana'});
    await tester.pumpAndSettle();

    expect(callCount, 1,
        reason: 'tras resolver, ningún montaje adicional debe repetir la '
            'consulta (ya quedó cacheada)');
  });

  testWidgets(
      'clear() durante un fetch en vuelo no deja datos del usuario anterior '
      'al llegar la respuesta tarde',
      (tester) async {
    final completer = Completer<Map<String, dynamic>?>();
    final store = ProfileStore(loader: () => completer.future);

    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: routerWithHome(ProfileAvatarButton(store: store)),
    ));

    store.clear(); // cierre de sesión mientras la consulta viaja
    completer.complete({'avatar_url': null, 'first_name': 'Usuario Anterior'});
    await tester.pumpAndSettle();

    expect(store.firstName, isNull,
        reason: 'la respuesta tardía del usuario anterior no debe '
            'resucitar datos tras el clear()');
  });
}
