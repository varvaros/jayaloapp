import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// Pedido PO 2026-08-03: una solicitud cuya conversación se cerró sin
/// completarse debe salir "Cerrada", apagada como la completada pero SIN el
/// violeta — el violeta es para el trato que terminó bien.
///
/// La Task 7 le añade a este fichero el grupo de widget tests de la fase
/// `closed`, con sus imports. El grupo de abajo ("cableado del swipe") es de
/// la ronda de arreglo 1: cubre las SEIS fases, no solo `closed`.
void main() {
  test('el chip dice "Cerrada", sin conteo de ofertas', () {
    final (icon, label) = phaseChip(RequestPhase.closed, 3);
    expect(label, 'Cerrada');
    expect(icon, Icons.lock_outline);
    // No es "done_all": ese es el de completada y confundirlas es justo el bug.
    expect(icon, isNot(Icons.done_all));
  });

  test('permisos: cerrada se puede borrar pero no editar', () {
    expect(blockedDeleteReasonForPhase(RequestPhase.closed), isNull);
    expect(blockedEditReasonForPhase(RequestPhase.closed), isNotNull);
  });

  test('permisos: las demás fases no cambian', () {
    for (final p in [RequestPhase.waiting, RequestPhase.withOffers]) {
      expect(blockedDeleteReasonForPhase(p), isNull);
      expect(blockedEditReasonForPhase(p), isNull);
    }
    for (final p in [
      RequestPhase.accepted,
      RequestPhase.unlocked,
      RequestPhase.completed
    ]) {
      expect(blockedDeleteReasonForPhase(p), isNotNull);
      expect(blockedEditReasonForPhase(p), isNotNull);
    }
  });

  group(
    'cableado del swipe: el assert de SwipeToActions (actions.length > 0 '
    '|| blockedReason != null) no revienta en ninguna fase',
    () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        onboardingStore.reset();
        // Las guías de esta pantalla montan un velo a pantalla completa; sin
        // esto tapa la fila (mismo patrón que my_requests_completed_card_test.dart).
        await onboardingStore.markDone('client.my_requests.v1');
        await onboardingStore.markDone('client.others_requests.v1');
      });

      Widget host(Widget child) =>
          MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

      /// `myFetch` sustituye a `_fetch` entero: una fila ya con su fase, sin
      /// Supabase.
      Future<List<(Map<String, dynamic>, RequestPhase, int)>> rowsWith(
        RequestPhase phase,
      ) async =>
          [
            (
              {
                'id': 'r1',
                'title': 'Solicitud de prueba',
                'kind': 'producto',
                'is_wholesale': false,
                'image_url': null,
                'status': 'completed',
                'created_at': DateTime.now().toIso8601String(),
              },
              phase,
              2,
            ),
          ];

      // La composición de `blocked` (franja gris) y de la lista `actions`
      // (Eliminar/Editar condicionales) es justo donde el assert de
      // SwipeToActions puede saltar en runtime si `blockedEdit`/
      // `blockedDelete` se descomponen mal — ni `flutter analyze` ni los
      // tests de función pura lo cubren. Con que la pantalla se construya
      // sin excepción ya vale: el assert ES la aserción.
      for (final phase in RequestPhase.values) {
        testWidgets(
          'fase ${phase.name}: la lista monta sin excepción',
          (tester) async {
            await tester.pumpWidget(host(MyRequestsScreen(
              myFetch: () => rowsWith(phase),
              othersFetch: () async => [],
              actions: const [],
            )));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
          },
        );
      }
    },
  );

  group('tarjeta', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      onboardingStore.reset();
      await onboardingStore.markDone('client.my_requests.v1');
      await onboardingStore.markDone('client.others_requests.v1');
    });

    Widget host(Widget child) =>
        MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

    Future<List<(Map<String, dynamic>, RequestPhase, int)>> rows() async => [
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
            RequestPhase.closed,
            2,
          ),
        ];

    testWidgets('cerrada: gris de fase terminada y SIN banda violeta',
        (tester) async {
      await tester.pumpWidget(host(MyRequestsScreen(
        myFetch: rows,
        othersFetch: () async => [],
        actions: const [],
      )));
      await tester.pumpAndSettle();

      final card = tester.widget<JayaloCard>(find
          .ancestor(
            of: find.text('Mesa de caoba'),
            matching: find.byType(JayaloCard),
          )
          .first);
      expect(card.tint, JayaloStatus.completedLight.bg);
      expect(find.text('Cerrada'), findsOneWidget);
      // La banda violeta es SOLO de la completada: el violeta significa que el
      // trato terminó bien, y este no terminó — se apagó.
      expect(find.text('Completado'), findsNothing);
    });
  });
}
