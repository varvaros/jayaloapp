import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/phase.dart';
import 'package:jayalo_app/features/client/request_detail_sheet.dart';

/// El PO reportó (2026-08-02, captura de device) que en el detalle de su
/// solicitud la primera línea del título aparece cortada por el borde inferior
/// de la foto. La hipótesis del spec es que la causa es el panel de alto FIJO:
/// la lista scrollea y su contenido se recorta contra él.
///
/// Este test reproduce la estructura actual para confirmarlo. Si pasa, la
/// hipótesis es falsa y hay que investigar de nuevo.
void main() {
  final request = <String, dynamic>{
    'id': 'req-1',
    'user_id': 'user-1',
    'title': 'Teclado Inalámbrico Klip Xtreme con receptor USB y teclado numérico',
    'bullets': <String>['Marca: Klip Xtreme'],
    'created_at': DateTime.now().toIso8601String(),
    'status': 'open',
    'is_wholesale': false,
    'budget_min': null,
    'budget_max': null,
    'image_urls': <String>[],
  };

  /// Réplica de la estructura ACTUAL: panel de alto fijo + hoja en un Expanded.
  Widget hostActual() => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              Container(height: 300, color: const Color(0xFFF0C48C)),
              Expanded(
                child: RequestDetailSheet(
                  request: request,
                  phase: RequestPhase.withOffers,
                  offers: const [],
                  unreadCount: 0,
                  onSeeOffers: () {},
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('HIPÓTESIS: al scrollear, el título queda recortado por el panel fijo',
      (tester) async {
    await tester.pumpWidget(hostActual());
    await tester.pumpAndSettle();

    final titulo = find.text(request['title'] as String);
    expect(titulo, findsOneWidget);

    // Arriba del todo el título se ve entero, por debajo del panel.
    final antes = tester.getRect(titulo);
    expect(antes.top, greaterThanOrEqualTo(300.0),
        reason: 'en reposo el título debe empezar por debajo del panel');

    // Scrollear la lista hacia arriba.
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    final despues = tester.getRect(titulo);

    // Confirmamos que el drag de verdad movió la lista: si no se moviera,
    // este test no probaría nada.
    expect(despues.top, isNot(equals(antes.top)),
        reason: 'el drag debe haber scrolleado la lista; si no se movió, '
            'el test no está probando nada');

    // Si el título sube por encima del borde inferior del panel, está siendo
    // tapado: eso es el recorte que reportó el PO.
    expect(despues.top, lessThan(300.0),
        reason: 'HIPÓTESIS CONFIRMADA si el título se mete bajo el panel fijo');
  });
}
