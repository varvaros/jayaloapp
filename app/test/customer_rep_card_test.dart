import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/customer_rep_card.dart';

/// Ficha del cliente en el detalle del proveedor (mockup aprobado 2026-08-11):
/// anónima hasta el desbloqueo, identidad real después, y puerta al perfil
/// cuando lleva `onTap`.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  const cid = 'abc-123';

  testWidgets('anónima: alias + "Nombre y foto al desbloquear"',
      (tester) async {
    await pump(tester, const CustomerRepCard(customerId: cid));
    expect(find.text(CustomerRepCard.aliasFor(cid)), findsOneWidget);
    expect(find.text('Nombre y foto al desbloquear'), findsOneWidget);
    expect(find.text('Ver perfil'), findsNothing); // sin onTap no hay puerta
  });

  testWidgets('revelada: nombre real + "Contacto desbloqueado"',
      (tester) async {
    await pump(
        tester,
        const CustomerRepCard(
          customerId: cid,
          realName: 'Amaury Rodríguez',
        ));
    expect(find.text('Amaury Rodríguez'), findsOneWidget);
    expect(find.text('Contacto desbloqueado'), findsOneWidget);
    expect(find.text(CustomerRepCard.aliasFor(cid)), findsNothing);
    expect(find.text('Nombre y foto al desbloquear'), findsNothing);
  });

  testWidgets('un realName vacío NO revela: cae a la ficha anónima',
      (tester) async {
    // La RPC puede devolver unlocked=true con nombres vacíos; eso no es una
    // identidad que mostrar.
    await pump(tester,
        const CustomerRepCard(customerId: cid, realName: '   '));
    expect(find.text(CustomerRepCard.aliasFor(cid)), findsOneWidget);
  });

  testWidgets('con onTap: muestra "Ver perfil" y el toque dispara',
      (tester) async {
    var taps = 0;
    await pump(
        tester,
        CustomerRepCard(
          customerId: cid,
          onTap: () => taps++,
        ));
    expect(find.text('Ver perfil'), findsOneWidget);
    await tester.tap(find.text(CustomerRepCard.aliasFor(cid)));
    expect(taps, 1);
  });
}
