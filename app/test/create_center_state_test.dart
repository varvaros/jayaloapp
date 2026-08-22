import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/client/create_request_screen.dart';

/// El botón central de la barra dentro de crear solicitud (bug PO 2026-08-22:
/// «sigue activo creando una solicitud»). La pantalla necesita Supabase vivo,
/// así que el predicado vive fuera y se prueba aquí.
void main() {
  test('componiendo: la cámara manda, encendida', () {
    final s = centerStateForCreate(started: false, submitted: false);
    expect(s.enabled, isTrue);
    expect(s.icon, Icons.photo_camera_outlined);
    expect(s.label, 'Añadir foto');
  });

  test('conversación en marcha: APAGADO', () {
    final s = centerStateForCreate(started: true, submitted: false);
    expect(s.enabled, isFalse);
    expect(s.icon, Icons.add);
    expect(s.label, 'En curso');
  });

  test('publicada: APAGADO (la pantalla de éxito se queda en pantalla)', () {
    final s = centerStateForCreate(started: true, submitted: true);
    expect(s.enabled, isFalse);
    expect(s.label, 'Publicada');
  });

  test('publicada manda sobre started', () {
    // Al publicar, `_messages` sigue lleno: el orden de los ifs importa.
    expect(centerStateForCreate(started: true, submitted: true).label,
        'Publicada');
    expect(centerStateForCreate(started: false, submitted: true).label,
        'Publicada');
  });

  test('si el primer turno falla y se vacía el historial, vuelve la cámara', () {
    // Los dos `catch` de `_send` hacen `_messages.removeLast()`: con el primer
    // turno eso deja la lista vacía y la pantalla regresa al compositor. Antes,
    // el botón ya se había soltado y NADIE lo retomaba.
    final s = centerStateForCreate(started: false, submitted: false);
    expect(s.enabled, isTrue);
    expect(s.icon, Icons.photo_camera_outlined);
  });
}
