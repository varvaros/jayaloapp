/// Avance honesto del asistente de crear solicitud ("N de ~M").
///
/// La IA decide cuántas preguntas hace (presupuesto del prompt: hasta 5 en
/// flujo normal, 7-8 en mayorista), así que M es un ESTIMADO y se muestra con
/// "~". Reglas: la barra nunca se llena antes del turno `ready`, y si la IA
/// pregunta más de lo estimado la meta crece en vez de clavarse en 100 %.
library;

int estimatedTotal({required int answered, required bool wholesale}) {
  final base = wholesale ? 7 : 4;
  return answered >= base ? answered + 1 : base;
}

double progressFraction(
    {required int answered, required bool wholesale, required bool ready}) {
  if (ready) return 1;
  return answered / estimatedTotal(answered: answered, wholesale: wholesale);
}
