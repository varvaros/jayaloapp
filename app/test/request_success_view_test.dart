import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/request_success_view.dart';

/// Contrato del éxito al publicar (spec solicitud-gamificada): mensaje claro
/// de que la solicitud quedó publicada, confeti de una sola pasada y un botón
/// que lleva a la lista — el reemplazo del SnackBar que la navbar tapaba.
void main() {
  testWidgets('muestra la celebración y el CTA dispara el callback',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
          body: RequestPublishedView(onSeeRequests: () => taps++)),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('¡Tu solicitud está publicada!'), findsOneWidget);
    expect(
        find.text('Los proveedores empezarán a enviarte ofertas.'), findsOneWidget);
    expect(find.byType(ConfettiBurst), findsOneWidget);
    await tester.tap(find.text('Ver mis solicitudes'));
    expect(taps, 1);
    // El confeti es de una pasada: al terminar no queda nada animando.
    await tester.pumpAndSettle();
  });
}
