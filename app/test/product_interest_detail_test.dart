import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/product_interest_detail_screen.dart';
import 'package:jayalo_app/features/provider/unlock_flow.dart' show WhatsappReveal;
import 'package:jayalo_app/features/shared/brand_kit.dart' show HoldToConfirmButton;
import 'package:jayalo_app/features/shared/collapsing_photo_panel.dart';
import 'package:jayalo_app/features/shared/customer_rep_card.dart';

/// Pedido PO 2026-08-01: "Interesado en producto" era una hoja al 70% de alto
/// que además enseñaba el WhatsApp del cliente en texto plano. Pasa a pantalla
/// completa con la misma estructura que el detalle de solicitud —datos del
/// cliente → información → acción—, con badge de que viene de la tienda, y el
/// teléfono detrás del mismo gate que las ofertas.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  ProductInterestDetailView view({
    bool unlocked = false,
    int balance = 5,
    String? contactPhone,
    String? contactName,
  }) =>
      ProductInterestDetailView(
        title: 'Taladro inalámbrico',
        message: 'Cantidad: 2\nCuándo quiere comprar: Esta semana',
        imageUrl: null,
        createdAt: DateTime.now(),
        unlocked: unlocked,
        cost: 1,
        balance: balance,
        customerId: 'cust-abc',
        contactName: contactName,
        contactPhone: contactPhone,
      );

  testWidgets('lleva el badge de que viene de la tienda', (tester) async {
    await tester.pumpWidget(host(view()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Desde tu tienda'), findsOneWidget);
  });

  testWidgets('usa el mismo panel plegable que el detalle de solicitud',
      (tester) async {
    await tester.pumpWidget(host(view()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(CollapsingPhotoPanel), findsOneWidget);
  });

  testWidgets('el orden es datos del cliente → información → acción',
      (tester) async {
    await tester.pumpWidget(host(view()));
    await tester.pump(const Duration(milliseconds: 450));

    final cliente = tester.getTopLeft(find.text('DATOS DEL CLIENTE')).dy;
    final info = tester.getTopLeft(find.text('INFORMACIÓN')).dy;
    final accion = tester.getTopLeft(find.byType(HoldToConfirmButton)).dy;

    expect(cliente, lessThan(info));
    expect(info, lessThan(accion));
  });

  testWidgets('muestra la ficha del cliente, como las solicitudes',
      (tester) async {
    await tester.pumpWidget(host(view()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(CustomerRepCard), findsOneWidget);
    expect(find.text(CustomerRepCard.aliasFor('cust-abc')), findsOneWidget);
  });

  testWidgets('sin desbloquear: hold de desbloqueo y ni rastro del contacto',
      (tester) async {
    await tester.pumpWidget(host(view()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(HoldToConfirmButton), findsOneWidget);
    expect(find.byType(WhatsappReveal), findsNothing);
  });

  testWidgets('saldo insuficiente: ofrece recargar en vez del hold',
      (tester) async {
    await tester.pumpWidget(host(view(balance: 0)));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Saldo insuficiente — Recargar'), findsOneWidget);
    expect(find.byType(HoldToConfirmButton), findsNothing);
  });

  testWidgets('desbloqueado: el chat es la vía y el teléfono NO se ve en claro',
      (tester) async {
    await tester.pumpWidget(host(view(
      unlocked: true,
      contactName: 'Ana',
      contactPhone: '+18095551234',
    )));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.widgetWithText(FilledButton, 'Abrir chat'), findsOneWidget);
    // Este era el bug reportado: el número salía escrito en la hoja.
    expect(find.textContaining('8095551234'), findsNothing);
    expect(find.textContaining('+1809'), findsNothing);
  });

  testWidgets('desbloqueado con teléfono: el gate con la advertencia está',
      (tester) async {
    await tester.pumpWidget(host(view(
      unlocked: true,
      contactName: 'Ana',
      contactPhone: '+18095551234',
    )));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(WhatsappReveal), findsOneWidget);
    expect(find.textContaining('no hay devolución'), findsOneWidget);
  });

  testWidgets('desbloqueado SIN teléfono: solo chat, sin gate vacío',
      (tester) async {
    await tester.pumpWidget(host(view(unlocked: true, contactName: 'Ana')));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.widgetWithText(FilledButton, 'Abrir chat'), findsOneWidget);
    expect(find.byType(WhatsappReveal), findsNothing);
  });
}
