import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/notifications/notification_bell.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';
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
    // 1-10: era 4.8, de cuando la app pintaba estas notas sobre 5.
    'avg_rating': 8.6,
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
    // Con la escala pegada: la métrica es sobre 10, no sobre 5.
    expect(find.text('8.6/10'), findsOneWidget);
    expect(find.text('calificación'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.textContaining('reseñas'), findsOneWidget);
  });

  testWidgets(
      'ya NO muestra el catálogo ni trabajos realizados (se movieron a Mi negocio)',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
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

  // ── "COMO COMPRADOR" (PO 2026-09-04) ────────────────────────────────────
  //
  // El proveedor perdió el ítem "Reputación" de su menú del avatar: los cinco
  // datos que vivían SOLO en `/client/reputation` (una pantalla de CLIENTE)
  // son ahora esta sección. El cliente conserva su pantalla intacta.
  //
  // `buyer` va ANIDADO porque `get_customer_reputation` repite los nombres
  // `avg_rating`/`reviews_count` de la nota del negocio — ver
  // `mergeProviderStats` en `repos_test.dart`.
  const comprador = {
    'requests_count': 12,
    'completed_purchases': 7,
    'avg_rating': 9.2,
    'reviews_count': 5,
    'median_response_minutes': 45,
    'response_samples': 11,
  };
  const conAmbos = {...conActividad, 'buyer': comprador};

  /// Con las dos secciones de negocio arriba, la sección de comprador cae
  /// DEBAJO del pliegue de los 600px del test — y un `ListView` ni siquiera
  /// construye lo que no se ve, así que un `expect` a secas da "0 widgets"
  /// tanto si el dato falta como si solo hay que bajar. Estas pruebas bajan de
  /// verdad, igual que un dedo.
  Future<void> bajarHasta(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('la sección COMO COMPRADOR enseña compras y solicitudes',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conAmbos)));
    await tester.pumpAndSettle();

    expect(find.text('COMO COMPRADOR'), findsOneWidget);
    await bajarHasta(tester, find.text('compras completadas'));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('solicitudes hechas'), findsOneWidget);
  });

  testWidgets('la nota de comprador convive con la del negocio sin pisarla',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conAmbos)));
    await tester.pumpAndSettle();

    // Dos notas distintas, de dos tablas distintas, en la misma pantalla.
    expect(find.text('8.6/10'), findsOneWidget); // business_reviews
    expect(find.text('9.2/10'), findsOneWidget); // customer_reviews
    // Y dos etiquetas DISTINTAS: dos "calificación" con números distintos se
    // leerían como un error de la app.
    expect(find.text('calificación'), findsOneWidget);
    expect(find.text('te califican'), findsOneWidget);
  });

  testWidgets('con muestras suficientes aparece el tiempo de respuesta',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conAmbos)));
    await tester.pumpAndSettle();
    await bajarHasta(tester, find.textContaining('Regularmente respondes'));
    expect(find.text('Regularmente respondes en 45 minutos'), findsOneWidget);
  });

  testWidgets('con menos de 5 muestras el tiempo de respuesta se calla',
      (tester) async {
    // Sin el spread: en un mapa CONST, `{...comprador, 'response_samples': 4}`
    // es clave duplicada en tiempo de compilación, no una sobrescritura.
    await tester.pumpWidget(host(const StatsView(data: {
      ...conActividad,
      'buyer': {
        'requests_count': 12,
        'completed_purchases': 7,
        'avg_rating': 9.2,
        'reviews_count': 5,
        'median_response_minutes': 45,
        'response_samples': 4,
      },
    })));
    await tester.pumpAndSettle();
    // Bajar HASTA EL FINAL primero: si no, la frase "no aparece" simplemente
    // porque su tarjeta nunca se construyó, y el test pasaría aunque el
    // umbral estuviera roto.
    await bajarHasta(tester, find.text('solicitudes hechas'));

    expect(find.textContaining('Regularmente respondes'), findsNothing);
    // El resto de la sección sigue ahí: el umbral calla UNA frase, no todo.
    expect(find.text('7'), findsOneWidget);
    expect(find.text('solicitudes hechas'), findsOneWidget);
  });

  testWidgets('sin actividad de comprador, la sección no se dibuja',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: conActividad)));
    await tester.pumpAndSettle();
    expect(find.text('COMO COMPRADOR'), findsNothing);
  });

  testWidgets(
      'negocio vacío pero con compras: NO corta la pantalla, avisa y enseña '
      'la sección de comprador', (tester) async {
    // La regresión que este caso blinda: con el gate viejo
    // (`completed == 0 && reviews == 0`) un proveedor que todavía no ha
    // vendido caía en el estado vacío — y como ya no tiene el ítem del menú,
    // no vería JAMÁS sus datos de comprador.
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
      'buyer': comprador,
    })));
    await tester.pumpAndSettle();

    expect(find.text('COMO COMPRADOR'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // El aviso sustituye a las dos secciones de negocio, que no se dibujan.
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
    expect(find.text('CÓMO TE CALIFICAN'), findsNothing);
    expect(find.text('TU NEGOCIO'), findsNothing);
  });

  testWidgets('ninguno de los dos lados con datos: estado vacío de siempre',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
      'buyer': {
        'requests_count': 0,
        'completed_purchases': 0,
        'avg_rating': 0,
        'reviews_count': 0,
        'response_samples': 0,
      },
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
    expect(find.text('COMO COMPRADOR'), findsNothing);
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

    // El header de detalle (violeta) trae su propio botón de atrás
    // (`HeaderCircleButton` con la flecha) que hace `context.pop()` — la
    // salida real de la pantalla, el mismo camino que un dedo real.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('bandeja de proveedor'), findsOneWidget,
        reason: 'BackGuard debe resolver BackAction.goHome para esta '
            'ubicación (≠ homePath) y sacar al proveedor, no dejarlo '
            'atrapado en Estadísticas');
    expect(find.text('Mis estadísticas'), findsNothing);
  });
}
