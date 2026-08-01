import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Mensaje genérico: todo lo que no sea una regla de negocio de la RPC.
const _improveOfferFallback =
    'No se pudo mejorar la oferta. Revisa tu conexión e intenta de nuevo.';

/// Copy para el usuario a partir del error de `improve_offer_price`
/// (migración 20260801150000).
///
/// La RPC rechaza sus reglas de negocio con `ERRCODE = 'P0001'` y un mensaje ya
/// redactado en español para quien lo va a leer ("El nuevo precio debe ser
/// menor al actual", "La conversación está cerrada"…), así que ese se muestra
/// tal cual. Cualquier otro fallo — RLS, red, un 42704 — es ruido de
/// infraestructura que el proveedor no debe leer en crudo: cae al genérico.
///
/// Mismo patrón que [onboardingErrorCopy] en `onboarding_errors.dart`, pero
/// discriminando por CÓDIGO en vez de por slug dentro del texto: aquí el
/// contrato del servidor es el errcode, que no se rompe al reescribir el copy.
String improveOfferErrorCopy(Object error) {
  if (error is PostgrestException &&
      error.code == 'P0001' &&
      error.message.trim().isNotEmpty) {
    return error.message;
  }
  return _improveOfferFallback;
}
