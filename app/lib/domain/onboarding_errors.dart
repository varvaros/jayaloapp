/// Los slugs los lanza complete_provider_onboarding (ADR-0029) y PostgREST los
/// entrega dentro del message de la excepción — basta buscar el slug. El caso
/// 23505 cubre el upsert directo de profiles del consumidor (sin RPC).
const _slugCopy = {
  'whatsapp_taken':
      'Este WhatsApp ya está registrado en otro usuario. Usa otro número o inicia sesión con la cuenta que lo tiene.',
  'phone_taken':
      'Este teléfono ya está registrado en otra cuenta. Usa otro número o inicia sesión con la cuenta que lo tiene.',
  'rnc_taken': 'Este RNC ya está registrado.',
  'duplicate': 'Ese registro ya existe. Revisa tu WhatsApp o RNC.',
  'invalid_business': 'Falta el nombre del negocio.',
  'not_authenticated': 'Tu sesión expiró. Inicia sesión de nuevo.',
};

String onboardingErrorCopy(Object error) {
  final msg = error.toString();
  if (msg.contains('23505') && msg.contains('phone')) {
    return _slugCopy['phone_taken']!;
  }
  for (final e in _slugCopy.entries) {
    if (msg.contains(e.key)) return e.value;
  }
  return 'No pudimos completar tu registro. Revisa tu conexión e intenta de nuevo.';
}
