/// Formato de dinero de la app: RD$ + entero con separador de miles.
///
/// Salió de `features/client/request_status_screen.dart`, donde vivía dentro
/// de una pantalla; lo necesitan también las estadísticas del proveedor y una
/// pantalla de proveedor no debe importar una de cliente.
library;

String fmtRD(num? v) => v == null
    ? ''
    : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
