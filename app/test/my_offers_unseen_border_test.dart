import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/my_offers_screen.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';
import 'package:jayalo_app/data/repos.dart' show kOfferUpdateKinds;

/// Pedido PO 2026-08-21: en Mis ofertas (proveedor) el borde de la tarjeta
/// marca lo NUEVO, no el estado. O sea: aparece mientras la notificación
/// `offer_accepted` siga sin leer y SE QUITA al tocar la tarjeta. Antes era
/// permanente (`status == 'accepted' || 'completed'`), así que no había forma
/// de quitárselo de encima. Y va a 1 px, no a 2: "50% más sutil".
void main() {
  // La guía 'wallet.credits.v1' monta un velo a pantalla completa que
  // intercepta los taps — mismo patrón que `my_offers_history_navigation_test`.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('wallet.credits.v1');
  });

  const titulo = 'Necesito un plomero';

  Map<String, dynamic> offer({
    required String id,
    required String requestId,
    required String status,
    DateTime? unlockedAt,
  }) => {
    'id': id,
    'request_id': requestId,
    'request_title': titulo,
    'status': status,
    'unlocked_at': unlockedAt?.toIso8601String(),
    'created_at': DateTime.now().toIso8601String(),
  };

  /// El borde CONFIGURADO en la tarjeta que contiene el título. Se lee del
  /// `AnimatedContainer` de dentro y no de la `JayaloCard`: esa es el `Padding`
  /// exterior, que no pinta nada (gotcha de medición 2026-08-19).
  Border? bordeDe(WidgetTester tester) {
    final card = find.ancestor(
      of: find.text(titulo),
      matching: find.byType(JayaloCard),
    );
    final cont = tester.widget<AnimatedContainer>(
      find.descendant(of: card, matching: find.byType(AnimatedContainer)).first,
    );
    return (cont.decoration as BoxDecoration?)?.border as Border?;
  }

  /// Doble del backend: el conjunto de "sin ver" vive acá y `markSeen` lo
  /// vacía, igual que el UPDATE de `read_at` hace en producción.
  ({
    List<String> marcadas,
    Future<Set<String>> Function() fetch,
    Future<void> Function(String) mark,
  }) fakeUnseen(Set<String> inicial) {
    final sinVer = {...inicial};
    final marcadas = <String>[];
    return (
      marcadas: marcadas,
      fetch: () async => {...sinVer},
      mark: (String id) async {
        marcadas.add(id);
        sinVer.remove(id);
      },
    );
  }

  ({GoRouter router, List<String> idsVisitados}) buildRouter(Widget home) {
    final idsVisitados = <String>[];
    final router = GoRouter(
      initialLocation: '/offers',
      routes: [
        GoRoute(path: '/offers', builder: (_, _) => home),
        GoRoute(
          path: '/provider/request/:id',
          builder: (_, s) {
            idsVisitados.add(s.pathParameters['id']!);
            return Scaffold(body: Text('detalle ${s.pathParameters['id']}'));
          },
        ),
      ],
    );
    return (router: router, idsVisitados: idsVisitados);
  }

  Future<void> pump(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(MaterialApp.router(
      theme: jayaloTheme(Brightness.light),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
  }

  MyOffersScreen pantalla({
    required List<Map<String, dynamic>> offers,
    required Future<Set<String>> Function() fetchUnseen,
    required Future<void> Function(String) markSeen,
  }) =>
      MyOffersScreen(
        fetchOffers: () async => offers,
        fetchBalance: () async => 10,
        fetchReviewed: (_) async => {},
        fetchUnseen: fetchUnseen,
        markSeen: markSeen,
        leading: const SizedBox.shrink(),
        actions: const [],
      );

  /// Cae en el HISTORIAL → la pinta `_offerCard`.
  Map<String, dynamic> aceptadaDesbloqueada() => offer(
        id: 'o-1',
        requestId: 'req-1',
        status: 'accepted',
        unlockedAt: DateTime(2026, 8, 1),
      );

  /// Cae en la sección "¡Te aceptaron!" → la pinta `_acceptedCard`, que es OTRA
  /// tarjeta con OTRO borde. Sin un caso propio, mutar `_acceptedCard` a 2 px
  /// dejaba los tests en verde: el falso verde de medir la caja equivocada.
  Map<String, dynamic> aceptadaSinDesbloquear() =>
      offer(id: 'o-1', requestId: 'req-1', status: 'accepted');

  testWidgets('una oferta ACEPTADA SIN VER lleva borde', (tester) async {
    final fake = fakeUnseen({'o-1'});
    final built = buildRouter(pantalla(
      offers: [aceptadaDesbloqueada()],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);

    expect(bordeDe(tester), isNotNull);
  });

  testWidgets('la misma oferta YA VISTA no lleva borde', (tester) async {
    final fake = fakeUnseen(const {});
    final built = buildRouter(pantalla(
      offers: [aceptadaDesbloqueada()],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);

    expect(bordeDe(tester), isNull);
  });

  testWidgets('una COMPLETADA ya vista tampoco lleva borde', (tester) async {
    final fake = fakeUnseen(const {});
    final built = buildRouter(pantalla(
      offers: [offer(id: 'o-c', requestId: 'req-c', status: 'completed')],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);

    expect(bordeDe(tester), isNull);
  });

  testWidgets('el borde mide 1 px (50% más sutil que los 2 px de antes)',
      (tester) async {
    final fake = fakeUnseen({'o-1'});
    final built = buildRouter(pantalla(
      offers: [aceptadaDesbloqueada()],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);

    expect(bordeDe(tester)!.top.width, 1);
  });

  group('sección "¡Te aceptaron!" (`_acceptedCard`, la otra tarjeta)', () {
    testWidgets('sin ver lleva borde, y mide 1 px', (tester) async {
      final fake = fakeUnseen({'o-1'});
      final built = buildRouter(pantalla(
        offers: [aceptadaSinDesbloquear()],
        fetchUnseen: fake.fetch,
        markSeen: fake.mark,
      ));
      await pump(tester, built.router);

      // El botón "Conversar · N créditos" solo lo pinta `_acceptedCard`: sin
      // este ancla estaríamos midiendo `_offerCard` otra vez, que es
      // exactamente el falso verde que dejó pasar los 2 px.
      expect(find.textContaining('Conversar'), findsOneWidget);
      expect(bordeDe(tester)!.top.width, 1);
    });

    testWidgets('ya vista no lleva borde', (tester) async {
      final fake = fakeUnseen(const {});
      final built = buildRouter(pantalla(
        offers: [aceptadaSinDesbloquear()],
        fetchUnseen: fake.fetch,
        markSeen: fake.mark,
      ));
      await pump(tester, built.router);

      expect(find.textContaining('Conversar'), findsOneWidget);
      expect(bordeDe(tester), isNull);
    });
  });

  testWidgets('TOCAR la tarjeta marca la oferta vista y le quita el borde',
      (tester) async {
    final fake = fakeUnseen({'o-c'});
    final built = buildRouter(pantalla(
      offers: [offer(id: 'o-c', requestId: 'req-c', status: 'completed')],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);
    expect(bordeDe(tester), isNotNull, reason: 'sin ver = con borde');

    await tester.tap(find.text(titulo));
    await tester.pumpAndSettle();
    expect(built.idsVisitados, ['req-c'], reason: 'sigue navegando al detalle');
    expect(fake.marcadas, ['o-c'], reason: 'la marcó leída en el servidor');

    // Volver atrás: la lista se recarga y la oferta ya NO debe traer borde.
    built.router.pop();
    await tester.pumpAndSettle();
    expect(bordeDe(tester), isNull, reason: 'el borde se quitó al tocarla');
  });

  testWidgets(
      'volver ANTES de que el servidor registre la lectura no revive el borde',
      (tester) async {
    // Servidor lento a propósito: `markSeen` se llama pero `fetch` sigue
    // devolviendo la oferta como NO vista, igual que si el UPDATE de `read_at`
    // aún no hubiera llegado. Volver de inmediato es un gesto normal, y sin la
    // resta de `_yaVistas` el borde reaparecía justo aquí.
    final marcadas = <String>[];
    final built = buildRouter(pantalla(
      offers: [offer(id: 'o-c', requestId: 'req-c', status: 'completed')],
      fetchUnseen: () async => {'o-c'},
      markSeen: (id) async => marcadas.add(id),
    ));
    await pump(tester, built.router);
    expect(bordeDe(tester), isNotNull);

    await tester.tap(find.text(titulo));
    await tester.pumpAndSettle();
    built.router.pop();
    await tester.pumpAndSettle();

    expect(marcadas, ['o-c']);
    expect(bordeDe(tester), isNull,
        reason: 'el borde no puede resucitar por una carrera con el servidor');
  });

  testWidgets('tocar una oferta YA VISTA no vuelve a marcarla', (tester) async {
    final fake = fakeUnseen(const {});
    final built = buildRouter(pantalla(
      offers: [offer(id: 'o-c', requestId: 'req-c', status: 'completed')],
      fetchUnseen: fake.fetch,
      markSeen: fake.mark,
    ));
    await pump(tester, built.router);

    await tester.tap(find.text(titulo));
    await tester.pumpAndSettle();
    expect(fake.marcadas, isEmpty);
  });

  group('que cuenta como "sin ver" en una oferta', () {
    test('NO es solo la aceptacion: cualquier actualizacion cuenta', () {
      // Regla del PO 2026-08-22: «si una oferta tiene una actualizacion que no
      // has abierto, cuenta». Al principio el borde miraba SOLO
      // `offer_accepted`, asi que un rechazo o una cancelacion del cliente
      // pasaban mudos. Este test existe para que nadie lo vuelva a estrechar
      // sin darse cuenta.
      expect(kOfferUpdateKinds, contains('offer_accepted'));
      expect(kOfferUpdateKinds, contains('offer_rejected'));
      expect(kOfferUpdateKinds, contains('offer_cancelled_customer'));
      expect(kOfferUpdateKinds.length, greaterThan(1),
          reason: 'un solo kind es justo el bug que esto vigila');
    });
  });
}
