import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/vuelo_monedas.dart';

/// El vuelo nació en la tienda, donde SIEMPRE son cinco monedas. El intro lo
/// reusa para el bono de bienvenida, que vale lo que diga el servidor: si el
/// bono bajara a 3 y volaran 5, la animación estaría mintiendo.
void main() {
  Future<List<int>> volar(WidgetTester tester, {int? monedas}) async {
    final aterrizadas = <int>[];
    var termino = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            VueloMonedas(
              origen: const Offset(100, 500),
              destino: const Offset(300, 80),
              monedas: monedas ?? 5,
              onAterrizaje: aterrizadas.add,
              onFin: () => termino = true,
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(termino, isTrue, reason: 'el vuelo siempre acaba y se retira solo');
    return aterrizadas;
  }

  testWidgets('por defecto vuelan las cinco de siempre', (tester) async {
    expect(await volar(tester), [0, 1, 2, 3, 4]);
  });

  testWidgets('con un bono de 3 vuelan 3, no 5', (tester) async {
    expect(await volar(tester, monedas: 3), [0, 1, 2]);
  });

  testWidgets('una sola moneda también aterriza y termina', (tester) async {
    expect(await volar(tester, monedas: 1), [0]);
  });

  testWidgets('nunca vuelan más de cinco: la coreografía solo tiene cinco tiempos', (
    tester,
  ) async {
    expect(await volar(tester, monedas: 99), hasLength(5));
  });
}
