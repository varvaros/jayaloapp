import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/package_detail_screen.dart';

/// Detalle de un PAQUETE de la tienda pública (pedido PO 2026-08-09: "El
/// paquete no abre nada"). Mismo patrón que `product_detail_screen_test.dart`
/// — `PackageDetailView` es la parte pura (sin fetch), `sendInterest` se
/// inyecta para probar sin tocar Supabase.
///
/// El CTA "Solicitar" reusa la MISMA RPC que el interés de producto
/// (`create_product_interest`, que ya resuelve contra `provider_products` O
/// `provider_packages` server-side — migración `20260718150000`), con el
/// mismo formato de mensaje que ya usaba la web
/// (`business.$id.tsx`: `Solicitud por paquete: ${pkName}`) — no hace falta
/// el formulario largo del producto (cantidad/color/dirección no aplican a
/// un paquete), solo un diálogo de confirmación, igual que el `AlertDialog`
/// que la web ya usa para esto.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: Scaffold(body: child),
      );

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final paquete = <String, dynamic>{
    'id': 'pk1',
    'user_id': 'owner-1',
    'business_id': 'biz-1',
    'name': 'Plan Básico',
    'description': 'Mantenimiento mensual de aires acondicionados.',
    'price': 1500,
    'items': <String>['1 visita al mes', 'Limpieza de filtros', 'Revisión de gas'],
    'image_url': null,
  };

  PackageDetailData dataFor({
    Map<String, dynamic>? package,
    bool hasInterest = false,
    bool isOwner = false,
  }) =>
      PackageDetailData(
        package: package ?? paquete,
        hasInterest: hasInterest,
        isOwner: isOwner,
      );

  Widget view(
    PackageDetailData data, {
    VoidCallback? onInterestSent,
    Future<({bool ok, bool alreadyExists, String? id})> Function(
            String productId, String message)?
        sendInterest,
  }) =>
      PackageDetailView(
        data: data,
        onInterestSent: onInterestSent ?? () {},
        sendInterest: sendInterest ??
            (_, _) async => (ok: true, alreadyExists: false, id: 'i1'),
      );

  testWidgets('pinta nombre, precio, descripción y "Qué incluye"',
      (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(dataFor())));
    await tester.pumpAndSettle();

    expect(find.text('Plan Básico'), findsOneWidget);
    expect(find.text('RD\$1,500'), findsOneWidget);
    expect(find.text('Mantenimiento mensual de aires acondicionados.'),
        findsOneWidget);
    expect(find.text('Qué incluye'), findsOneWidget);
    expect(find.text('1 visita al mes'), findsOneWidget);
    expect(find.text('Limpieza de filtros'), findsOneWidget);
    expect(find.text('Revisión de gas'), findsOneWidget);
  });

  testWidgets('precio en 0 o null: "Consultar precio"', (tester) async {
    setPhoneSize(tester);
    await tester
        .pumpWidget(host(view(dataFor(package: {...paquete, 'price': 0}))));
    await tester.pumpAndSettle();
    expect(find.text('Consultar precio'), findsOneWidget);

    await tester.pumpWidget(host(
        view(dataFor(package: {...paquete, 'price': null}))));
    await tester.pumpAndSettle();
    expect(find.text('Consultar precio'), findsOneWidget);
  });

  testWidgets('sin items: no aparece "Qué incluye"', (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
        host(view(dataFor(package: {...paquete, 'items': <String>[]}))));
    await tester.pumpAndSettle();
    expect(find.text('Qué incluye'), findsNothing);
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

    expect(find.textContaining('Este es tu paquete'), findsOneWidget);
    expect(find.text('Solicitar'), findsNothing);
    expect(find.text('Solicitud enviada'), findsNothing);
  });

  testWidgets(
      'Solicitar → confirmar → envía "Solicitud por paquete: <nombre>" y avisa',
      (tester) async {
    setPhoneSize(tester);
    var sent = false;
    await tester.pumpWidget(host(view(
      dataFor(),
      sendInterest: (id, message) async {
        expect(id, 'pk1');
        expect(message, 'Solicitud por paquete: Plan Básico');
        return (ok: true, alreadyExists: false, id: 'i1');
      },
      onInterestSent: () => sent = true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Enviar solicitud?'), findsOneWidget);
    await tester.tap(find.text('Sí, enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sent, isTrue);
    expect(find.text('¡Solicitud enviada! El proveedor te contactará pronto.'),
        findsOneWidget);
  });

  testWidgets('cancelar el diálogo no manda nada', (tester) async {
    setPhoneSize(tester);
    var calls = 0;
    await tester.pumpWidget(host(view(
      dataFor(),
      sendInterest: (_, _) async {
        calls++;
        return (ok: true, alreadyExists: false, id: 'i1');
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('already_exists: avisa que ya envió antes', (tester) async {
    setPhoneSize(tester);
    await tester.pumpWidget(host(view(
      dataFor(),
      sendInterest: (_, _) async =>
          (ok: true, alreadyExists: true, id: 'i1'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Solicitar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Ya enviaste tu solicitud por este paquete.'),
        findsOneWidget);
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
    await tester.tap(find.text('Sí, enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No se pudo enviar tu solicitud.'), findsOneWidget);
    expect(sent, isFalse);
  });
}
