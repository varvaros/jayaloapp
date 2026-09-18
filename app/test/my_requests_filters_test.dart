import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/my_requests_screen.dart';
import 'package:jayalo_app/features/shared/onboarding_store.dart';

/// El riel de filtros de «Mis solicitudes» (PO 2026-09-18): UNA sola línea con
/// tres píldoras excluyentes. «Activas» desapareció —«Mis solicitudes» ya
/// significa eso— y «Terminadas» subió a esa misma línea.
///
/// Y la tarjeta de muestra del estado vacío, que el PO vio desviada del diseño
/// vivo, ahora se construye con la tarjeta REAL: aquí se fija por lo que solo
/// la real pinta (el riel de fases).
void main() {
  // Las guías de esta pantalla montan un velo a pantalla completa que
  // intercepta los taps: marcarlas vistas evita que se coma los toques a las
  // píldoras.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onboardingStore.reset();
    await onboardingStore.markDone('client.home_tour.v1');
  });

  Widget screen({bool embedded = false}) => MaterialApp(
    theme: jayaloTheme(Brightness.light),
    home: MyRequestsScreen(
      actions: const [],
      embedded: embedded,
      myFetch: () async => [],
      othersFetch: () async => [],
    ),
  );

  /// El color del texto de una píldora dice si está seleccionada: blanca
  /// sobre violeta, tinta apagada cuando no.
  bool seleccionada(WidgetTester t, String label) =>
      t.widget<Text>(find.text(label)).style?.color == Colors.white;

  /// La fila que contiene las píldoras de filtro.
  Finder riel() =>
      find.ancestor(of: find.text('Mis solicitudes'), matching: find.byType(Wrap)).first;

  testWidgets('«Activas» ya no existe y los tres filtros van en UNA fila', (
    t,
  ) async {
    await t.pumpWidget(screen());
    await t.pumpAndSettle();

    expect(find.text('Activas'), findsNothing);
    expect(
      find.descendant(of: riel(), matching: find.text('Todas las solicitudes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: riel(), matching: find.text('Terminadas')),
      findsOneWidget,
    );
    // Abre en las propias activas.
    expect(seleccionada(t, 'Mis solicitudes'), isTrue);
    expect(seleccionada(t, 'Terminadas'), isFalse);
  });

  testWidgets('tocar «Terminadas» APAGA «Mis solicitudes»', (t) async {
    await t.pumpWidget(screen());
    await t.pumpAndSettle();

    await t.tap(find.text('Terminadas'));
    await t.pumpAndSettle();

    // El defecto que este riel viene a quitar: con `!_others` a secas la
    // píldora de las activas se quedaba encendida sobre las terminadas.
    expect(seleccionada(t, 'Mis solicitudes'), isFalse);
    expect(seleccionada(t, 'Terminadas'), isTrue);
  });

  testWidgets('los tres son excluyentes: de «Todas» se vuelve a las propias', (
    t,
  ) async {
    await t.pumpWidget(screen());
    await t.pumpAndSettle();

    await t.tap(find.text('Todas las solicitudes'));
    await t.pumpAndSettle();
    expect(seleccionada(t, 'Todas las solicitudes'), isTrue);
    expect(seleccionada(t, 'Mis solicitudes'), isFalse);
    expect(seleccionada(t, 'Terminadas'), isFalse);

    await t.tap(find.text('Terminadas'));
    await t.pumpAndSettle();
    expect(seleccionada(t, 'Terminadas'), isTrue);
    expect(seleccionada(t, 'Todas las solicitudes'), isFalse);

    await t.tap(find.text('Mis solicitudes'));
    await t.pumpAndSettle();
    expect(seleccionada(t, 'Mis solicitudes'), isTrue);
    expect(seleccionada(t, 'Terminadas'), isFalse);
  });

  testWidgets('incrustada conserva «Terminadas» aunque no lleve «Todas»', (
    t,
  ) async {
    // Un proveedor mirando «Mis pedidos»: el segmentado de la pantalla
    // anfitriona ya hace de «Todas», pero sin «Terminadas» se quedaría sin
    // manera de ver sus solicitudes terminadas.
    await t.pumpWidget(screen(embedded: true));
    await t.pumpAndSettle();

    expect(find.text('Todas las solicitudes'), findsNothing);
    expect(find.text('Activas'), findsNothing);
    await t.tap(find.text('Terminadas'));
    await t.pumpAndSettle();
    expect(seleccionada(t, 'Terminadas'), isTrue);
  });

  testWidgets('la tarjeta de ejemplo es la tarjeta REAL, con su riel de fases', (
    t,
  ) async {
    await t.pumpWidget(screen());
    await t.pumpAndSettle();

    expect(find.text('Ejemplo'), findsOneWidget);
    expect(find.text('Nevera 11 pies, poco uso'), findsOneWidget);
    // Lo que la muestra vieja NO tenía y la tarjeta real sí: el riel de fases
    // con su paso actual, y el chevrón de la fila.
    expect(find.text('Ofertas'), findsOneWidget);
    expect(find.text('3 ofertas'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
