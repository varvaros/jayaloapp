import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/client/request_detail_sheet.dart';
import 'package:jayalo_app/features/shared/buscando_indicator.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-09-18: una solicitud en «esperando» se percibía DETENIDA —
/// píldora quieta, verbo en pasiva. Pasa a decir «Buscando proveedores» con un
/// reloj en avance rápido y tres puntos que rebotan.
///
/// Lo que de verdad protege esta batería no es el copy (eso es un literal):
/// es que el PRIMER BUCLE PERPETUO de la app no cuelgue los tests ni se cuele
/// en fases que deben estar quietas.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    // Las guías de esta pantalla montan un velo a pantalla completa que
    // taparía la tarjeta (mismo patrón que `my_requests_others_test.dart`).
    await onboardingStore.markDone('client.home_tour.v1');
  });

  Widget host(Widget child, {bool sinAnimaciones = false}) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: sinAnimaciones
            ? MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: child,
              )
            : child,
      );

  Future<List<(Map<String, dynamic>, RequestPhase, int, ClosedReason?)>> filas(
    RequestPhase phase,
  ) async =>
      [
        (
          {
            'id': 'r1',
            'title': 'Mesa de caoba',
            'kind': 'producto',
            'is_wholesale': false,
            'image_url': null,
            'status': 'open',
            'created_at': DateTime.now().toIso8601String(),
          },
          phase,
          phase == RequestPhase.waiting ? 0 : 2,
          null,
        ),
      ];

  Widget lista(RequestPhase phase) => MyRequestsScreen(
        myFetch: () => filas(phase),
        othersFetch: () async => [],
        actions: const [],
      );

  Map<String, dynamic> solicitud() => <String, dynamic>{
        'id': 'req-1',
        'user_id': 'user-1',
        'title': 'Teclado inalámbrico',
        'bullets': <String>[],
        'created_at': DateTime.now().toIso8601String(),
        'status': 'open',
        'is_wholesale': false,
        'image_urls': <String>[],
      };

  Widget detalle(RequestPhase phase) => Scaffold(
        body: RequestDetailSheet(
          request: solicitud(),
          phase: phase,
          offers: const [],
        ),
      );

  group('copy de la fase', () {
    test('el chip de «esperando» dice que se está BUSCANDO, no esperando', () {
      expect(phaseChip(RequestPhase.waiting, 0).$2, buscandoProveedoresCopy);
      expect(buscandoProveedoresCopy, 'Buscando proveedores');
    });

    test('el ícono de la tupla NO cambia: no es el del chip', () {
      // `request_status_screen.dart` usa este `.$1` como `fallbackIcon` del
      // panel de foto cuando la solicitud no tiene imágenes. Ese glifo tiene
      // que seguir siendo estático — el movimiento vive en el chip, que se
      // pinta aparte con `BuscandoIndicator`.
      expect(phaseChip(RequestPhase.waiting, 0).$1, Icons.schedule);
    });
  });

  group('en la lista de «Mis solicitudes»', () {
    testWidgets('la tarjeta en espera se mueve y dice «Buscando proveedores»',
        (tester) async {
      await tester.pumpWidget(host(lista(RequestPhase.waiting)));
      await tester.pumpAndSettle();

      expect(find.text(buscandoProveedoresCopy), findsOneWidget);
      // Dos: el chip de la tarjeta y la píldora del riel de progreso.
      expect(find.byType(BuscandoIndicator), findsNWidgets(2));
      // El riel conserva su etiqueta de hito; no se vuelve «Buscando».
      expect(find.text('Esperando'), findsOneWidget);
    });

    testWidgets('una fase que YA pasó no se mueve', (tester) async {
      // El movimiento significa "esto sigue corriendo". Con ofertas ya hay un
      // hecho consumado que contar, y un hecho no se anima.
      await tester.pumpWidget(host(lista(RequestPhase.withOffers)));
      await tester.pumpAndSettle();

      expect(find.byType(BuscandoIndicator), findsNothing);
      expect(find.text('2 ofertas'), findsOneWidget);
    });

    testWidgets('con «reducir animaciones» el texto sigue entero',
        (tester) async {
      await tester.pumpWidget(
        host(lista(RequestPhase.waiting), sinAnimaciones: true),
      );
      await tester.pumpAndSettle();

      // El rebote es el adorno; la palabra es la información. Apagar el
      // movimiento no puede quitar lo segundo.
      expect(find.text(buscandoProveedoresCopy), findsOneWidget);
      expect(find.byType(BuscandoIndicator), findsNWidgets(2));
    });
  });

  group('en el detalle', () {
    testWidgets('la misma fase se mueve también aquí', (tester) async {
      await tester.pumpWidget(host(detalle(RequestPhase.waiting)));
      await tester.pumpAndSettle();

      // Si la lista se moviera y esta hoja no, el cliente vería dos estados
      // distintos para una sola solicitud.
      expect(find.byType(BuscandoIndicator), findsOneWidget);
      // «Buscando» a secas en el chip (ancho: comparte fila con el título de
      // 22pt) y la frase completa abajo, en el cuerpo de ESTADO.
      expect(find.text('Buscando'), findsOneWidget);
      expect(
        find.text(
          'Tu solicitud está publicada y estamos buscando proveedores que '
          'respondan.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con ofertas el chip queda quieto', (tester) async {
      await tester.pumpWidget(host(detalle(RequestPhase.withOffers)));
      await tester.pumpAndSettle();

      expect(find.byType(BuscandoIndicator), findsNothing);
      expect(find.text('Con ofertas'), findsOneWidget);
    });
  });

  group('el bucle no se escapa', () {
    // ESTE es el test que importa. `BuscandoIndicator` es la primera
    // animación en bucle de la app; sin el guardia `FLUTTER_TEST` un ticker
    // en `repeat()` deja `pumpAndSettle()` girando hasta el timeout y toda la
    // batería que monte esta pantalla muere con "Pending timers".
    //
    // Cubre los DOS dueños posibles del ticker: el controlador compartido de
    // `_MyRequestsScreenState` (lista) y el propio del widget (hoja suelta).
    testWidgets('la lista en espera termina de asentarse', (tester) async {
      await tester.pumpWidget(host(lista(RequestPhase.waiting)));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('la hoja del detalle en espera termina de asentarse',
        (tester) async {
      await tester.pumpWidget(host(detalle(RequestPhase.waiting)));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
