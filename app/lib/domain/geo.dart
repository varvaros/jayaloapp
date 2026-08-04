/// Dominio de direcciones. Puro y testeable: aqui no entra Flutter ni la red.
///
/// Sustituye a `formatPlacemarkAddress`, que unia lo que devolvia el
/// geocodificador NATIVO de Android. En RD ese geocoder devuelve la via grande
/// mas cercana y el municipio, asi que la direccion salia tan vaga que no
/// servia ("Autopista Las Americas, Santo Domingo Este" para alguien de Parque
/// del Este). Ahora los campos vienen estructurados del endpoint de la web.
class GeocodedPlace {
  const GeocodedPlace({
    this.country = '',
    this.city = '',
    this.cityInCatalog = false,
    this.sector = '',
    this.sectorInCatalog = false,
    this.street = '',
    this.streetNumber = '',
    this.addressLine = '',
  });

  final String country;
  final String city;
  final bool cityInCatalog;
  final String sector;
  final bool sectorInCatalog;
  final String street;
  final String streetNumber;
  final String addressLine;

  static const empty = GeocodedPlace();

  factory GeocodedPlace.fromJson(Map<String, dynamic> j) => GeocodedPlace(
        country: (j['country'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        cityInCatalog: (j['cityInCatalog'] as bool?) ?? false,
        sector: (j['sector'] as String?) ?? '',
        sectorInCatalog: (j['sectorInCatalog'] as bool?) ?? false,
        street: (j['street'] as String?) ?? '',
        streetNumber: (j['streetNumber'] as String?) ?? '',
        addressLine: (j['addressLine'] as String?) ?? '',
      );
}

/// Une los componentes en una linea legible, sin vacios ni duplicados.
String composeAddressLine({
  required String street,
  required String streetNumber,
  required String sector,
  required String city,
}) {
  final line1 = [street.trim(), streetNumber.trim()]
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();
  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [line1, sector.trim(), city.trim()]) {
    if (raw.isEmpty || seen.contains(raw.toLowerCase())) continue;
    seen.add(raw.toLowerCase());
    parts.add(raw);
  }
  return parts.join(', ');
}

/// Enlace universal al mapa.
///
/// A proposito NO se usa el esquema `geo:`: lo entiende Android, pero no el
/// navegador ni WhatsApp, y este texto viaja en un chat que el otro puede abrir
/// donde sea. El de Google Maps abre la app nativa si esta instalada y el
/// navegador si no.
String mapsLinkFor(double lat, double lng) =>
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

/// Separa el enlace del mapa del resto del cuerpo de un mensaje de direccion,
/// para que la burbuja pinte texto arriba y un boton abajo en vez de una URL
/// cruda de 60 caracteres.
({String text, String? mapUrl}) splitMapLink(String body) {
  final lines = body.split('\n');
  final i = lines.indexWhere(
      (l) => l.trim().startsWith('https://www.google.com/maps/'));
  if (i == -1) return (text: body, mapUrl: null);
  final url = lines[i].trim();
  lines.removeAt(i);
  return (text: lines.join('\n').trimRight(), mapUrl: url);
}

/// Une los componentes de una dirección (de un Placemark) en una línea legible,
/// omitiendo vacíos y duplicados. Puro y testeable.
///
/// DEPRECATED: Usa composeAddressLine con campos estructurados en su lugar.
/// Esta funcion la retira la tarea 9 del plan de direcciones.
@Deprecated('Usa composeAddressLine en su lugar; esta funcion la retira la tarea 9')
String formatPlacemarkAddress({
  String? street,
  String? subLocality,
  String? locality,
  String? administrativeArea,
}) {
  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [street, subLocality, locality, administrativeArea]) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty || seen.contains(v.toLowerCase())) continue;
    seen.add(v.toLowerCase());
    parts.add(v);
  }
  return parts.join(', ');
}
