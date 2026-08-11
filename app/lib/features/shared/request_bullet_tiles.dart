import 'package:flutter/material.dart';

/// Convierte los bullets de la IA («Producto: Sillas plásticas apilables») en
/// filas para `detailTileBlock` — plantilla aprobada PO 2026-08-11: los datos
/// de una solicitud se leen igual que los de una oferta o un producto del
/// catálogo (tarjeta horizontal con ícono en pastilla, etiqueta arriba, valor
/// debajo).
///
/// Un bullet es "convertible" cuando tiene la forma `Etiqueta: valor` con una
/// etiqueta corta; lo que no encaje (frases largas, texto sin dos puntos)
/// sobrevive ÍNTEGRO en `freeText` — nunca se pierde nada de lo que la IA
/// escribió, mismo criterio que `freeTextFromOfferMessage`.
({List<(IconData, String, String, bool)> rows, List<String> freeText})
    requestBulletRows(List<String> bullets) {
  final rows = <(IconData, String, String, bool)>[];
  final free = <String>[];
  for (final b in bullets) {
    final t = b.trim();
    if (t.isEmpty) continue;
    final i = t.indexOf(':');
    // Etiqueta de más de 28 caracteres = casi seguro una frase con dos puntos
    // dentro, no un dato «Etiqueta: valor» — va entera al texto libre.
    if (i <= 0 || i > 28 || i + 1 >= t.length) {
      free.add(t);
      continue;
    }
    final label = t.substring(0, i).trim();
    final value = t.substring(i + 1).trim();
    if (label.isEmpty || value.isEmpty) {
      free.add(t);
      continue;
    }
    rows.add((_iconFor(label), label, value, false));
  }
  return (rows: rows, freeText: free);
}

/// Ícono por etiqueta, alineado con los que ya usan la hoja de oferta y el
/// detalle del catálogo (Estado=caja, Marca=tag, Color=paleta, Entrega=reloj,
/// Envío/logística=camión…) para que el mismo concepto lleve el mismo dibujo
/// en toda la app. Etiqueta desconocida → ícono neutro de nota.
IconData _iconFor(String label) {
  final l = _fold(label);
  if (l.contains('producto') || l.contains('articulo')) {
    return Icons.inventory_2_outlined;
  }
  if (l.contains('servicio')) return Icons.handyman_outlined;
  if (l.contains('cantidad') || l.contains('unidades')) {
    return Icons.layers_outlined;
  }
  if (l.contains('marca')) return Icons.sell_outlined;
  if (l.contains('tipo de compra') || l.contains('frecuencia')) {
    return Icons.autorenew_rounded;
  }
  if (l.contains('logistica') || l.contains('envio')) {
    return Icons.local_shipping_outlined;
  }
  if (l.contains('ubicacion') ||
      l.contains('zona') ||
      l.contains('lugar') ||
      l.contains('direccion')) {
    return Icons.place_outlined;
  }
  if (l.contains('presupuesto') || l.contains('precio')) {
    return Icons.payments_outlined;
  }
  if (l.contains('urgencia') ||
      l.contains('cuando') ||
      l.contains('fecha') ||
      l.contains('entrega')) {
    return Icons.schedule_outlined;
  }
  if (l.contains('color')) return Icons.palette_outlined;
  if (l.contains('garantia')) return Icons.gpp_good_outlined;
  if (l.contains('estado') || l.contains('condicion')) {
    return Icons.inventory_2_outlined;
  }
  if (l.contains('empaque')) return Icons.all_inbox_outlined;
  return Icons.notes_outlined;
}

/// Minúsculas y sin tildes, para que «Logística» y «logistica» casen igual.
String _fold(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunaeiouun';
  var out = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}
