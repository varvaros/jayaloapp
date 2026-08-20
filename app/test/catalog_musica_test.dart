import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/catalog.dart';

/// Paridad del catálogo de categorías con la web y con la BD.
///
/// BUG QUE CIERRA (auditoría 2026-07-30): `musica` existía en `public.rubros`
/// con 13 rubros y la IA la ofrecía, pero faltaba en los DOS catálogos de
/// cliente. En la app eso dejaba `categoryNameById('musica') == null`, así que
/// el rótulo salía VACÍO en `catalog_screen`, `my_business_screen` y
/// `product_list_card`.
///
/// La lista de abajo es el espejo de `kCategories` de
/// `jayalo-main/src/mocks/categories.ts`. Si la web agrega una categoría y aquí
/// no, este test falla — que es justo la señal que faltó la vez pasada.
void main() {
  // 45 desde el 2026-08-20 (catálogo del PO): entran `arquitectura`,
  // `inmobiliaria`, `turismo`, `rrhh`, `empresariales` y `seguros`, y sale
  // `editorial` — sus 6 rubros se mudaron a `redaccion` conservando su id.
  const idsEsperados = <String>{
    'agricultura', 'arquitectura', 'arte', 'autos', 'belleza', 'cerrajeria',
    'climatizacion', 'construccion', 'contabilidad', 'contenido', 'deportes',
    'educacion', 'electricidad', 'electronica', 'empresariales', 'eventos',
    'ferreteria', 'fotografia', 'gastronomia', 'hogar', 'inmobiliaria',
    'investigacion', 'jardineria', 'joyeria', 'legal', 'limpieza', 'locucion',
    'maquinarias', 'marketing', 'mascotas', 'medios', 'mudanzas', 'musica',
    'pintura', 'plomeria', 'redaccion', 'relaciones_publicas', 'ropa', 'rrhh',
    'salud', 'seguridad', 'seguros', 'servicios', 'tecnologia', 'turismo',
  };

  test('el catálogo tiene exactamente las categorías de la web', () {
    final ids = kCategories.map((c) => c.id).toSet();
    expect(ids.difference(idsEsperados), isEmpty,
        reason: 'hay categorías en la app que la web no tiene');
    expect(idsEsperados.difference(ids), isEmpty,
        reason: 'faltan categorías que la web sí tiene');
  });

  test('no hay ids duplicados', () {
    final ids = kCategories.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('toda categoría resuelve a un nombre visible', () {
    for (final c in kCategories) {
      expect(categoryNameById(c.id), isNotNull, reason: 'sin nombre: ${c.id}');
      expect(categoryNameById(c.id), isNotEmpty);
    }
  });

  test('musica resuelve (regresión: devolvía null y el rótulo salía vacío)', () {
    expect(categoryNameById('musica'), 'Música');
  });

  test('una categoría inexistente sigue devolviendo null', () {
    expect(categoryNameById('no_existe'), isNull);
    expect(categoryNameById(null), isNull);
  });
}
