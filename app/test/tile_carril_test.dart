import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/tile_carril.dart';

/// Regresion (ronda de arreglo 1/5, Task 8): PortfolioTile guarda estado
/// propio (pagina del carrusel) pero vivia SIN key dentro de un
/// ListView.separated que indexa por POSICION. Al borrar un trabajo, los
/// que le siguen se corren de posicion y, sin key, Flutter reutilizaba el
/// State de esa posicion para un trabajo distinto — el carrusel del que
/// quedaba en esa posicion aparecia en una pagina que no le correspondia.
void main() {
  testWidgets(
      'borrar el primer trabajo no traspasa la pagina del carrusel al que '
      'queda en su lugar', (tester) async {
    var trabajos = [
      {
        'id': 't1',
        'title': 'Trabajo uno',
        'media': [
          {'url': 'https://x/1a.jpg', 'kind': 'image'},
          {'url': 'https://x/1b.jpg', 'kind': 'image'},
        ],
      },
      {
        'id': 't2',
        'title': 'Trabajo dos',
        'media': [
          {'url': 'https://x/2a.jpg', 'kind': 'image'},
          {'url': 'https://x/2b.jpg', 'kind': 'image'},
          {'url': 'https://x/2c.jpg', 'kind': 'image'},
        ],
      },
    ];

    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setSt) {
          setState = setSt;
          return SizedBox(
            width: 800,
            child: TileCarril(
              items: trabajos,
              height: 230,
              tileBuilder: (t) => PortfolioTile(
                key: ValueKey(t['id']),
                item: t,
              ),
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    // Mueve el carrusel del SEGUNDO trabajo (t2, indice 1, con 3 archivos)
    // a su pagina 2.
    final controladorT2Antes =
        tester.widget<PageView>(find.byType(PageView).at(1)).controller!;
    controladorT2Antes.jumpToPage(2);
    await tester.pumpAndSettle();
    expect(controladorT2Antes.page, 2.0);

    // Borra t1 (el primero): t2 pasa de indice 1 a indice 0.
    setState(() {
      trabajos = [trabajos[1]];
    });
    await tester.pumpAndSettle();

    // t2, ahora en indice 0, debe seguir mostrando SU pagina 2 — no la
    // pagina 0 que tenia t1 (el que se borro y con el que NO debe
    // confundirse).
    final controladorEnIndice0 =
        tester.widget<PageView>(find.byType(PageView).first).controller!;
    expect(controladorEnIndice0.page, 2.0);
  });
}
