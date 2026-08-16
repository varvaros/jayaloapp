/// Composición de la dirección del perfil — paridad con el `useEffect` de
/// `InterestConfirmDialog.tsx` (web): `address` completo gana si existe; si
/// no, se arma con `street street_number, sector, city`. Puro, sin Supabase.
library;

/// Dirección de ENTREGA que se le enseña al proveedor.
///
/// No sirve `composeProfileAddress` aquí: aquella corta en seco si `address`
/// tiene algo, y desde que el alta de consumidor desglosó la dirección,
/// `address` guarda SOLO calle y número — el proveedor recibía "Calle Duarte
/// 45" sin ciudad ni sector, o sea una dirección a la que no se puede llegar.
/// Esta compone siempre la línea completa, venga de `address` o de
/// `street`+`street_number`, y no repite lo que ya esté escrito en la calle
/// (perfiles viejos guardaban la dirección entera ahí).
String? composeDeliveryAddress({
  String? address,
  String? street,
  String? streetNumber,
  String? sector,
  String? city,
}) {
  final addressTrim = address?.trim() ?? '';
  final streetLine = addressTrim.isNotEmpty
      ? addressTrim
      : ((street != null && street.trim().isNotEmpty)
          ? ((streetNumber != null && streetNumber.trim().isNotEmpty)
              ? '${street.trim()} ${streetNumber.trim()}'
              : street.trim())
          : '');

  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [streetLine, sector, city]) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) continue;
    final key = v.toLowerCase();
    // Un perfil antiguo puede traer "Calle 1, Naco, Santiago" entero en
    // `address`: sin esto, ciudad y sector saldrían repetidos detrás.
    if (seen.contains(key) || streetLine.toLowerCase().contains(key)) continue;
    seen.add(key);
    parts.add(v);
  }
  return parts.isEmpty ? null : parts.join(', ');
}

String? composeProfileAddress({
  String? address,
  String? street,
  String? streetNumber,
  String? sector,
  String? city,
}) {
  final addressTrim = address?.trim() ?? '';
  if (addressTrim.isNotEmpty) return addressTrim;

  final streetLine = (street != null && street.isNotEmpty)
      ? ((streetNumber != null && streetNumber.isNotEmpty)
          ? '$street $streetNumber'
          : street)
      : null;
  final parts = [streetLine, sector, city]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final composed = parts.join(', ').trim();
  return composed.isEmpty ? null : composed;
}
