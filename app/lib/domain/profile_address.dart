/// Composición de la dirección del perfil — paridad con el `useEffect` de
/// `InterestConfirmDialog.tsx` (web): `address` completo gana si existe; si
/// no, se arma con `street street_number, sector, city`. Puro, sin Supabase.
library;

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
