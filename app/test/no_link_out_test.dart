import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Play prohíbe llevar al usuario a un método de pago que no sea el suyo
/// (link-out) y también insinuárselo (anti-steering). Un solo call site
/// reintroducido hace el binario NO publicable, así que se vigila desde los
/// tests en vez de confiar en la revisión.
///
/// ⚠️ La primera versión de este fichero vigilaba los NOMBRES de la
/// implementación que se retiró (`walletUrl`, `createWalletLoginLink`) y daba
/// verde sobre dos link-outs vivos: un `launchUrl` a `jayalo.com/provider` —un
/// panel con dos botones de "Recargar créditos" que abren PayPal— y el editor
/// de negocio, que se abría con la sesión ya montada sobre una página cuya
/// barra superior tenía "Mis créditos". Lo que hay que vigilar es la ACCIÓN
/// (salir al navegador) y el DESTINO, no el nombre de un helper muerto.
void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('el barrido encuentra ficheros (si no, el test pasa por vacío)', () {
    expect(dart.length, greaterThan(50));
  });

  test('ningún fichero abre el wallet web ni acuña magic links', () {
    final ofensores = <String>[];
    for (final f in dart) {
      final src = f.readAsStringSync();
      if (src.contains('walletUrl') ||
          src.contains('createWalletLoginLink') ||
          src.contains('create-wallet-login-link') ||
          src.contains('/provider/wallet')) {
        ofensores.add(rel(f));
      }
    }
    expect(ofensores, isEmpty,
        reason: 'link-out a Play prohibido reintroducido en: $ofensores');
  });

  /// Lista blanca de ficheros que pueden abrir el navegador. No es burocracia:
  /// cada salida al navegador es un link-out en potencia, y el destino puede
  /// volverse una zona de pago sin que cambie una línea de la app — es
  /// exactamente lo que pasó con `jayalo.com/provider`. Añadir un fichero aquí
  /// obliga a mirar A DÓNDE lleva.
  test('solo la lista blanca abre el navegador', () {
    const permitidos = <String>{
      'lib/core/secure_web_launch.dart', // el helper
      'lib/features/onboarding/provider_onboarding_screen.dart', // términos y privacidad
      'lib/features/onboarding/consumer_onboarding_screen.dart', // términos y privacidad
      'lib/features/settings/settings_screen.dart', // términos y privacidad
      'lib/features/chat/widgets/bubbles.dart', // mapas
      'lib/features/shared/open_in_maps_button.dart', // mapas (Task 11)
      'lib/features/provider/unlock_flow.dart', // wa.me del contacto desbloqueado
      // El editor del negocio. Su destino lleva `?embed=app`, que hace que la
      // web NO pinte navbar ni footer — sin eso, la barra superior de esa
      // página tiene "Mis créditos" → PayPal.
      'lib/features/provider/my_business_screen.dart',
    };
    final actuales = <String>{};
    for (final f in dart) {
      final src = f.readAsStringSync();
      if (src.contains('launchUrl(') || src.contains('launchAuthenticatedUrl(')) {
        actuales.add(rel(f));
      }
    }
    expect(actuales.difference(permitidos), isEmpty,
        reason: 'fichero nuevo que sale al navegador — comprobar que el DESTINO '
            'no contiene ninguna vía de pago: $actuales');
  });

  test('la app no abre ninguna ruta /provider de la web', () {
    final web = RegExp(r'''(AppConfig\.siteUrl|https://jayalo\.com)[^'"]*/provider''');
    final ofensores = [
      for (final f in dart)
        if (web.hasMatch(_sinComentarios(f.readAsStringSync()))) rel(f)
    ];
    expect(ofensores, isEmpty,
        reason: 'el panel web lleva dos "Recargar créditos" (PayPal) en: $ofensores');
  });

  // Lo que Play prohíbe insinuar es PAGAR fuera de su sistema, no mencionar el
  // sitio. Un patrón sobre "jayalo.com" a secas marcaba copy legítimo como
  // "Completa tu negocio en jayalo.com para ofertar" (ofertar es GRATIS). Pero
  // la primera corrección se pasó de laxa: exigía las dos mitades en la MISMA
  // línea y a menos de 40 caracteres, así que un copy partido por el
  // formateador se escapaba. Ahora el texto se normaliza antes de buscar.
  test('ninguna pantalla sugiere pagar fuera de la app', () {
    const dinero = r'(recarg\w*|pag(?:a|ar|ando|o|os|u[eé])\w*|compr\w*'
        r'|cr[ée]dito\w*|saldo|paquete\w*|barat\w*|ahorr\w*|descuento\w*)';
    const fuera = r'(jayalo\.com|(?:la|nuestra|una) (?:web|p[áa]gina)'
        r'|sitio (?:web|oficial)|el navegador|tu (?:computadora|pc)'
        r'|fuera de la app|desde la web)';
    // Sin ancla de dinero: quien escribe esto ya está desviando.
    const solos = r'(desde la web|m[áa]s barat)';
    final prohibido = RegExp(
      '$dinero.{0,80}$fuera|$fuera.{0,80}$dinero|$solos',
      caseSensitive: false,
      dotAll: true,
    );
    final ofensores = <String>[];
    for (final f in dart) {
      final copys = _literales(_sinComentarios(f.readAsStringSync()));
      if (copys.any(prohibido.hasMatch)) ofensores.add(rel(f));
    }
    expect(ofensores, isEmpty, reason: 'copy anti-steering en: $ofensores');
  });
}

/// Quita los comentarios. Lo que Play juzga es el copy que ve el usuario; una
/// nota nuestra explicando por qué ya no mandamos a nadie a la web no es un
/// steer, y con los comentarios dentro el test marcaba media docena de ellas y
/// habría acabado desactivado por ruidoso.
///
/// Cubre `//` de línea completa y bloques `/* */` (que la primera versión
/// ignoraba, así que la regla se aplicaba a unos comentarios y a otros no). Una
/// línea que empiece por `//` pero contenga comillas se CONSERVA: puede ser la
/// segunda mitad de un URL partido por el formateador, y ese es justo el caso
/// que no se puede dejar escapar.
/// Extrae los literales de texto y **une los adyacentes**, que es como Dart
/// concatena una frase larga y como `dartfmt` la parte en varias líneas: para
/// el usuario es un solo copy.
///
/// Se busca dentro de cada literal y NO sobre el fichero entero colapsado: eso
/// último pegaba palabras de líneas sin relación entre sí (dos falsos
/// positivos medidos) y un test ruidoso acaba desactivado.
List<String> _literales(String src) {
  final comilla = String.fromCharCode(39); // '
  final doble = String.fromCharCode(34); // "
  final lit = RegExp(
    '$comilla(?:\\\\.|[^$comilla\\\\])*$comilla'
    '|$doble(?:\\\\.|[^$doble\\\\])*$doble',
    dotAll: true,
  );
  final grupos = <String>[];
  final buffer = StringBuffer();
  var finAnterior = -1;
  for (final m in lit.allMatches(src)) {
    final texto = m.group(0)!;
    final cuerpo = texto.substring(1, texto.length - 1);
    final separador = finAnterior < 0 ? '' : src.substring(finAnterior, m.start);
    // Solo espacios entre dos literales = concatenación adyacente de Dart.
    if (finAnterior >= 0 && separador.trim().isEmpty) {
      buffer.write(cuerpo);
    } else {
      if (buffer.isNotEmpty) grupos.add(buffer.toString());
      buffer.clear();
      buffer.write(cuerpo);
    }
    finAnterior = m.end;
  }
  if (buffer.isNotEmpty) grupos.add(buffer.toString());
  return grupos;
}

String _sinComentarios(String src) {
  final sinBloques = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return sinBloques
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        if (!t.startsWith('//')) return true;
        return t.contains("'") || t.contains('"');
      })
      .join('\n');
}
