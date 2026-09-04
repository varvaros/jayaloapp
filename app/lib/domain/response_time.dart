/// Tiempo de respuesta del usuario como CLIENTE ("Regularmente respondes en X").
///
/// La mediana la calcula la RPC `get_customer_reputation` (server-side, sobre
/// las últimas 20 muestras: respuestas de chat + decisiones de oferta). Aquí
/// solo vive el umbral de visibilidad y el paso a palabras.
///
/// Estaba dentro de `features/client/reputation_screen.dart` como constante y
/// función privadas. Salió aquí al aparecer una SEGUNDA superficie que lo
/// enseña (la sección "Como comprador" de `provider/stats_screen.dart`): una
/// pantalla de proveedor no debe importar una de cliente — misma razón por la
/// que `MetricTile` vive en `brand_kit.dart` y no en Reputación.
library;

/// Con menos de estas respuestas medidas la mediana no representa nada y la
/// frase se omite por completo — a un usuario nuevo no se le castiga con un
/// dato construido sobre dos muestras.
///
/// Espejo del `MIN_RESPONSE_SAMPLES` de la web (`src/lib/responseTime.ts`).
const kMinResponseSamples = 5;

/// La frase completa, o `null` si todavía no hay con qué decirla.
///
/// Recibe lo que devuelve la RPC tal cual (`median_response_minutes` puede
/// venir nulo si no hubo ninguna muestra) para que las dos pantallas apliquen
/// el mismo criterio en vez de cada una el suyo.
String? responseTimeCopy(int? medianMinutes, int samples) {
  if (medianMinutes == null || medianMinutes < 0) return null;
  if (samples < kMinResponseSamples) return null;
  return 'Regularmente respondes en ${humanMinutes(medianMinutes)}';
}

/// "45 minutos" / "unas 2 horas" / "1 día" — nunca "min" ni "h" abreviados:
/// el público de la app lee palabras, no unidades.
String humanMinutes(int m) {
  if (m < 60) return '$m minutos';
  final horas = (m / 60).round();
  if (horas < 24) return horas == 1 ? 'una hora' : 'unas $horas horas';
  final dias = (horas / 24).round();
  return dias == 1 ? 'un día' : '$dias días';
}
