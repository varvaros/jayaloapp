import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/contact_info.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  const bloquea = [
    'Llámame al 809-555-1234',
    '8095551234',
    '8 0 9 5 5 5 1 2 3 4',
    '+1 (829) 555-1234',
    '849.555.1234',
    '809,555,1234',
    '８０９５５５１２３４',
    'Escríbeme a wa.me/18095551234',
    'Contáctame: ventas@ferreteria.do',
  ];
  const pasa = [
    'Garantía de 12 meses',
    'RNC 130123456',
    'Medida 809 x 1234567 mm',
    'modelo 809, pieza 5551234',
    '',
  ];

  // Casos NUEVOS de la revision final (2026-07-29). Van aparte de la bateria
  // canonica de 14 (que no se toca) y son los mismos, uno a uno, que
  // `src/lib/contactInfo.test.ts` de la web. Los guiones Unicode se escriben
  // con `String.fromCharCode` porque en el codigo fuente son indistinguibles
  // del `-` ASCII a simple vista.
  final bloqueaNuevos = <String, String>{
    // El SQL usa `[[:alnum:]]`, que con el lc_ctype UTF-8 de Supabase casa
    // letras acentuadas: antes la BD los rechazaba y el aviso del formulario
    // no, y el usuario perdia lo escrito.
    'correo con tilde en el nombre': 'josé@gmail.com',
    'correo con tilde en el dominio': 'ventas@ferretería.do',
    'telefono con guion largo U+2013':
        '809${String.fromCharCode(0x2013)}555${String.fromCharCode(0x2013)}1234',
    'telefono con guion U+2010':
        '809${String.fromCharCode(0x2010)}555${String.fromCharCode(0x2010)}1234',
    'telefono con signo menos U+2212':
        '809${String.fromCharCode(0x2212)}555${String.fromCharCode(0x2212)}1234',
    // Ruta de Storage con `Date.now()` que empieza por 1829: el detector SI la
    // casa (al quitar `-`/`.` el timestamp queda como bloque de digitos
    // contiguo). En la app NO es un problema porque los call sites revisan
    // listas explicitas de campos de texto, nunca URLs de imagen; en la web si
    // lo era, y por eso `payloadHasContactInfo` salta las URLs (ver
    // `src/lib/contactInfo.test.ts`). El caso se replica aqui para que las dos
    // implementaciones sigan dando el MISMO veredicto sobre la misma entrada.
    'ruta de Storage con timestamp 1829':
        'https://mfaiklvobnvgusbcssbx.supabase.co/storage/v1/object/public/'
            'business-logos/8e2b0f4a-1111-2222-3333-444455556666/requests/'
            '1829773255605-3i726g-p0.webp',
  };

  for (final entrada in bloquea) {
    test('bloquea: $entrada', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  }

  bloqueaNuevos.forEach((nombre, entrada) {
    test('bloquea (caso nuevo) $nombre', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  });

  // Bateria v2 (2026-08-14, migracion 20260814120000_contact_info_guard_v2).
  // La v1 solo plegaba una lista fija de separadores, asi que CUALQUIER otro
  // caracter entre los digitos la evadia entera. Verificado en produccion antes
  // del arreglo: los 5 primeros devolvian `false`. Desde la APP el agujero
  // estaba abierto del todo: la web tapaba a medias el caso del emoji porque
  // `sanitizeUserText` los borraba, y la app nunca los borro fuera del chat.
  // Espejada 1:1 en `src/lib/contactInfo.test.ts` y en el pie de la migracion.
  final bloqueaV2 = <String, String>{
    'letra pegada': 'llamame al 809x8675309',
    'asterisco pegado': 'llamame al 809*8675309',
    'guion bajo pegado': 'llamame al 809_8675309',
    'barra pegada': 'llamame al 809/867/5309',
    'emoji pegado': 'llamame al 809\u{1F44D}8675309',
    // Dos code points: por eso la rama de PEGADO lleva `+`.
    'emoji con tono de piel': 'llamame al 809\u{1F44D}\u{1F3FD}8675309',
    'varias letras pegadas': 'llamame al 809ab8675309',
    'almohadilla': 'llamame al 809#867#5309',
    'dos puntos': 'llamame al 809:867:5309',
    'asterisco espaciado': 'llamame al 809 * 867 * 5309',
    'barra espaciada': 'llamame al 809 / 867 / 5309',
    'punto y coma espaciado': 'llamame al 809 ; 867 ; 5309',
    // Si el hueco no cubriera el PREFIJO este caso se escaparia: es la
    // regresion que hundio el primer intento de arreglo.
    'area espaciada entera': 'llamame al 8 0 9 8 6 7 5 3 0 9',
    'parentesis del area': 'mi numero: (809) 867-5309',
    // INVISIBLES. Son los 6 codepoints donde `\s` de Dart y `[[:space:]]` de
    // glibc NO coinciden, y por eso se BORRAN en las tres implementaciones: sin
    // eso el SQL bloqueaba el BOM y el cliente lo dejaba pasar -- la divergencia
    // que hace perder lo escrito. Un BOM se cuela al pegar desde Word.
    // Escritos como escape, NUNCA como byte literal (gotcha registrado: un
    // caracter de control literal en un test es ilegible y puede volver el
    // fichero binario para git).
    'BOM U+FEFF entre digitos': 'llamame al 809\u{FEFF}8675309',
    'NEL U+0085 entre digitos': 'llamame al 809\u{0085}8675309',
    'separador U+001C entre digitos': 'llamame al 809\u{001C}8675309',
    'separador U+001F entre digitos': 'llamame al 809\u{001F}8675309',
  };

  // Lo que la v2 tiene que SEGUIR dejando pasar.
  final pasaV2 = <String, String>{
    // El salto de linea es FRONTERA DURA: `customer_requests.description` la
    // COMPONE LA MAQUINA uniendo bullets, asi que fusionar a traves del salto
    // hacia que el usuario leyera "no incluyas telefonos" sobre un texto que el
    // no escribio asi. Coste aceptado: '809\n8675309' pasa.
    'telefono partido en dos lineas': 'llamame al 809\n8675309',
    'lista con vinetas': '• 809\n• 5551234',
    'lista numerada': '1. 809\n2. 5551234',
    'dos campos en lineas distintas': 'Ref 809\nCantidad 5551234',
    // Simbolos de LISTA, fuera de la lista blanca de la rama 3.
    'vineta en linea': 'Cantidad: 809 • 5551234 unidades',
    'punto medio': '809 · 5551234',
    'barra vertical': '809 | 5551234',
    // Atenuante de los falsos positivos aceptados: basta un espacio o un RD\$.
    'solar con la unidad separada': 'Terreno 809 m2 de 5,551,234 pesos',
    'solar con prefijo de moneda': 'Terreno 809m2 RD\$5,551,234',
    // Textos que componen los propios generadores de la app.
    'mensaje de oferta generado':
        'Estado: Nuevo · Garantia: 1 ano · Envio: RD\$300',
    'bullets de la IA': 'Marca: Kikkoman • Contenido: 5 fl oz (148 ml)',
    // Marketplace dominicano.
    'codigo con palabra intercalada': 'Serie 809 modelo 1234567 unidades',
    'cedula': 'Cedula 001-1234567-8',
    'dimensiones': 'Nevera 1200x800 mm, 12 pies',
    'perfil': 'Perfil 2x4 de 8 pies',
    'capacidad': 'Capacidad: 12,000 BTU',
    'lote': 'lote 809-2024',
  };

  bloqueaV2.forEach((nombre, entrada) {
    test('bloquea (v2) $nombre', () {
      expect(containsContactInfo(entrada), isTrue);
    });
  });

  for (final entrada in pasa) {
    test('deja pasar: $entrada', () {
      expect(containsContactInfo(entrada), isFalse);
    });
  }

  pasaV2.forEach((nombre, entrada) {
    test('deja pasar (v2) $nombre', () {
      expect(containsContactInfo(entrada), isFalse);
    });
  });

  // El nucleo del arreglo: el espacio dejo de borrarse. Si alguien lo devuelve a
  // `_separadores`, "Medida 809 x 1234567 mm" pasa a bloquearse y este test cae.
  test('no borra el espacio: distingue el separador PEGADO del ESPACIADO', () {
    expect(containsContactInfo('809x8675309'), isTrue);
    expect(containsContactInfo('Medida 809 x 1234567 mm'), isFalse);
  });

  test('tolera null', () => expect(containsContactInfo(null), isFalse));

  // Añadido en el fix round 1 (hallazgo del guardado en tienda,
  // request_detail_screen.dart:_maybeSaveToStore): isContactInfoError es la
  // parte que decide si el catch de un envío traduce el SQLSTATE al mensaje
  // humano o cae al genérico — sin tests propios hasta ahora, aunque ya se
  // usaba en dos call sites.
  group('isContactInfoError', () {
    test('true para JY422 — el rechazo real del trigger', () {
      expect(
        isContactInfoError(const PostgrestException(
          message: 'contact_info_not_allowed',
          code: 'JY422',
        )),
        isTrue,
      );
    });

    test(
        'false para JY500 — error de PROGRAMACIÓN nuestro, nunca se traduce '
        'al mensaje de "no incluyas teléfonos ni correos"', () {
      expect(
        isContactInfoError(const PostgrestException(
          message:
              'enforce_no_contact_info: la tabla no tiene la columna esperada',
          code: 'JY500',
        )),
        isFalse,
      );
    });

    test('false para otro SQLSTATE cualquiera (p. ej. JY429, anti-flood)', () {
      expect(
        isContactInfoError(const PostgrestException(
          message: 'Vas muy rápido, espera un momento.',
          code: 'JY429',
        )),
        isFalse,
      );
    });

    test('false para un error que no es PostgrestException', () {
      expect(isContactInfoError(Exception('red caída')), isFalse);
    });
  });

  group('payloadHasContactInfo — barrido del payload entero', () {
    test('detecta el dato sucio en CUALQUIER campo, no solo en `message`', () {
      expect(
        payloadHasContactInfo({
          'message': 'Todo bien',
          'product_warranty': 'Garantía: escríbeme a ventas@ferreteria.do',
        }),
        isTrue,
      );
    });

    test('mira dentro de las listas de strings (product_colors)', () {
      expect(
        payloadHasContactInfo({
          'message': 'Todo bien',
          'product_colors': const ['rojo', '809-555-1234'],
        }),
        isTrue,
      );
    });

    test('un payload limpio pasa, con números y precios incluidos', () {
      expect(
        payloadHasContactInfo({
          'message': 'Medida 809 x 1234567 mm, RNC 130123456',
          'price': 1500.0,
          'offers_shipping': true,
          'product_colors': const ['rojo', 'azul'],
        }),
        isFalse,
      );
    });

    test('una URL de Storage con un timestamp de 13 dígitos NO es falso positivo',
        () {
      // El bloque `1829...` casaría el patrón de móvil RD si no se saltaran las
      // URLs: es el caso que rompería TODO envío con foto en ciertas fechas.
      expect(
        payloadHasContactInfo({
          'message': 'Listo',
          'image_urls': const [
            'https://x.supabase.co/storage/v1/object/public/b/u/1829551234567-ab.webp',
          ],
        }),
        isFalse,
      );
    });

    test('pero un wa.me sí se detecta aunque venga como URL', () {
      expect(
        payloadHasContactInfo({'message': 'https://wa.me/18095551234'}),
        isTrue,
      );
    });

    test('ignora valores que no son string ni lista de strings', () {
      expect(
        payloadHasContactInfo({'price': null, 'hourly_rate': 250.0, 'x': 1}),
        isFalse,
      );
    });
  });
}
