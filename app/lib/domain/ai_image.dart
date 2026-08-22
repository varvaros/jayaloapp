import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Lado mayor de la foto que ve la IA. Gemini tesela internamente a ~768 px:
/// los píxeles por encima son bytes de subida tirados, no visión. La foto
/// ORIGINAL no se toca — Storage y las previews siguen usando el fichero del
/// picker (1200 px); esto solo adelgaza lo que viaja en `imageDataUrl` en
/// CADA POST de la conversación.
const kAiImageMaxSide = 768;

/// Por debajo de este peso una imagen ya chica no se recomprime: pagar un
/// re-encode para ahorrar nada es puro CPU.
const kAiImagePassthroughBytes = 150 * 1024;

const _kAiJpegQuality = 72;

/// Data URL de la foto para la IA. PURA y síncrona para poder testearla;
/// en producción va dentro de [aiPhotoDataUrl] (isolate).
///
/// Best-effort POR DISEÑO: ante bytes que no decodifican (formato exótico,
/// fichero corrupto) devuelve los bytes tal cual — adjuntar una foto nunca
/// se bloquea por esta función; el peor caso es el peso de siempre.
String buildAiPhotoDataUrl(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return 'data:${_sniffMime(bytes)};base64,${base64Encode(bytes)}';
  }
  final maxSide = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (maxSide <= kAiImageMaxSide && bytes.length <= kAiImagePassthroughBytes) {
    return 'data:${_sniffMime(bytes)};base64,${base64Encode(bytes)}';
  }
  var out = decoded;
  if (maxSide > kAiImageMaxSide) {
    out = img.copyResize(
      out,
      width: out.width >= out.height ? kAiImageMaxSide : null,
      height: out.height > out.width ? kAiImageMaxSide : null,
      interpolation: img.Interpolation.linear,
    );
  }
  // JPEG no tiene alfa: un PNG/WebP transparente saldría con fondo NEGRO si
  // no se compone sobre blanco antes de encodear.
  if (out.hasAlpha) {
    final plana = img.Image(width: out.width, height: out.height, numChannels: 3);
    img.fill(plana, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(plana, out);
    out = plana;
  }
  final jpg = img.encodeJpg(out, quality: _kAiJpegQuality);
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}

/// Mime por bytes mágicos, no por extensión: la siembra descarga fotos de
/// Storage cuya URL no siempre dice la verdad (un WebP sin `.png` viajaba
/// etiquetado `image/jpeg`).
String _sniffMime(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/// Recomprime en un isolate: decodificar+re-encodear 1200 px en el hilo de UI
/// es jank garantizado mientras el usuario mira el compositor.
Future<String> aiPhotoDataUrl(Uint8List bytes) =>
    compute(buildAiPhotoDataUrl, bytes);
