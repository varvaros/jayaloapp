import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/data/repos.dart' show BusinessLite;
import 'package:jayalo_app/features/client/product_detail_screen.dart';

/// `/catalog/:id` (Task 7): el detalle pinta nombre/precio/negocio, el
/// estado idempotente "ya enviaste tu interés" reemplaza el CTA, el negocio
/// se muestra con su nombre y logo reales SIEMPRE (PO 2026-07-28: el
/// cliente ve la identidad del proveedor sin desbloquear nada, paridad
/// `products.$productId.tsx`), y un error de la RPC `create_product_interest`
/// avisa sin reventar la pantalla.
///
/// `sendInterest`/`loadAddress`/`uploadPhoto` se inyectan (mismo patrón que
/// `CatalogFetch` en `catalog_screen_test.dart`) para probar sin tocar Supabase.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  // Ancho de teléfono típico: con la surface de prueba por defecto (800x600,
  // apaisada) la galería cuadrada (ancho completo) mide 800px de alto y
  // empuja nombre/precio/negocio/CTA fuera del cacheExtent del ListView —
  // nunca se llegan a construir. Mismo ajuste que ya usa
  // `catalog_screen_test.dart` para su prueba de overflow.
  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final producto = <String, dynamic>{
    'id': 'p1',
    'user_id': 'owner-1',
    'business_id': 'biz-1',
    'name': 'Taladro inalámbrico',
    'description': 'Taladro de 20V con dos baterías.',
    'color': null,
    'price': 2500,
    'price_min': null,
    'price_max': null,
    'image_urls': <String>[],
    'category_id': 'ferreteria',
    'rubro': 'Herramientas',
    'condition': 'nuevo',
    'offers_shipping': false,
    'offers_installation': false,
    'kind': 'producto',
  };

  const negocio =
      (id: 'biz-1', name: 'Ferretería Pérez', logoUrl: null, verified: true);

  ProductDetailData dataFor({
    Map<String, dynamic>? product,
    BusinessLite? business = negocio,
    bool hasInterest = false,
    bool isOwner = false,
  }) =>
      ProductDetailData(
        product: product ?? producto,
        business: business,
        hasInterest: hasInterest,
        isOwner: isOwner,
      );

  Widget view(
    ProductDetailData data, {
    VoidCallback? onInterestSent,
    Future<({bool ok, bool alreadyExists, String? id})> Function(
            String productId, String message)?
        sendInterest,
  }) =>
      ProductDetailView(
        data: data,
        onInterestSent: onInterestSent ?? () {},
        sendInterest: sendInterest ??
            (_, _) async => (ok: true, alreadyExists: false, id: 'i1'),
        loadAddress: () async => null,
        uploadPhoto: (_) async => 'https://cdn.example.com/foto.jpg',
      );

  testWidgets('pinta nombre, precio y el negocio con su identidad real',
      (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(dataFor())));
    await tester.pumpAndSettle();

    expect(find.text('Taladro inalámbrico'), findsOneWidget);
    expect(find.text('RD\$2,500'), findsOneWidget);
    expect(find.text('Ferretería Pérez'), findsOneWidget);
  });

  testWidgets('ya interesado muestra el estado amable, no el CTA',
      (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(dataFor(hasInterest: true))));
    await tester.pumpAndSettle();

    expect(find.text('Solicitud enviada'), findsOneWidget);
    expect(find.text('Solicitar'), findsNothing);
  });

  testWidgets('el dueño no ve ningún CTA de interés', (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(dataFor(isOwner: true))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Este es tu producto'), findsOneWidget);
    expect(find.text('Solicitar'), findsNothing);
    expect(find.text('Solicitud enviada'), findsNothing);
  });

  testWidgets(
      'el negocio muestra su nombre real aunque el cliente no tenga interés '
      'registrado (PO 2026-07-28: ya no hay gate de identidad por unlock)',
      (tester) async {
    setPhoneSize(tester);
    await tester
        .pumpWidget(host(view(dataFor(hasInterest: false, isOwner: false))));
    await tester.pumpAndSettle();

    expect(find.text('Ferretería Pérez'), findsOneWidget);
    expect(find.text('Proveedor'), findsNothing);
  });

  testWidgets('error de la RPC muestra un aviso y no revienta la pantalla',
      (tester) async {
    setPhoneSize(tester);
    var sent = false;
    await tester.pumpWidget(host(view(
      dataFor(),
      sendInterest: (_, _) async => throw Exception('boom'),
      onInterestSent: () => sent = true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Enviar'));
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    // El diálogo de confirmación aparece antes de llamar a la RPC.
    expect(find.text('¿Enviar tu interés?'), findsOneWidget);
    await tester.tap(find.text('Sí, enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No se pudo enviar tu solicitud.'), findsOneWidget);
    expect(sent, isFalse);
  });

  testWidgets('éxito: cierra el sheet y notifica onInterestSent',
      (tester) async {
    setPhoneSize(tester);
    var sent = false;
    await tester.pumpWidget(host(view(
      dataFor(),
      sendInterest: (id, message) async {
        expect(id, 'p1');
        expect(message, contains('Cantidad: 1'));
        return (ok: true, alreadyExists: false, id: 'i1');
      },
      onInterestSent: () => sent = true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enviar'));
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sent, isTrue);
    // El sheet se cerró: "Confirmar solicitud" ya no está en pantalla.
    expect(find.text('Confirmar solicitud'), findsNothing);
  });

  testWidgets(
      'servicio: el botón Enviar queda deshabilitado bajo 15 caracteres',
      (tester) async {
    setPhoneSize(tester);
    final servicio = {...producto, 'id': 'p2', 'kind': 'servicio'};
    var calls = 0;
    await tester.pumpWidget(host(view(
      dataFor(product: servicio),
      sendInterest: (_, _) async {
        calls++;
        return (ok: true, alreadyExists: false, id: 'i1');
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();

    // Sin escribir nada en "¿Qué necesitas?", el botón está deshabilitado.
    final enviarBtn = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton, 'Enviar', skipOffstage: false));
    expect(enviarBtn.onPressed, isNull);

    await tester.enterText(
        find.byType(TextField).first, 'Muy corto');
    await tester.pumpAndSettle();
    final stillDisabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enviar', skipOffstage: false));
    expect(stillDisabled.onPressed, isNull);
    expect(calls, 0);
  });

  // Pedido PO 2026-08-03: coherencia visual con las ofertas. `provider_products`
  // guarda `brand`, `warranty` y `requires_evaluation`, y el detalle no los
  // pintaba — ni siquiera los traía en su `select`. No existe `delivery_time`
  // en productos (eso es de ofertas), así que no se inventa.
  testWidgets('pinta los detalles que el producto sí guarda', (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(dataFor(
      product: {
        ...producto,
        'brand': 'DeWalt',
        'warranty': '1 año',
        'requires_evaluation': true,
      },
    ))));
    await tester.pumpAndSettle();

    expect(find.text('DeWalt'), findsOneWidget);
    expect(find.text('Garantía: 1 año'), findsOneWidget);
    expect(find.text('Requiere evaluación'), findsOneWidget);
  });

  testWidgets('sin esos datos no aparecen chips vacíos', (tester) async {
    setPhoneSize(tester);
    // `producto` no trae brand/warranty y no requiere evaluación.
    await tester.pumpWidget(host(view(dataFor())));
    await tester.pumpAndSettle();

    expect(find.text('Requiere evaluación'), findsNothing);
    expect(find.textContaining('Garantía'), findsNothing);
  });
}
