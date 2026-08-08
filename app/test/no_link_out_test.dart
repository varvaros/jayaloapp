import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Play prohíbe llevar al usuario a un método de pago que no sea el suyo
/// (link-out) y también insinuárselo (anti-steering). Un solo call site
/// reintroducido hace el binario NO publicable, así que se vigila desde los
/// tests en vez de confiar en la revisión.
void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

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
        ofensores.add(f.path);
      }
    }
    expect(ofensores, isEmpty,
        reason: 'link-out a Play prohibido reintroducido en: $ofensores');
  });

  // Lo que Play prohíbe insinuar es PAGAR fuera de su sistema, no mencionar el
  // sitio. Un patrón sobre "jayalo.com" a secas marcaba copy legítimo como
  // "Completa tu negocio en jayalo.com para ofertar" (ofertar es GRATIS, no
  // hay pago que desviar) y se habría desactivado por ruidoso, que es peor que
  // no tenerlo. Por eso exige las dos mitades: dinero + fuera de la app.
  test('ninguna pantalla sugiere pagar fuera de la app', () {
    const dinero = r'(recarg\w*|recarga|pagar|pago|compra\w*|comprar|cr[ée]ditos)';
    const fuera = r'(jayalo\.com|la web|el navegador|p[áa]gina web|fuera de la app)';
    final prohibido = RegExp(
      '$dinero[^\\n]{0,40}$fuera|$fuera[^\\n]{0,40}$dinero|más barato en',
      caseSensitive: false,
    );
    final ofensores = <String>[];
    for (final f in dart) {
      if (prohibido.hasMatch(_sinComentarios(f.readAsStringSync()))) {
        ofensores.add(f.path);
      }
    }
    expect(ofensores, isEmpty, reason: 'copy anti-steering en: $ofensores');
  });
}

/// Quita las líneas que son SOLO comentario. Lo que Play juzga es el copy que
/// ve el usuario; una nota nuestra explicando por qué ya no mandamos a nadie a
/// la web no es un steer. Sin este filtro el test marcaba media docena de
/// comentarios y acabaría desactivado por ruidoso.
String _sinComentarios(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');
