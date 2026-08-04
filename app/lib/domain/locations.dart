/// Catalogo de ubicaciones — pais -> ciudad (provincia) -> lista de sectores.
///
/// Portado 1:1 de `src/mocks/locations.ts` (web), mismo shape
/// `Record<pais, Record<ciudad, string[]>>`. Enfocado en Republica Dominicana;
/// extender segun haga falta. Los nombres propios de lugares llevan sus
/// tildes exactas del original — la regla de "sin tildes" del repo es para
/// comentarios, no para datos.
library;

const Map<String, Map<String, List<String>>> kLocations = {
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
    'Santo Domingo Oeste': [
      'Manoguayabo',
      'Pantoja',
      'Buenos Aires de Herrera',
    ],
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

/// Paises del catalogo, en el orden declarado.
final List<String> kCountries = kLocations.keys.toList();

/// Ciudades (provincias) de un pais. Lista vacia si el pais no esta en el
/// catalogo — nunca lanza, para que el Autocomplete de texto libre siga
/// funcionando aunque el pais no este mapeado.
List<String> citiesFor(String country) => kLocations[country]?.keys.toList() ?? const [];

/// Sectores de una ciudad dentro de un pais. Lista vacia si el pais o la
/// ciudad no estan en el catalogo — el caso real que motiva este plan: un
/// sector real (p. ej. "Parque del Este") puede no estar en la lista, y el
/// Autocomplete debe aceptarlo igual como texto libre.
List<String> sectorsFor(String country, String city) =>
    kLocations[country]?[city] ?? const [];
