/// Port 1:1 de jayalo-main src/lib/phone.ts (misma semántica, RD +1).
String normalizePhone(String raw) {
  final t = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (t.isEmpty) return '';
  if (t.startsWith('+')) return t;
  if (t.length == 10) return '+1$t';
  return t;
}

bool isValidPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '').length >= 8;
