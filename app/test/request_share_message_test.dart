import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_share_message.dart';

ShareableRequest _r({
  String id = 'r1',
  String? title = 'Silla decorativa de caoba',
  String? zone,
  String? description,
  num? budgetMin,
  num? budgetMax,
}) =>
    ShareableRequest(
      id: id,
      title: title,
      zone: zone,
      description: description,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      urgency: null,
      kind: 'product',
    );

void main() {
  group('buildRequestShareText', () {
    test('con zona, la nombra en la cabecera', () {
      final t = buildRequestShareText(_r(zone: 'Piantini'));
      expect(t, startsWith(
          'Hola, tengo un cliente en Piantini que busca: Silla decorativa de caoba'));
    });

    test('sin zona, la cabecera no la inventa', () {
      final t = buildRequestShareText(_r());
      expect(t, startsWith('Hola, tengo un cliente que busca: Silla decorativa de caoba'));
      expect(t, isNot(contains(' en  que busca')));
    });

    test('una zona de solo espacios cuenta como sin zona', () {
      expect(buildRequestShareText(_r(zone: '   ')),
          startsWith('Hola, tengo un cliente que busca:'));
    });

    test('sin titulo dice "un trabajo"', () {
      expect(buildRequestShareText(_r(title: '  ')),
          startsWith('Hola, tengo un cliente que busca: un trabajo'));
      expect(buildRequestShareText(_r(title: null)),
          startsWith('Hola, tengo un cliente que busca: un trabajo'));
    });

    test('los cuatro casos de presupuesto', () {
      expect(buildRequestShareText(_r(budgetMin: 1000, budgetMax: 5000)),
          contains('Presupuesto: RD\$1,000 – RD\$5,000'));
      expect(buildRequestShareText(_r(budgetMin: 1000)),
          contains('Presupuesto: desde RD\$1,000'));
      expect(buildRequestShareText(_r(budgetMax: 5000)),
          contains('Presupuesto: hasta RD\$5,000'));
      expect(buildRequestShareText(_r()), isNot(contains('Presupuesto')));
    });

    test('el enlace sale de ShareLinks, al final', () {
      expect(buildRequestShareText(_r(id: 'abc')),
          endsWith('Míralo aquí: https://jayalo.com/requests/abc'));
    });

    test('la descripcion larga se recorta a 220 code points con …', () {
      final larga = 'a' * 300;
      final t = buildRequestShareText(_r(description: larga));
      expect(t, contains('${'a' * 220}…'));
      expect(t, isNot(contains('a' * 221)));
    });

    test('una descripcion corta viaja entera y sin …', () {
      final t = buildRequestShareText(_r(description: 'Dos sillas'));
      expect(t, contains('Dos sillas'));
      expect(t, isNot(contains('Dos sillas…')));
    });

    test('recorta por CODE POINTS: no parte un emoji por la mitad', () {
      // 300 emojis = 300 code points = 600 unidades UTF-16. Recortar por
      // `length` partiria el par subrogado y dejaria un caracter invalido.
      final t = buildRequestShareText(_r(description: '🪑' * 300));
      final cuerpo = t.split('\n\n')[1];
      expect(cuerpo.runes.length, 221); // 220 + el …
      expect(cuerpo, endsWith('…'));
      expect(cuerpo, isNot(contains('�')));
    });
  });

  group('privacidad', () {
    test('la lista blanca es exactamente esta', () {
      // Espejo de SHAREABLE_FIELDS en src/lib/requestShareMessage.ts.
      expect(kShareableRequestCols, [
        'id', 'title', 'zone', 'description',
        'budget_min', 'budget_max', 'urgency', 'kind',
      ]);
    });

    test('ANCLA: una fila con datos del perfil NO los filtra al mensaje', () {
      // `city`/`sector` se copian del PERFIL del cliente en la misma consulta
      // que su GPS (web: requests/new.tsx) y la pagina publica no los muestra.
      // Es el barrio de su casa. Si alguien los mete en el texto, esto cae.
      final fila = <String, dynamic>{
        'id': 'r9',
        'title': 'Mesa de comedor',
        'zone': 'Piantini',
        'description': 'Para seis personas',
        'budget_min': 1000,
        'budget_max': 2000,
        'urgency': 'normal',
        'kind': 'product',
        'city': 'SANTIAGOSECRETO',
        'sector': 'LOSJARDINESSECRETO',
        'lat': 19.4517,
        'lng': -70.6970,
        'user_id': 'UUIDDELCLIENTE',
      };
      final texto = buildRequestShareText(ShareableRequest.fromRow(fila));
      for (final prohibido in [
        'SANTIAGOSECRETO', 'LOSJARDINESSECRETO', '19.4517', '70.6970',
        'UUIDDELCLIENTE',
      ]) {
        expect(texto, isNot(contains(prohibido)), reason: 'se filtro $prohibido');
      }
      expect(texto, contains('Piantini')); // `zone` SI puede viajar
    });
  });

  group('whatsappShareUri', () {
    test('apunta a wa.me sin numero y con el texto codificado', () {
      final u = whatsappShareUri(_r(id: 'r7', zone: 'Piantini'));
      expect(u.origin, 'https://wa.me');
      expect(u.path, '/');
      expect(u.queryParameters['text'], buildRequestShareText(_r(id: 'r7', zone: 'Piantini')));
    });
  });

  group('guarda estatica: fromRow no puede leer una columna fuera de la lista blanca', () {
    // En la web esto lo hace el COMPILADOR (`tsc` con `satisfies` + `AssertCovers`
    // sobre SHAREABLE_FIELDS en requestShareMessage.ts); Dart no tiene equivalente
    // estatico, asi que este test LEE EL CODIGO FUENTE de `fromRow` (mismo patron
    // que no_link_out_test.dart) y compara cada `r['clave']` que lee contra
    // `kShareableRequestCols`. Hace falta ADEMAS del test de mutacion de arriba:
    // ese solo caza un campo fugado si alguien lo mete en el TEXTO del mensaje: un
    // campo que se agregue a la clase y a `fromRow` pero que todavia no se use en
    // `buildRequestShareText` pasa desapercibido — y deja la fuga cargada para el
    // siguiente que edite la funcion y si la use.
    test('ANCLA-ESTATICA: toda clave que fromRow lee de la fila esta en kShareableRequestCols', () {
      final src = File('lib/domain/request_share_message.dart').readAsStringSync();

      final inicio =
          src.indexOf('factory ShareableRequest.fromRow(Map<String, dynamic> r) =>');
      expect(inicio, greaterThanOrEqualTo(0),
          reason: 'no se encontro "factory ShareableRequest.fromRow" en '
              'request_share_message.dart — ¿se renombro o se movio? esta guarda '
              'depende de poder localizar y leer su cuerpo como texto.');
      final fin = src.indexOf(';', inicio);
      expect(fin, greaterThan(inicio));
      final cuerpo = src.substring(inicio, fin);

      final lector = RegExp(r'''r\[['"]([A-Za-z0-9_]+)['"]\]''');
      final leidas = lector.allMatches(cuerpo).map((m) => m.group(1)!).toSet();

      expect(leidas, isNotEmpty,
          reason: 'no se encontro ninguna r[\'...\'] dentro del cuerpo de fromRow '
              '— el regex de este test dejo de encajar con el codigo real; '
              'revisalo antes de confiar en que este test protege algo.');

      final fuera = leidas.difference(kShareableRequestCols.toSet());
      expect(fuera, isEmpty,
          reason: 'fromRow lee ${fuera.join(", ")} de la fila, pero esa clave NO '
              'esta en kShareableRequestCols. Este mensaje sale de la plataforma '
              'por WhatsApp a alguien SIN SESION: si ${fuera.join(", ")} es algo '
              'como city/sector/lat/lng, es el barrio donde vive el cliente. '
              'Agregala a kShareableRequestCols solo si /requests/<id> ya la '
              'muestra sin sesion; si no, sacala de fromRow.');
    });
  });
}
