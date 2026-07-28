/// Efectos de sonido cortos de la app. Hoy solo las DOS celebraciones
/// deliberadas (doctrina PO "hold en ambos, con distinción visual"):
///
///   • [Sfx.offerAccepted] — al aceptar una oferta (cliente).
///   • [Sfx.unlock] — al desbloquear el contacto (proveedor, acción pagada).
///
/// Fire-and-forget: el audio es DECORATIVO — si el dispositivo lo silencia o
/// falla la reproducción, nunca debe romper el flujo (todo va envuelto en un
/// try/catch). Cada disparo usa su propio [AudioPlayer] efímero que se libera
/// al terminar (patrón one-shot de audioplayers 6).
library;

import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Rutas RELATIVAS a `assets/` (así las resuelve `AssetSource`).
abstract final class Sfx {
  static const offerAccepted = 'sounds/oferta_aceptada.mp3';
  static const unlock = 'sounds/desbloqueo.mp3';

  /// Mensaje que entra mientras ESTÁS dentro de esa conversación. Discreto a
  /// propósito: ya estás mirando el chat, solo confirma que llegó algo.
  static const messageInChat = 'sounds/mensaje_en_chat.mp3';

  /// Mensaje que entra con la app abierta pero FUERA de esa conversación. Es el
  /// mismo pop de burbuja que suena con la app cerrada (canal `jayalo_chat_v1`
  /// de Android), para que el aviso se oiga igual esté donde esté el usuario.
  static const messageElsewhere = 'sounds/mensaje_nuevo.mp3';
}

/// Reproduce un SFX empaquetado una sola vez. Nunca lanza.
Future<void> playSfx(String asset) async {
  // Bajo `flutter test` no hay canal de plataforma de audio: instanciar un
  // AudioPlayer dispararía un error async no atrapado (rompe pumpAndSettle).
  // El audio es puramente decorativo, así que se omite en pruebas.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    final player = AudioPlayer();
    // Un one-shot: se libera solo al completar (o si algo falla al armarlo).
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.setReleaseMode(ReleaseMode.release);
    await player.play(AssetSource(asset));
  } catch (e) {
    // Decorativo: tragamos el error para no interrumpir la celebración.
    debugPrint('playSfx($asset) falló: $e');
  }
}
