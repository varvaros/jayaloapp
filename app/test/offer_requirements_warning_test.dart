import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/domain/request_requirements.dart';
import 'package:jayalo_app/features/provider/offer_requirements_warning.dart';

void main() {
  /// Monta un botón que abre el aviso y guarda lo que devuelve. Sin esto no hay
  /// forma de probar un diálogo: necesita un `BuildContext` bajo un `Navigator`.
  Future<bool?> abrir(WidgetTester tester, List<Requirement> unmet) async {
    bool? resultado;
    await tester.pumpWidget(MaterialApp(
      theme: jayaloTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await showOfferRequirementsWarning(context, unmet);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  testWidgets('lista cada requisito sin cubrir con su etiqueta y su explicación',
      (tester) async {
    await abrir(tester, const [Requirement.fiscal, Requirement.state]);

    expect(find.text('El cliente pide algo que tu oferta no cubre'), findsOneWidget);
    expect(find.text('Requiere comprobante fiscal'), findsOneWidget);
    expect(
      find.text('El proveedor debe poder emitir comprobante fiscal (NCF).'),
      findsOneWidget,
    );
    expect(find.text('Requiere suplidor del Estado'), findsOneWidget);
    expect(find.textContaining('comprobante fiscal y suplidor del Estado'),
        findsOneWidget);
  });

  testWidgets('los requisitos salen en orden canónico', (tester) async {
    await abrir(tester, const [
      Requirement.shipping,
      Requirement.fiscal,
      Requirement.state,
    ]);

    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      textos.indexOf('Requiere envío') < textos.indexOf('Requiere comprobante fiscal'),
      isTrue,
    );
    expect(
      textos.indexOf('Requiere comprobante fiscal') <
          textos.indexOf('Requiere suplidor del Estado'),
      isTrue,
    );
  });

  testWidgets('devuelve true al enviar de todos modos y false al editar',
      (tester) async {
    bool? resultado;
    Future<void> montar(List<Requirement> unmet) async {
      await tester.pumpWidget(MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultado = await showOfferRequirementsWarning(context, unmet);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    await montar(const [Requirement.fiscal]);
    await tester.tap(find.text('Enviar de todos modos'));
    await tester.pumpAndSettle();
    expect(resultado, isTrue);

    await montar(const [Requirement.fiscal]);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(resultado, isFalse);
  });

  testWidgets('el copy no promete que el cliente lo verá', (tester) async {
    // Hoy nadie lee `provider_offers.has_fiscal_receipt`, ni en la app ni en la
    // web. El texto dice que queda registrado, no que el cliente lo verá: si
    // alguien lo cambia, que este test lo pare hasta que sea verdad.
    await abrir(tester, const [Requirement.fiscal]);
    expect(find.textContaining('quedará registrado'), findsOneWidget);
    expect(find.textContaining('el cliente verá'), findsNothing);
  });
}
