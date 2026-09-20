import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/features/client/catalog_articulos.dart';

void main() {
  test('negocioCatalogoDe: verificado = identidad o negocio', () {
    const b = (
      name: 'getto',
      logoUrl: null,
      whatsappVerified: true,
      identityVerified: false,
      businessVerified: true,
      hasPhysicalLocation: true,
      description: 'Electrónica',
      city: 'SDE',
    );
    final n = negocioCatalogoDe(b);
    expect(n.verificado, isTrue);
    expect(n.city, 'SDE');
    expect(n.description, 'Electrónica');
    expect(n.hasPhysicalLocation, isTrue);
  });
  test('mergeCatalogRatings también hornea la reputación en un paquete', () {
    final k = paqueteComoItem({
      'id': 'k',
      'business_id': 'b1',
      'name': 'Chicha',
      'price': 3000,
      'items': const [],
      'image_url': null,
    });
    final out = mergeCatalogRatings([k], {'b1': (avg: 9.0, count: 2)});
    expect(out.single['avg_rating'], 9.0);
    expect(out.single['kind'], 'paquete');
  });

  group('catalogSearchPattern — paridad con searchPattern de la web', () {
    test('pliega tildes y mayusculas y envuelve en comodines', () {
      expect(catalogSearchPattern('Instalación'), '%instalacion%');
      expect(catalogSearchPattern('  Máquina  '), '%maquina%');
    });
    test('quita los comodines de LIKE y la coma, conserva los paréntesis', () {
      // `%` `_` `*` son comodines de LIKE/PostgREST; `,` parte filtros de or=(...).
      expect(catalogSearchPattern('taladro (grande)'), '%taladro (grande)%');
      expect(catalogSearchPattern('50%_'), '%50%');
      expect(catalogSearchPattern('a*b'), '%a b%');
    });
    test('con menos de 2 caracteres utiles no filtra', () {
      expect(catalogSearchPattern('a'), isNull);
      expect(catalogSearchPattern('***'), isNull);
      expect(catalogSearchPattern(null), isNull);
      expect(catalogSearchPattern('   '), isNull);
      expect(catalogSearchPattern('ab'), '%ab%');
    });
  });

  group(
    'catalogFiltroDeTexto (M-3): un patrón nulo NUNCA es "sin resultados"',
    () {
      // Antes de la Task 3 la app hacía `ilike` crudo y un carácter SÍ
      // casaba: `catalogProducts` traducía `pattern == null` con búsqueda no
      // vacía a `return const []`, una regresión no declarada. Paridad con
      // la web (`searchPattern` de `src/lib/searchTerm.ts`: "null significa
      // no apliques el filtro"): con menos de 2 caracteres se enseña el
      // catálogo COMPLETO, igual que sin búsqueda.
      test('un carácter ("a") ⇒ NO filtra (catálogo completo)', () {
        final r = catalogFiltroDeTexto('a');
        expect(r.filtrar, isFalse);
        expect(r.patron, isNull);
      });

      test('término vacío ⇒ NO filtra', () {
        final r = catalogFiltroDeTexto('');
        expect(r.filtrar, isFalse);
        expect(r.patron, isNull);
      });

      test('sin término (null) ⇒ NO filtra', () {
        final r = catalogFiltroDeTexto(null);
        expect(r.filtrar, isFalse);
        expect(r.patron, isNull);
      });

      test('solo símbolos ("***") ⇒ NO filtra (no "sin resultados")', () {
        final r = catalogFiltroDeTexto('***');
        expect(r.filtrar, isFalse);
        expect(r.patron, isNull);
      });

      test('término útil (2+ caracteres) ⇒ SÍ filtra con su patrón', () {
        final r = catalogFiltroDeTexto('ab');
        expect(r.filtrar, isTrue);
        expect(r.patron, '%ab%');
      });
    },
  );
}
