/// Formato de dinero de la app: RD$ + entero con separador de miles.
///
/// Salió de `features/client/request_status_screen.dart`, donde vivía dentro
/// de una pantalla; lo necesitan también las estadísticas del proveedor y una
/// pantalla de proveedor no debe importar una de cliente.
library;

String fmtRD(num? v) => v == null
    ? ''
    : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

/// Miles agrupados SIN símbolo ni decimales ("12000" → "12,000") — el formato
/// de los CAMPOS de precio al ofertar (pedido PO 2026-08-10: "unidades de
/// mil, sin .00").
String fmtMiles(num? v) => v == null
    ? ''
    : v
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// Lo escrito en un campo de precio ("5,000", "RD\$5000", "3000.50") → entero,
/// o null si está vacío / no numérico.
///
/// Contrato conservador nacido del BUG PO 08-09 (precio ×10): descartar todo
/// carácter no-dígito convertía "3000.0" en "30000". Los precios RD\$ son
/// enteros, así que un punto o coma ÚNICO seguido de 1-2 dígitos AL FINAL se
/// trata como separador DECIMAL y se redondea (`round()`, no trunca:
/// "3000.50" → 3001). Un punto/coma seguido de exactamente 3 dígitos sigue
/// siendo separador de MILES ("3.000"/"1,500" → 3000/1500); cualquier otro
/// caso cae al camino de solo-dígitos.
int? parseMiles(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (cleaned.isEmpty) return null;

  final decimal = RegExp(r'^(\d*)[.,](\d{1,2})$').firstMatch(cleaned);
  if (decimal != null) {
    final wholePart = decimal.group(1)!;
    final fracPart = decimal.group(2)!.padRight(2, '0');
    final whole = wholePart.isEmpty ? 0 : int.parse(wholePart);
    final cents = int.parse(fracPart);
    return ((whole * 100 + cents) / 100).round();
  }

  final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Etiqueta de precio de un producto/servicio del catálogo — paridad EXACTA
/// con `formatProductHitPrice` de la web (`ProductHitCard.tsx`): precio fijo
/// gana sobre el rango; si solo hay `price_min` es "desde"; sin ningún precio
/// es "Consultar precio" (nunca vacío, para no parecer un dato faltante).
String catalogPriceLabel(
    {required num? price, required num? priceMin, required num? priceMax}) {
  if (price != null) return fmtRD(price);
  if (priceMin != null && priceMax != null) {
    return '${fmtRD(priceMin)} - ${fmtRD(priceMax)}';
  }
  if (priceMin != null) return 'desde ${fmtRD(priceMin)}';
  return 'Consultar precio';
}

/// Etiqueta del PRESUPUESTO ESTIMADO de una solicitud (paridad con el detalle
/// web `$requestId.tsx`): rango "RD$X - RD$Y", "desde RD$X" o "hasta RD$Y".
/// Devuelve null si el cliente no puso presupuesto (para no pintar la fila).
String? requestBudgetLabel(num? min, num? max) {
  final lo = (min != null && min > 0) ? min : null;
  final hi = (max != null && max > 0) ? max : null;
  if (lo != null && hi != null) return '${fmtRD(lo)} - ${fmtRD(hi)}';
  if (lo != null) return 'desde ${fmtRD(lo)}';
  if (hi != null) return 'hasta ${fmtRD(hi)}';
  return null;
}
