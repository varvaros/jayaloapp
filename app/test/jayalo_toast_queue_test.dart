import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';

/// Reporte del PO (2026-08-18): al descartar solicitudes en la bandeja, el
/// aviso «Solicitud descartada.» no se va — ni tocándolo ni cambiando de
/// pantalla.
///
/// Hipótesis: `showJayaloToast` hacía `hideCurrentSnackBar()`, que retira el
/// actual y DESTAPA el siguiente de la cola. N descartes seguidos = N avisos
/// encadenados de 4 s cada uno, y como el `ScaffoldMessenger` es el de la raíz
/// de `MaterialApp`, la cadena sobrevive a la navegación.
///
/// Este test fija el comportamiento correcto: el último aviso GANA y la
/// pantalla queda limpia pasada una sola duración.
void main() {
  Future<void> pumpHost(WidgetTester tester, void Function(BuildContext) onTap) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('disparar'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('un aviso solo: desaparece pasada su duración', (tester) async {
    await pumpHost(tester, (c) => showJayaloToast(c, 'Solicitud descartada.'));
    await tester.tap(find.text('disparar'));
    await tester.pump();
    expect(find.text('Solicitud descartada.'), findsOneWidget);

    // OJO con el bombeo: el temporizador de 4 s de SnackBar no arranca hasta
    // que la animación de ENTRADA termina. Un solo `pump(5s)` produce un único
    // frame, la entrada se completa ahí y el reloj empieza en ese instante —
    // el aviso seguiría en pantalla y parecería un bug del código.
    await tester.pump(const Duration(milliseconds: 400)); // entra
    await tester.pump(const Duration(seconds: 5));        // vive y caduca
    await tester.pumpAndSettle();                          // sale
    expect(find.text('Solicitud descartada.'), findsNothing);
  });

  testWidgets('cinco descartes seguidos NO encadenan cinco avisos',
      (tester) async {
    var n = 0;
    await pumpHost(tester, (c) => showJayaloToast(c, 'Descartada ${++n}'));

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('disparar'));
      await tester.pump();
    }

    // Solo el último está en pantalla: los anteriores no se quedaron en cola.
    expect(find.text('Descartada 5'), findsOneWidget);
    for (final prev in ['Descartada 1', 'Descartada 2', 'Descartada 3',
        'Descartada 4']) {
      expect(find.text(prev), findsNothing, reason: prev);
    }

    // Y pasada UNA duración no queda nada. (Medido: `hideCurrentSnackBar`
    // retira el anterior de verdad, NO lo encola — la hipótesis inicial de
    // avisos encadenados resultó falsa. Este test queda como reja.)
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Descartada'), findsNothing);
  });

  testWidgets('el aviso se puede cerrar tocándolo', (tester) async {
    await pumpHost(tester, (c) => showJayaloToast(c, 'Solicitud descartada.'));
    await tester.tap(find.text('disparar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Solicitud descartada.'), findsOneWidget);

    await tester.tap(find.text('Solicitud descartada.'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud descartada.'), findsNothing);
  });
}
