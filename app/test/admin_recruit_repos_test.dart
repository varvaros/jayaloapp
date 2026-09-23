import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/domain/request_share_message.dart';

void main() {
  test('la pantalla pide la lista blanca MAS created_at, y nada mas', () {
    // Dos listas, dos responsabilidades: `kShareableRequestCols` es lo que el
    // MENSAJE puede llevar; `kAdminListCols` es lo que la PANTALLA pide (le
    // hace falta la fecha). Si alguien mete `city` aqui para pintarla en la
    // fila, este test lo hace visible en el diff.
    // Y desde el 2026-09-22 las dos columnas de FOTO: el PO no distinguia dos
    // solicitudes con el mismo titulo en la lista. Siguen FUERA del mensaje
    // (`ShareableRequest.fromRow` lee solo `kShareableRequestCols`).
    expect(kAdminListCols, [
      ...kShareableRequestCols,
      'created_at',
      'image_url',
      'image_urls',
    ]);
    for (final prohibido in ['city', 'sector', 'lat', 'lng', 'user_id']) {
      expect(kAdminListCols, isNot(contains(prohibido)));
    }
  });

  test('el select es la lista separada por comas, sin espacios', () {
    // PostgREST parte por comas: un espacio dentro haria que pidiera una
    // columna llamada " title" y devolveria 400.
    expect(kAdminListCols.join(','), isNot(contains(' ')));
  });

  test(
    'adminListRequests excluye las solicitudes DIRIGIDAS de la consulta '
    '(su pagina publica no carga sin sesion)',
    () {
      // Este repo NO mockea Supabase (`supa` es `Supabase.instance.client`,
      // un singleton que exige `Supabase.initialize()` real) y `PostgrestBuilder`
      // no expone la URL/los filtros que arma antes de ejecutar la consulta
      // (`_url` es privado) — así que la cadena de filtros REAL no se puede
      // comprobar sin red. Lo que SÍ se puede comprobar sin ejecutar nada es
      // que el filtro sigue en el CUERPO de la función, con el método exacto
      // que exige `supabase_flutter` para un IS NULL: `.isFilter(col, null)`,
      // nunca `.eq(col, null)` (compila, pero jamás compara igual a NULL en
      // Postgres, así que dejaría pasar las dirigidas).
      //
      // Lo que este test CAZA: que alguien borre o revierta el filtro, que lo
      // escriba con el método equivocado (`.eq` en vez de `.isFilter`), o que
      // le cambie el nombre de columna por un error de tipeo.
      // Lo que este test NO CAZA: que la política RLS deje de aplicar, que
      // `.isFilter` genere una URL de PostgREST distinta a la que Supabase
      // documenta, ni que alguien monte para esta pantalla una consulta nueva
      // que no pase por `adminListRequests`.
      final fuente = File('lib/data/repos.dart').readAsStringSync();
      const firma = 'Future<List<Map<String, dynamic>>> adminListRequests';
      final inicio = fuente.indexOf(firma);
      expect(inicio, greaterThanOrEqualTo(0),
          reason: 'no se encontró adminListRequests en repos.dart');
      final finBlanco = fuente.indexOf('\n\n', inicio);
      final cuerpo = fuente.substring(inicio, finBlanco > 0 ? finBlanco : fuente.length);

      expect(cuerpo, contains(".isFilter('target_business_id', null)"));
      expect(cuerpo, isNot(contains(".eq('target_business_id'")));

      // El orden no importa para Postgres, pero si el filtro de status
      // desaparece del cuerpo sin que nadie lo note, el índice da -1 y esta
      // comparación también revienta.
      expect(
        cuerpo.indexOf(".eq('status', 'open')"),
        lessThan(cuerpo.indexOf(".isFilter('target_business_id', null)")),
      );
    },
  );
}
