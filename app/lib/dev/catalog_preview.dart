/// Harness de pulido SOLO de desarrollo para la pestaña Catálogo.
///
/// No entra en la app: se corre a mano con
///   `flutter run -d <device> -t lib/dev/catalog_preview.dart`
/// para iterar el diseño de la rejilla del catálogo sin auth ni red real,
/// con datos deterministas que cubren los casos de borde (nombre de 2 líneas,
/// precio fijo/rango/"desde"/"Consultar precio", sin foto). Verificación por
/// screenshot en el Redmi. Borrar si molesta; no lo importa nada de producción.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../features/client/catalog_screen.dart';

/// Fotos cuadradas deterministas (semilla fija) para que el screenshot no
/// cambie entre corridas.
String _img(String seed) => 'https://picsum.photos/seed/$seed/500/500';

final _fake = <Map<String, dynamic>>[
  {
    'id': '1',
    'name': 'Taladro percutor inalámbrico 20V con maletín',
    'description':
        'Incluye 2 baterías, cargador rápido y set de 15 brocas. Ideal para concreto y madera.',
    'category_id': 'ferreteria',
    'image_urls': [_img('drill')],
    'price': 4850,
    'avg_rating': 8.7,
    'reviews_count': 34,
  },
  {
    'id': '2',
    'name': 'Corte de cabello a domicilio',
    'description':
        'Barbero profesional va a tu casa. Corte, barba y perfilado. Zona metropolitana.',
    'category_id': 'belleza',
    'image_urls': [_img('haircut')],
    'price_min': 500,
    'price_max': 1200,
    'avg_rating': 9.2,
    'reviews_count': 128,
  },
  {
    'id': '3',
    'name': 'Silla ergonómica de oficina',
    'description': 'Soporte lumbar ajustable, reposabrazos 3D, malla transpirable.',
    'category_id': 'hogar',
    'image_urls': [_img('chair')],
    'price': 12500,
    'avg_rating': 7.9,
    'reviews_count': 12,
  },
  {
    'id': '4',
    'name': 'Diseño de logo profesional para tu negocio',
    'description':
        'Entrega en 48h, 3 propuestas iniciales y archivos vectoriales listos para imprenta.',
    'category_id': 'marketing',
    'image_urls': [_img('logo')],
    'price_min': 3000,
    // Proveedor nuevo: sin reseñas todavía (la estrella no aparece).
    'avg_rating': 0,
    'reviews_count': 0,
  },
  {
    'id': '5',
    'name': 'Ramo de flores frescas surtidas',
    'description': 'Arreglo del día con flores de temporada. Entrega el mismo día.',
    'category_id': 'eventos',
    'image_urls': [_img('flowers')],
    'price': 950,
    'avg_rating': 9.6,
    'reviews_count': 210,
  },
  {
    'id': '6',
    'name': 'Reparación de aire acondicionado',
    'description': 'Diagnóstico, recarga de gas y mantenimiento. Split y de ventana.',
    'category_id': 'climatizacion',
    'image_urls': const <String>[],
    'price': null,
    'avg_rating': 8.1,
    'reviews_count': 47,
  },
  {
    'id': '7',
    'name': 'Zapatillas deportivas edición limitada',
    'description': 'Tallas 38–45. Originales, con caja. Envío a todo el país.',
    'category_id': 'ropa',
    'image_urls': [_img('shoes')],
    'price': 7200,
    'avg_rating': 8.9,
    'reviews_count': 63,
  },
  {
    'id': '8',
    'name': 'Clases de guitarra para principiantes',
    'description': 'Presencial o por videollamada. Primera clase de prueba gratis.',
    'category_id': 'educacion',
    'image_urls': [_img('guitar')],
    'price_min': 800,
    'avg_rating': 9.0,
    'reviews_count': 25,
  },
];

Future<List<Map<String, dynamic>>> _fakeFetch(
    {required String kind, String? search}) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return _fake;
}

void main() => runApp(MaterialApp(
      title: 'Catálogo preview',
      theme: jayaloTheme(Brightness.light),
      themeMode: ThemeMode.light,
      scrollBehavior: const JayaloScrollBehavior(),
      debugShowCheckedModeBanner: false,
      home: const CatalogView(fetch: _fakeFetch, actions: []),
    ));
