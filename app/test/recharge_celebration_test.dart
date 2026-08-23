import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/recharge_celebration.dart';

/// Contrato de la celebración de recarga (mockup B aprobado por el PO
/// 2026-08-23). Entra DESPUÉS del vuelo de monedas al contador, así que aquí
/// no hay espera: al abrirse ya trae el saldo nuevo, la frase y su salida.
///
/// No se auto-cierra —a diferencia de aceptar/desbloquear— porque su botón
/// LLEVA a algún sitio: cerrarla sola le robaría el destino al proveedor.
///
/// No fija píxeles de la lluvia ni del confeti; fija lo que dice y por dónde
/// se sale.
void main() {
  const clave = ValueKey('celebration-recharge');

  Widget host(
    void Function(BuildContext) onTap, {
    bool reducirAnimaciones = false,
  }) =>
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducirAnimaciones),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: ElevatedButton(
                onPressed: () => onTap(c),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  Future<void> abrir(
    WidgetTester tester, {
    int? agregados = 50,
    int saldo = 150,
    void Function(Future<bool?>)? capturar,
    bool reducirAnimaciones = false,
  }) async {
    await tester.pumpWidget(host(
      (c) {
        final f = showRechargeCelebration(c, agregados: agregados, saldo: saldo);
        capturar?.call(f);
      },
      reducirAnimaciones: reducirAnimaciones,
    ));
    await tester.tap(find.text('go'));
    await tester.pump(); // dispara la ruta
    await tester.pumpAndSettle(); // baja el panel y entra el contenido
  }

  testWidgets('canta el saldo nuevo, el título y su salida', (tester) async {
    await abrir(tester);

    expect(find.byKey(clave), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('¡Ya estás listo!'), findsOneWidget);
    expect(find.text('Buscar clientes'), findsOneWidget);
  });

  testWidgets('la píldora dorada dice cuántos créditos acaba de comprar',
      (tester) async {
    await abrir(tester, agregados: 100, saldo: 260);

    expect(find.text('+100 CRÉDITOS'), findsOneWidget);
    expect(find.text('260'), findsOneWidget);
  });

  testWidgets('sin saber el saldo previo NO se inventa un «+0»',
      (tester) async {
    await abrir(tester, agregados: null, saldo: 150);

    // La etiqueta "CRÉDITOS" bajo el número sigue ahí; lo que no puede
    // aparecer es un "+N": la píldora del delta desaparece antes que mentir.
    expect(find.textContaining('+'), findsNothing);
    expect(find.text('150'), findsOneWidget,
        reason: 'el saldo sí se sabe: ese se canta igual');
  });

  testWidgets('NO se auto-cierra: espera a que el proveedor decida',
      (tester) async {
    await abrir(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byKey(clave), findsOneWidget);
  });

  testWidgets('el botón cierra y devuelve true', (tester) async {
    Future<bool?>? resultado;
    await abrir(tester, capturar: (f) => resultado = f);

    await tester.tap(find.text('Buscar clientes'));
    await tester.pumpAndSettle();

    expect(find.byKey(clave), findsNothing);
    expect(await resultado, isTrue);
  });

  testWidgets('salir por atrás devuelve null: nadie navega', (tester) async {
    Future<bool?>? resultado;
    await abrir(tester, capturar: (f) => resultado = f);

    // El proveedor que quiere seguir comprando sale por atrás y se queda en
    // la tienda, que sigue viva debajo.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(clave), findsNothing);
    expect(await resultado, isNull);
  });

  testWidgets('con «reducir animaciones» sigue diciendo lo mismo',
      (tester) async {
    await abrir(tester, reducirAnimaciones: true);

    expect(find.text('150'), findsOneWidget);
    expect(find.text('Buscar clientes'), findsOneWidget);
  });
}
