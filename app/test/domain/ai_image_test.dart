import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:jayalo_app/domain/ai_image.dart';

// Fixtures generados con el propio paquete `image` (sin ficheros binarios en
// el repo). Un degradado comprime parecido a una foto; el ruido puro no.
Uint8List _jpegDegradado(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 128);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 88));
}

Uint8List _pngTransparente(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  // Alfa 0 en todo: si el encode a JPEG no compone sobre blanco, sale NEGRO.
  return Uint8List.fromList(img.encodePng(im));
}

img.Image _decodificarDataUrl(String dataUrl) {
  final coma = dataUrl.indexOf(',');
  final bytes = base64Decode(dataUrl.substring(coma + 1));
  return img.decodeImage(bytes)!;
}

void main() {
  test('una foto grande baja a 768 px de lado mayor y pesa menos', () {
    final entrada = _jpegDegradado(1600, 1200);
    final dataUrl = buildAiPhotoDataUrl(entrada);
    expect(dataUrl, startsWith('data:image/jpeg;base64,'));
    final salida = _decodificarDataUrl(dataUrl);
    expect(salida.width, kAiImageMaxSide);
    expect(salida.height, lessThanOrEqualTo(kAiImageMaxSide));
    final pesoSalida = base64Decode(dataUrl.split(',')[1]).length;
    expect(pesoSalida, lessThan(entrada.length));
  });

  test('la vertical respeta el lado mayor en alto', () {
    final dataUrl = buildAiPhotoDataUrl(_jpegDegradado(900, 1500));
    final salida = _decodificarDataUrl(dataUrl);
    expect(salida.height, kAiImageMaxSide);
    expect(salida.width, lessThan(kAiImageMaxSide));
  });

  test('una foto ya chica y liviana pasa INTACTA (passthrough)', () {
    final entrada = _jpegDegradado(400, 300);
    expect(entrada.length, lessThan(kAiImagePassthroughBytes),
        reason: 'el fixture debe ser liviano para probar el passthrough');
    final dataUrl = buildAiPhotoDataUrl(entrada);
    expect(dataUrl, 'data:image/jpeg;base64,${base64Encode(entrada)}');
  });

  test('PNG transparente grande sale JPEG con fondo BLANCO, no negro', () {
    final dataUrl = buildAiPhotoDataUrl(_pngTransparente(1000, 900));
    expect(dataUrl, startsWith('data:image/jpeg;base64,'));
    final salida = _decodificarDataUrl(dataUrl);
    final p = salida.getPixel(salida.width ~/ 2, salida.height ~/ 2);
    // JPEG q72 puede rizar un pelo: blanco = canales muy altos, nunca ~0.
    expect(p.r, greaterThan(240));
    expect(p.g, greaterThan(240));
    expect(p.b, greaterThan(240));
  });

  test('bytes que no decodifican pasan tal cual con mime por defecto', () {
    final basura = Uint8List.fromList(List.generate(64, (i) => (i * 7) % 251));
    final dataUrl = buildAiPhotoDataUrl(basura);
    expect(dataUrl, 'data:image/jpeg;base64,${base64Encode(basura)}');
  });

  test('el mime del passthrough sale de los bytes mágicos, no de nadie más', () {
    final png = _pngTransparente(8, 8);
    expect(buildAiPhotoDataUrl(png), startsWith('data:image/png;base64,'));
    // Cabecera WebP sintética (RIFF....WEBP): no decodifica como imagen real
    // ⇒ passthrough, y aun así el mime debe decir webp.
    final webpHeader = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, //
      0x57, 0x45, 0x42, 0x50, 0x00, 0x00, 0x00, 0x00,
    ]);
    expect(
      buildAiPhotoDataUrl(webpHeader),
      startsWith('data:image/webp;base64,'),
    );
  });
}
