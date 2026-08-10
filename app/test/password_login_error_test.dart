import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// El mensaje crudo de Supabase llega en inglés y no dice qué hacer; esta es
/// la ÚNICA puerta de entrada de la app, así que el copy importa.
void main() {
  group('passwordLoginError', () {
    test('credenciales inválidas', () {
      expect(
        passwordLoginError(AuthException('Invalid login credentials')),
        'Correo o contraseña incorrectos.',
      );
    });

    test('correo sin confirmar dice qué hacer', () {
      expect(
        passwordLoginError(AuthException('Email not confirmed')),
        contains('Confirma tu correo'),
      );
    });

    test('rate limit', () {
      expect(
        passwordLoginError(
            AuthException('Too many requests, please try again later')),
        contains('Demasiados intentos'),
      );
    });

    test('cualquier otro fallo cae al genérico accionable', () {
      expect(
        passwordLoginError(Exception('SocketException: no route to host')),
        contains('Revisa tu conexión'),
      );
      expect(
        passwordLoginError(AuthException('Something unexpected')),
        contains('Revisa tu conexión'),
      );
    });

    test('nunca devuelve el mensaje crudo de Supabase', () {
      for (final raw in [
        'Invalid login credentials',
        'Email not confirmed',
        'Something unexpected',
      ]) {
        expect(passwordLoginError(AuthException(raw)), isNot(contains(raw)));
      }
    });
  });
}
