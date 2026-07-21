import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/request_success_view.dart';
import 'package:jayalo_app/features/shared/celebration.dart' show ConfettiBurst;
import 'package:jayalo_app/features/shared/jayalo_loader.dart';

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
    // La mascota celebra en BUCLE (por diseño, ronda 3): no se puede usar
    // pumpAndSettle aquí — basta avanzar más allá del confeti (1.8s) y
    // verificar que la pantalla sigue viva sin excepciones.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(JayaloMascotFace), findsOneWidget);
  });
}
