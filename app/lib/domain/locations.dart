/// Catálogo en cascada país → ciudad/provincia → sector. Port 1:1 de
/// `src/mocks/locations.ts` de jayalo-main, donde alimenta el selector de zona
/// del wizard de proveedor. Todo cambio del catálogo debe aplicarse en AMBOS
/// repos: son dos copias del mismo dato, no hay tabla en la BD que las una.
///
/// Puro y sin Flutter, para poder testear el filtrado sin montar widgets.
library;

const kLocations = <String, Map<String, List<String>>>{
  'República Dominicana': {
    'Distrito Nacional': [
      'Naco',
      'Piantini',
      'Bella Vista',
      'Gazcue',
      'Los Cacicazgos',
      'Ensanche La Fe',
      'Villa Mella',
      'Villa Consuelo',
      'Zona Colonial',
    ],
    'Santo Domingo': [
      'Los Alcarrizos',
      'Boca Chica',
      'San Antonio de Guerra',
      'Pedro Brand',
    ],
    'Santo Domingo Este': [
      'Alma Rosa',
      'Los Mina',
      'Villa Duarte',
      'San Isidro',
      'Invivienda',
      'Ensanche Ozama',
    ],
    'Santo Domingo Norte': ['Villa Mella', 'Sabana Perdida', 'La Victoria'],
    'Santo Domingo Oeste': ['Manoguayabo', 'Pantoja', 'Buenos Aires de Herrera'],
    'Santiago': [
      'Centro',
      'Los Jardines',
      'Cerros de Gurabo',
      'La Trinitaria',
      'Pekín',
      'Villa Olga',
    ],
    'Azua': ['Azua de Compostela', 'Las Charcas', 'Padre Las Casas', 'Sabana Yegua'],
    'Bahoruco': ['Neiba', 'Galván', 'Tamayo', 'Villa Jaragua'],
    'Barahona': ['Santa Cruz de Barahona', 'Cabral', 'Enriquillo', 'Paraíso'],
    'Dajabón': ['Dajabón', 'Loma de Cabrera', 'Partido', 'Restauración'],
    'Duarte': ['San Francisco de Macorís', 'Castillo', 'Pimentel', 'Villa Riva'],
    'El Seibo': ['Santa Cruz de El Seibo', 'Miches'],
    'Elías Piña': ['Comendador', 'Bánica', 'Hondo Valle', 'Pedro Santana'],
    'Espaillat': ['Moca', 'Gaspar Hernández', 'Cayetano Germosén', 'Jamao al Norte'],
    'Hato Mayor': ['Hato Mayor del Rey', 'Sabana de la Mar', 'El Valle'],
    'Hermanas Mirabal': ['Salcedo', 'Tenares', 'Villa Tapia'],
    'Independencia': ['Jimaní', 'Duvergé', 'La Descubierta', 'Postrer Río'],
    'La Altagracia': [
      'Higüey',
      'Punta Cana',
      'Bávaro',
      'Verón',
      'San Rafael del Yuma',
    ],
    'La Romana': ['La Romana', 'Guaymate', 'Villa Hermosa', 'Caleta'],
    'La Vega': ['Concepción de La Vega', 'Jarabacoa', 'Constanza', 'Jima Abajo'],
    'María Trinidad Sánchez': ['Nagua', 'Cabrera', 'El Factor', 'Río San Juan'],
    'Monseñor Nouel': ['Bonao', 'Maimón', 'Piedra Blanca'],
    'Monte Cristi': [
      'San Fernando de Monte Cristi',
      'Castañuelas',
      'Guayubín',
      'Villa Vásquez',
    ],
    'Monte Plata': [
      'Monte Plata',
      'Bayaguana',
      'Sabana Grande de Boyá',
      'Yamasá',
    ],
    'Pedernales': ['Pedernales', 'Oviedo'],
    'Peravia': ['Baní', 'Nizao'],
    'Puerto Plata': [
      'San Felipe de Puerto Plata',
      'Sosúa',
      'Cabarete',
      'Imbert',
      'Luperón',
      'Altamira',
    ],
    'Samaná': ['Santa Bárbara de Samaná', 'Las Terrenas', 'Sánchez'],
    'Sánchez Ramírez': ['Cotuí', 'Cevicos', 'Fantino', 'La Mata'],
    'San Cristóbal': [
      'San Cristóbal',
      'Bajos de Haina',
      'Cambita Garabitos',
      'Villa Altagracia',
      'Yaguate',
    ],
    'San José de Ocoa': ['San José de Ocoa', 'Sabana Larga', 'Rancho Arriba'],
    'San Juan': [
      'San Juan de la Maguana',
      'Bohechío',
      'El Cercado',
      'Las Matas de Farfán',
    ],
    'San Pedro de Macorís': [
      'San Pedro de Macorís',
      'Juan Dolio',
      'Los Llanos',
      'Consuelo',
      'Quisqueya',
    ],
    'Santiago Rodríguez': ['Sabaneta', 'Monción', 'Villa Los Almácigos'],
    'Valverde': ['Mao', 'Esperanza', 'Laguna Salada'],
  },
};

List<String> get kCountries => kLocations.keys.toList();

/// Ciudades/provincias de un país. Lista vacía si el país no está en el árbol.
List<String> citiesOf(String? country) =>
    (country == null ? null : kLocations[country])?.keys.toList() ?? const [];

/// Sectores de una ciudad dentro de un país.
List<String> sectorsOf(String? country, String? city) {
  if (country == null || city == null) return const [];
  return kLocations[country]?[city] ?? const [];
}

/// Busca en el árbol el par (ciudad, sector) que corresponde a lo que devolvió
/// el reverse geocoding. El geocoder no conoce nuestro catálogo: puede dar
/// "Santo Domingo Este" como `locality` y "Alma Rosa" como `subLocality`, pero
/// también variantes con tildes distintas o mayúsculas. Se compara normalizado
/// y solo se acepta lo que EXISTE en el catálogo — así los selectores nunca
/// quedan con un valor que el usuario no podría haber elegido a mano.
({String? city, String? sector}) matchLocation({
  required String country,
  String? locality,
  String? subLocality,
}) {
  final tree = kLocations[country];
  if (tree == null) return (city: null, sector: null);

  String? city;
  final loc = normalizeLoose(locality);
  if (loc.isNotEmpty) {
    for (final c in tree.keys) {
      if (normalizeLoose(c) == loc) {
        city = c;
        break;
      }
    }
  }

  final sub = normalizeLoose(subLocality);
  // Con ciudad resuelta, el sector solo puede salir de ESA ciudad.
  if (city != null && sub.isNotEmpty) {
    for (final s in tree[city]!) {
      if (normalizeLoose(s) == sub) return (city: city, sector: s);
    }
    return (city: city, sector: null);
  }

  // Sin ciudad: a veces el geocoder mete en `locality` lo que para nosotros es
  // un sector (p. ej. "Naco"). Se busca el sector en todo el país y la ciudad
  // se deduce de él.
  for (final candidate in [sub, loc]) {
    if (candidate.isEmpty) continue;
    for (final entry in tree.entries) {
      for (final s in entry.value) {
        if (normalizeLoose(s) == candidate) return (city: entry.key, sector: s);
      }
    }
  }
  return (city: city, sector: null);
}

/// Minúsculas y sin tildes, para comparar y BUSCAR: "Bánica" ≡ "banica".
String normalizeLoose(String? v) {
  final t = (v ?? '').trim().toLowerCase();
  if (t.isEmpty) return '';
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buf = StringBuffer();
  for (final ch in t.split('')) {
    final i = from.indexOf(ch);
    buf.write(i == -1 ? ch : to[i]);
  }
  return buf.toString();
}
