import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/improve_offer_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// `improve_offer_price` (migración 20260801150000) rechaza con ERRCODE P0001 y
/// un mensaje ya escrito para el usuario final. Antes de esto el diálogo hacía
/// `catch (_)` y mostraba SIEMPRE "No se pudo mejorar la oferta.", así que el
/// proveedor no distinguía "el precio tiene que ser menor" de "se cayó la red".
void main() {
  group('improveOfferErrorCopy', () {
    test('P0001: muestra el mensaje de la RPC tal cual', () {
      expect(
        improveOfferErrorCopy(
          PostgrestException(
            message: 'El nuevo precio debe ser menor al actual',
            code: 'P0001',
          ),
        ),
        'El nuevo precio debe ser menor al actual',
      );
    });

    test('P0001: la conversación cerrada también llega literal', () {
      expect(
        improveOfferErrorCopy(
          PostgrestException(
            message: 'La conversación está cerrada',
            code: 'P0001',
          ),
        ),
        'La conversación está cerrada',
      );
    });

    test('otro código de Postgrest cae al mensaje genérico', () {
      // 42501 (RLS) o 42704 no son reglas de negocio redactadas para el
      // usuario: son fallos que no debe leer en crudo.
      expect(
        improveOfferErrorCopy(
          PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ),
        'No se pudo mejorar la oferta. Revisa tu conexión e intenta de nuevo.',
      );
    });

    test('un fallo de red cae al mensaje genérico', () {
      expect(
        improveOfferErrorCopy(Exception('SocketException: host lookup failed')),
        'No se pudo mejorar la oferta. Revisa tu conexión e intenta de nuevo.',
      );
    });

    test('P0001 con mensaje vacío cae al genérico, no a una burbuja en blanco',
        () {
      expect(
        improveOfferErrorCopy(PostgrestException(message: '', code: 'P0001')),
        'No se pudo mejorar la oferta. Revisa tu conexión e intenta de nuevo.',
      );
    });
  });
}
