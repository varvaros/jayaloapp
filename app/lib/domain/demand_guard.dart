/// "La solicitud es SOLO DEMANDA" (PO 2026-08-13): la BD rechaza con JY423
/// (trigger `trg_request_is_demand`, migracion 20260813120000) toda solicitud
/// cuyo texto sea una VENTA o un servicio OFRECIDO, sin marcador de demanda.
///
/// A diferencia del anti-contacto, aqui NO hay espejo del patron en Dart a
/// proposito: la regla es nueva y va a moverse; el filtro previo vive en el
/// servidor del chat (`/api/ai/chat-stream` convierte el `ready` ofertista en
/// una pregunta de redireccion, cubriendo web y app con UNA implementacion).
/// Este fichero solo traduce el SQLSTATE cuando algo llega igual a la BD.
library;

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// SQLSTATE del trigger "solo demanda". Familia de JY422 (contacto) y
/// JY429 (anti-flood).
const String offerNotAllowedCode = 'JY423';

const String offerNotAllowedMessage =
    'Aquí solo se pide lo que necesitas comprar o contratar. Si quieres vender '
    'o anunciar tu servicio, publícalo en tu tienda. Vuelve a empezar '
    'describiendo lo que necesitas.';

bool isOfferNotAllowedError(Object error) =>
    error is PostgrestException && error.code == offerNotAllowedCode;
