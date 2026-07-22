import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: jayaloTheme(Brightness.light), home: child);

  final others = [
    {
      'id': 'o1',
      'title': 'Busco 50 sillas plegables',
      'kind': 'producto',
      'is_wholesale': false,
      'image_url': null,
      'created_at': DateTime.now().toIso8601String(),
    },
  ];

  testWidgets('el toggle De otros muestra el feed ajeno inyectado',
      (tester) async {
    await tester.pumpWidget(host(
      MyRequestsScreen(
        // `myFetch: []` evita que el tab inicial "Mías" toque la red en el test.
        myFetch: () async => [],
        othersFetch: () async => others,
        // `HeaderBell` (default) toca `notifCountStore`, que accede a `supa`
        // sin try/catch en su constructor y revienta sin Supabase
        // inicializado — mismo patrón usado en catalog_screen_test.dart.
        actions: const [],
      ),
    ));
    await tester.pumpAndSettle();

    // Cambiar al segmento "De otros".
    await tester.tap(find.text('De otros'));
    await tester.pumpAndSettle();

    expect(find.text('Busco 50 sillas plegables'), findsOneWidget);
  });
}
