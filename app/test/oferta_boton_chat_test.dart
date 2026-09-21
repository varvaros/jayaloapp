import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/request_status_screen.dart'
    show OfferChatButton;

/// Atajo al chat en la tarjeta de la oferta «En contacto» (PO 2026-09-21).
/// `_OfferCard` es privado, así que se prueba el widget extraído en aislado —
/// mismo patrón que `offer_card_provider_header_test.dart`.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('dice lo MISMO que el botón del detalle de la oferta', (t) async {
    await t.pumpWidget(wrap(OfferChatButton(onTap: () {})));
    // Literal copiada de `offer_actions.dart`: dos botones que hacen lo mismo
    // no pueden llamarse distinto.
    expect(find.text('Hablar con el proveedor'), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
  });

  testWidgets('al tocarlo avisa una sola vez', (t) async {
    var toques = 0;
    await t.pumpWidget(wrap(OfferChatButton(onTap: () => toques++)));
    await t.tap(find.byType(OfferChatButton));
    await t.pumpAndSettle();
    expect(toques, 1);
  });
}
