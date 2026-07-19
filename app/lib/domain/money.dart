/// Formato de dinero de la app: RD$ + entero con separador de miles.
///
/// Salió de `features/client/request_status_screen.dart`, donde vivía dentro
/// de una pantalla; lo necesitan también las estadísticas del proveedor y una
/// pantalla de proveedor no debe importar una de cliente.
library;

String fmtRD(num? v) => v == null
    ? ''
    : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

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
