/// Copy del tiempo de respuesta del proveedor ("Regularmente responde en ~X"),
/// mostrado en la tienda anónima bajo el nombre del proveedor.
///
/// La mediana en minutos viene de la RPC `get_business_response_times`
/// (server-side, SECURITY DEFINER); aquí solo se mapea a rangos amigables.
/// Paridad EXACTA con la web (`src/lib/responseTime.ts`): mismos umbrales y
/// mismo mínimo de muestras. Con menos de [minResponseSamples] respuestas
/// medidas no se muestra nada — un proveedor nuevo no se castiga.
library;

const int minResponseSamples = 5;

/// Devuelve el copy o `null` (no mostrar la línea) según la mediana y el número
/// de muestras.
String? responseTimeCopy(double? medianMinutes, int samples) {
  if (medianMinutes == null || medianMinutes < 0) return null;
  if (samples < minResponseSamples) return null;
  if (medianMinutes < 60) return 'Regularmente responde en minutos';
  if (medianMinutes < 360) return 'Regularmente responde en pocas horas';
  if (medianMinutes < 1440) return 'Regularmente responde el mismo día';
  if (medianMinutes < 4320) return 'Regularmente responde en 1–2 días';
  return 'Puede tardar varios días en responder';
}
