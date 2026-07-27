/// Port 1:1 de jayalo-main src/lib/phone.ts (misma semántica, RD +1).
String normalizePhone(String raw) {
  final t = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (t.isEmpty) return '';
  if (t.startsWith('+')) return t;
  if (t.length == 10) return '+1$t';
  return t;
}

bool isValidPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '').length >= 8;

const kRdPrefixes = ['809', '829', '849'];

/// Compone un WhatsApp RD desde prefijo (809/829/849) + 7 dígitos locales.
/// Devuelve E.164 o '' si el local no tiene EXACTAMENTE 7 dígitos.
String composeRdWhatsapp(String prefix, String local) {
  final p = kRdPrefixes.contains(prefix) ? prefix : '809';
  final digits = local.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 7) return '';
  return normalizePhone('$p$digits');
}
