/// Categorías del marketplace — port de jayalo-main src/mocks/categories.ts
/// (la tabla `categories` de prod está VACÍA; la web usa este mismo mock; el
/// matching solicitud↔negocio es por slug de texto). Regenerar con el script
/// del plan (Task 3) si la web cambia la lista.
typedef Category = ({String id, String name});

/// Nombre visible de una categoría por su id (slug), o `null` si no existe —
/// equivalente móvil de `findCategoryById` de la web, para pintar el rótulo de
/// categoría en la tarjeta del catálogo. Mapa construido una sola vez.
final Map<String, String> _categoryNameById = {
  for (final c in kCategories) c.id: c.name,
};

String? categoryNameById(String? id) =>
    id == null ? null : _categoryNameById[id];

const List<Category> kCategories = [
  (id: 'autos', name: 'Autos'),
  (id: 'ferreteria', name: 'Ferretería'),
  (id: 'hogar', name: 'Hogar'),
  (id: 'electronica', name: 'Electrónica'),
  (id: 'ropa', name: 'Ropa y calzado'),
  (id: 'maquinarias', name: 'Maquinaria y equipos'),
  (id: 'plomeria', name: 'Plomería'),
  (id: 'electricidad', name: 'Electricidad'),
  (id: 'pintura', name: 'Pintura'),
  (id: 'eventos', name: 'Eventos'),
  (id: 'servicios', name: 'Servicios generales'),
  (id: 'belleza', name: 'Belleza'),
  (id: 'salud', name: 'Salud y bienestar'),
  (id: 'mascotas', name: 'Mascotas'),
  (id: 'mudanzas', name: 'Mudanzas y transporte'),
  (id: 'tecnologia', name: 'Tecnología e IT'),
  (id: 'educacion', name: 'Educación y cursos'),
  (id: 'gastronomia', name: 'Gastronomía y catering'),
  (id: 'construccion', name: 'Construcción'),
  (id: 'jardineria', name: 'Jardinería'),
  (id: 'limpieza', name: 'Limpieza'),
  (id: 'seguridad', name: 'Seguridad'),
  (id: 'legal', name: 'Legal'),
  (id: 'contabilidad', name: 'Contabilidad y finanzas'),
  (id: 'marketing', name: 'Marketing y publicidad'),
  (id: 'fotografia', name: 'Fotografía y video'),
  (id: 'agricultura', name: 'Agricultura'),
  (id: 'deportes', name: 'Deportes y fitness'),
  (id: 'arte', name: 'Arte y manualidades'),
  (id: 'joyeria', name: 'Joyería y relojería'),
  (id: 'cerrajeria', name: 'Cerrajería'),
  (id: 'climatizacion', name: 'Aire y refrigeración'),
  (id: 'medios', name: 'Medios y Periodismo'),
  (id: 'redaccion', name: 'Redacción y Corrección'),
  (id: 'relaciones_publicas', name: 'Relaciones Públicas'),
  (id: 'contenido', name: 'Contenido y Publicaciones'),
  (id: 'investigacion', name: 'Investigación'),
  // `editorial` se retiró el 2026-08-20: sus 6 rubros se mudaron a `redaccion`
  // conservando su id (decisión PO).
  (id: 'locucion', name: 'Locución y Presentación'),
  // `musica` existía en la BD (13 rubros) y la IA la ofrecía, pero faltaba en
  // los DOS catálogos de cliente (este y el de la web): `categoryNameById`
  // devolvía null y el rótulo salía vacío en catalog_screen, my_business_screen
  // y product_list_card. Peor: ningún proveedor podía elegirla, así que una
  // solicitud de música no le llegaba a nadie.
  (id: 'musica', name: 'Música'),

  // Las 6 del catálogo del PO (2026-08-20). Entran A LA VEZ que en la BD y que
  // en el mock de la web, por la misma razón que documenta `musica`.
  (id: 'arquitectura', name: 'Arquitectura y diseño'),
  (id: 'inmobiliaria', name: 'Inmobiliaria'),
  (id: 'turismo', name: 'Turismo'),
  (id: 'rrhh', name: 'Recursos humanos'),
  (id: 'empresariales', name: 'Servicios empresariales'),
  (id: 'seguros', name: 'Seguros y finanzas'),
];
