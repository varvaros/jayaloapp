/// Ficha "Detalles del proveedor" — paridad con `src/lib/providerDetails.ts` y
/// `BusinessDetailsCard.tsx` de la web.
///
/// La app enseñaba tres chips (categoría, zona, mayorista) donde la web tiene
/// nueve filas. El PO lo reportó como "la tienda aún no tiene el diseño que se
/// coordinó" (2026-08-01). Esto es la parte de datos; el dibujo vive en
/// `features/shared/business_details_card.dart`.
///
/// Puro a propósito, sin Flutter y sin reloj: [currentYear] entra por
/// parámetro para que "hace N años" sea testeable.
library;

import 'oficio.dart';

typedef BusinessDetailRow = ({
  BusinessDetailKind kind,
  String label,
  String value,
});

/// El TIPO de fila, para que la capa de dibujo elija el ícono sin volver a
/// interpretar la etiqueta.
enum BusinessDetailKind {
  wholesale,
  profession,
  experience,
  founded,
  team,
  coverage,
  hours,
  languages,
  payments,
  warranty,
}

const _serviceAreas = <String, String>{
  'en_taller': 'En taller / local',
  'a_domicilio': 'A domicilio',
  'ambos': 'En taller y a domicilio',
  'ciudad': 'Solo en mi ciudad',
  'nacional': 'En todo el país',
};

const _languages = <String, String>{
  'es': 'Español',
  'en': 'Inglés',
  'fr': 'Francés',
  'pt': 'Portugués',
  'it': 'Italiano',
  'de': 'Alemán',
  'zh': 'Chino',
  'cr': 'Creole',
};

const _paymentMethods = <String, String>{
  'efectivo': 'Efectivo',
  'transferencia': 'Transferencia',
  'tarjeta': 'Tarjeta',
  'paypal': 'PayPal',
  'cripto': 'Cripto',
};

/// Orden de la semana. `full` en minúscula al construir los segmentos, con la
/// primera letra del resumen en mayúscula al final — igual que la web.
const _days = <(String, String)>[
  ('mon', 'Lunes'),
  ('tue', 'Martes'),
  ('wed', 'Miércoles'),
  ('thu', 'Jueves'),
  ('fri', 'Viernes'),
  ('sat', 'Sábado'),
  ('sun', 'Domingo'),
];

List<String> _codeList(dynamic raw) => raw is List
    ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
    : const [];

/// Las filas que la ficha debe pintar, en el ORDEN de la web. Lista vacía =
/// no hay nada que contar y la ficha entera se oculta.
List<BusinessDetailRow> businessDetailRows(
  Map<String, dynamic> business, {
  required int currentYear,
}) {
  final rows = <BusinessDetailRow>[];

  if (business['is_wholesale'] == true) {
    rows.add((
      kind: BusinessDetailKind.wholesale,
      label: 'Ventas',
      value: 'Al por mayor',
    ));
  }

  // El texto libre `profession` queda SUSTITUIDO por el catálogo de oficios
  // (PO 2026-08-20), igual que ya hizo `BusinessDetailsCard.tsx` en la web.
  // Sin respaldo al texto viejo a propósito: mantener los dos vivos es
  // exactamente la divergencia que el catálogo existe para cerrar.
  final oficios = approvedOficioNames(business);
  if (oficios.isNotEmpty) {
    rows.add((
      kind: BusinessDetailKind.profession,
      label: oficios.length == 1 ? 'Profesión' : 'Profesiones',
      value: oficios.join(' · '),
    ));
  }

  final years = (business['experience_years'] as num?)?.toInt();
  if (years != null && years > 0) {
    rows.add((
      kind: BusinessDetailKind.experience,
      label: 'Experiencia',
      value: '$years ${years == 1 ? 'año' : 'años'}',
    ));
  }

  // Solo negocios formales: el CHECK de la tabla admite tecnico|informal|formal
  // y "fundada en" no significa nada para un técnico independiente.
  final founded = (business['founded_year'] as num?)?.toInt();
  if (business['business_type'] == 'formal' && founded != null) {
    final ago = currentYear - founded;
    rows.add((
      kind: BusinessDetailKind.founded,
      label: 'Fundada',
      // Un año futuro (dato mal metido) no debe producir "hace -4 años".
      value: ago >= 0 ? '$founded · $ago ${ago == 1 ? 'año' : 'años'}' : '$founded',
    ));
  }

  final team = (business['employees_count'] as String?)?.trim();
  if (team != null && team.isNotEmpty) {
    rows.add((
      kind: BusinessDetailKind.team,
      label: 'Equipo',
      value: '$team ${team == '1' ? 'persona' : 'personas'}',
    ));
  }

  final area = _serviceAreas[business['service_area'] as String? ?? ''];
  if (area != null) {
    rows.add((
      kind: BusinessDetailKind.coverage,
      label: 'Cobertura',
      value: area,
    ));
  }

  final hours = summarizeHours(
      (business['service_hours'] as Map?)?.cast<String, dynamic>());
  if (hours != null) {
    rows.add((kind: BusinessDetailKind.hours, label: 'Horario', value: hours));
  }

  // Un código que no esté en la tabla se muestra CRUDO, no se descarta: mejor
  // un "xx" visible que un idioma que el proveedor puso y no aparece.
  final langs = _codeList(business['languages'])
      .map((c) => _languages[c] ?? c)
      .toList();
  if (langs.isNotEmpty) {
    rows.add((
      kind: BusinessDetailKind.languages,
      label: 'Idiomas',
      value: langs.join(', '),
    ));
  }

  final pays = _codeList(business['payment_methods'])
      .map((c) => _paymentMethods[c] ?? c)
      .toList();
  if (pays.isNotEmpty) {
    rows.add((
      kind: BusinessDetailKind.payments,
      label: 'Pagos',
      value: pays.join(', '),
    ));
  }

  final warranty = (business['warranty'] as String?)?.trim();
  if (warranty != null && warranty.isNotEmpty) {
    rows.add((
      kind: BusinessDetailKind.warranty,
      label: 'Garantía',
      value: warranty,
    ));
  }

  return rows;
}

String? _hoursKey(Map<String, dynamic>? h) {
  final open = h?['open'] as String?;
  final close = h?['close'] as String?;
  if (open == null || close == null || open.isEmpty || close.isEmpty) {
    return null;
  }
  return '$open-$close';
}

String _toAmPm(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts.first);
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (h == null || m == null) return time;
  final suffix = h >= 12 ? 'PM' : 'AM';
  // `h % 12 || 12` de la web: medianoche y mediodía son las 12, no las 0.
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display:${m.toString().padLeft(2, '0')} $suffix';
}

/// Resume el horario semanal en una línea: agrupa días CONSECUTIVOS con el
/// mismo tramo y los expresa como rango a partir de tres ("lunes a viernes
/// 8:00 AM a 5:00 PM"); con menos, los lista uno a uno. La nota se pega al
/// final tras " · ". `null` = no hay nada que decir.
String? summarizeHours(Map<String, dynamic>? hours) {
  if (hours == null) return null;

  // Agrupación por tramos iguales consecutivos. Un día cerrado (clave nula)
  // rompe el grupo igual que un horario distinto.
  final groups = <({int start, int end, Map<String, dynamic>? hours})>[];
  for (var i = 0; i < _days.length; i++) {
    final current = (hours[_days[i].$1] as Map?)?.cast<String, dynamic>();
    if (groups.isNotEmpty && _hoursKey(groups.last.hours) == _hoursKey(current)) {
      final last = groups.removeLast();
      groups.add((start: last.start, end: i, hours: last.hours));
    } else {
      groups.add((start: i, end: i, hours: current));
    }
  }

  final segments = <String>[];
  for (final g in groups) {
    final key = _hoursKey(g.hours);
    if (key == null) continue;
    final range =
        '${_toAmPm(g.hours!['open'] as String)} a ${_toAmPm(g.hours!['close'] as String)}';
    if (g.end - g.start + 1 >= 3) {
      segments.add(
          '${_days[g.start].$2.toLowerCase()} a ${_days[g.end].$2.toLowerCase()} $range');
    } else {
      for (var i = g.start; i <= g.end; i++) {
        segments.add('${_days[i].$2.toLowerCase()} $range');
      }
    }
  }

  final notes = (hours['notes'] as String?)?.trim();
  if (segments.isEmpty && (notes == null || notes.isEmpty)) return null;

  final summary =
      segments.join(', ') + (notes != null && notes.isNotEmpty ? ' · $notes' : '');
  final clean = summary.startsWith(' · ') ? summary.substring(3) : summary;
  return clean.isEmpty
      ? null
      : clean[0].toUpperCase() + clean.substring(1);
}
