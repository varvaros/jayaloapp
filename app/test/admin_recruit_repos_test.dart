import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/domain/request_share_message.dart';

void main() {
  test('la pantalla pide la lista blanca MAS created_at, y nada mas', () {
    // Dos listas, dos responsabilidades: `kShareableRequestCols` es lo que el
    // MENSAJE puede llevar; `kAdminListCols` es lo que la PANTALLA pide (le
    // hace falta la fecha). Si alguien mete `city` aqui para pintarla en la
    // fila, este test lo hace visible en el diff.
    expect(kAdminListCols, [...kShareableRequestCols, 'created_at']);
    for (final prohibido in ['city', 'sector', 'lat', 'lng', 'user_id']) {
      expect(kAdminListCols, isNot(contains(prohibido)));
    }
  });

  test('el select es la lista separada por comas, sin espacios', () {
    // PostgREST parte por comas: un espacio dentro haria que pidiera una
    // columna llamada " title" y devolveria 400.
    expect(kAdminListCols.join(','), isNot(contains(' ')));
  });
}
