import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/notifications/notification_bell.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';
import 'package:jayalo_app/features/provider/my_business_screen.dart'
    show CatalogCard;
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';
import 'package:jayalo_app/features/shell/back_guard.dart';

/// El contrato de Estadísticas.
///
/// Task 4 (2026-07-18): el catálogo (productos/servicios) y "trabajos
/// realizados" SALIERON hacia "Mi negocio" (`/provider/business`) —
/// decisión PO verbatim: "lo movemos aquí". Esta suite verifica la MUDANZA,
/// no solo la llegada: Estadísticas ya no debe mostrar ninguna de las dos.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  const conActividad = {
    'clients_count': 8,
    'completed_count': 12,
    'points_invested': 45,
    'revenue_total': 128500,
    'avg_rating': 4.8,
    'reviews_count': 9,
  };

  testWidgets('muestra clientes, facturado y créditos invertidos',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('RD\$128,500'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
  });

  testWidgets('calificación y reseñas quedan como dos métricas separadas',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('calificación'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.textContaining('reseñas'), findsOneWidget);
  });

  testWidgets(
      'ya NO muestra el catálogo ni trabajos realizados (se movieron a Mi negocio)',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogCard), findsNothing);
    expect(find.textContaining('LO QUE OFRECES'), findsNothing);
    expect(find.textContaining('productos'), findsNothing);
    expect(find.textContaining('servicios'), findsNothing);
    expect(find.textContaining('trabajos realizados'), findsNothing);
    // El 12 de completed_count no debe colarse en ningún tile visible.
    expect(find.text('12'), findsNothing);
  });

  testWidgets('sin trabajos completados ni reseñas muestra el estado vacío',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
  });

  // ── M1 (revisión final de rama) ─────────────────────────────────────────
  //
  // `/provider/stats` SALIÓ del mapa de la barra (Task 8, vive en
  // `_excludedFromNav`) y se llega por `context.push` desde el menú del
  // avatar — es un detalle/menú, no una pestaña raíz, así que no debe
  // repetir campana+avatar (su propio menú de avatar ofrecería "Estadísticas"
  // navegando a donde ya se está). Mismo patrón que `/catalog/:id` y
  // `/client/request/:id`.
  //
  // Antes de quitarlas había que VERIFICAR que el usuario pueda volver: esta
  // pantalla vive DENTRO del `ShellRoute` y `BackGuard` intercepta todo pop
  // (ver `back_guard.dart`) para decidir `BackAction.goHome` en vez de un
  // pop silencioso. El router real monta `StatsScreen` así:
  // `GoRoute(path: '/provider/stats', builder: (_, _) =>
  // const BackGuard(child: StatsScreen()))`, reproducido aquí con un stub de
  // `/provider` como home del rol.
  GoRouter routerConPush() => GoRouter(
        initialLocation: '/provider',
        routes: [
          ShellRoute(
            builder: (_, _, child) => child,
            routes: [
              GoRoute(
                  path: '/provider',
                  builder: (_, _) =>
                      const BackGuard(child: Text('bandeja de proveedor'))),
              GoRoute(
                  path: '/provider/stats',
                  builder: (_, _) => const BackGuard(child: StatsScreen())),
            ],
          ),
        ],
      );

  testWidgets(
      'Estadísticas NO muestra campana ni avatar (ya no es pestaña raíz)',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester
        .pumpWidget(MaterialApp.router(routerConfig: routerConPush()));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('bandeja de proveedor'));
    GoRouter.of(ctx).push('/provider/stats');
    await tester.pumpAndSettle();

    expect(find.text('Mis estadísticas'), findsOneWidget);
    expect(find.byType(NotificationBell), findsNothing);
    expect(find.byType(ProfileAvatarButton), findsNothing);
  });

  testWidgets(
      'Estadísticas conserva una salida real: el back (flecha automática / '
      'atrás del sistema) saca al proveedor, no lo deja atrapado',
      (tester) async {
    roleStore.value = RoleState.provider;
    await tester
        .pumpWidget(MaterialApp.router(routerConfig: routerConPush()));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('bandeja de proveedor'));
    GoRouter.of(ctx).push('/provider/stats');
    await tester.pumpAndSettle();
    expect(find.text('Mis estadísticas'), findsOneWidget);

    // `tester.pageBack()` busca la flecha automática del AppBar (tooltip
    // 'Back', la que Flutter dibuja solo porque `Navigator.canPop()` es
    // true tras el push) y la toca — el mismo camino que un dedo real, y
    // también el que dispara el ATRÁS del sistema vía `BackGuard`.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('bandeja de proveedor'), findsOneWidget,
        reason: 'BackGuard debe resolver BackAction.goHome para esta '
            'ubicación (≠ homePath) y sacar al proveedor, no dejarlo '
            'atrapado en Estadísticas');
    expect(find.text('Mis estadísticas'), findsNothing);
  });
}
