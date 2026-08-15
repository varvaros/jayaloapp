import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/profile_sections.dart';

/// Paridad exacta con `profileSections` de `src/lib/storefront.ts` (web,
/// jayalo-main) — casos copiados uno a uno de
/// `src/lib/storefront.test.ts` (describe("profileSections")), NO
/// reinterpretados: la paridad entre implementaciones se mide, no se razona
/// (lección del guard anti-elusión, donde TS y SQL divergían en 6
/// codepoints).
void main() {
  group('profileSections', () {
    test('técnico con solo servicios: una sección', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 0,
          serviceCount: 4,
          packageCount: 0,
        ),
        [ProfileSection.servicios],
      );
    });

    test('técnico que ADEMÁS vende un producto: se ve el producto', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 1,
          serviceCount: 4,
          packageCount: 0,
        ),
        [ProfileSection.servicios, ProfileSection.productos],
      );
    });

    test('regla anti-inferencia: offers dice servicios pero solo hay '
        'productos', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 3,
          serviceCount: 0,
          packageCount: 0,
        ),
        [ProfileSection.productos],
      );
    });

    test('tienda con productos y servicios: productos primero', () {
      expect(
        profileSections(
          offers: 'productos',
          productCount: 9,
          serviceCount: 2,
          packageCount: 0,
        ),
        [ProfileSection.productos, ProfileSection.servicios],
      );
    });

    test('los paquetes cuentan como sección propia', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 0,
          serviceCount: 0,
          packageCount: 2,
        ),
        [ProfileSection.paquetes],
      );
    });

    test('todo vacío: lista vacía, no una sección fantasma (fix 2026-08-14 '
        '— espejo del fix de la web en storefront.ts)', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 0,
          serviceCount: 0,
          packageCount: 0,
        ),
        <ProfileSection>[],
      );
      expect(
        profileSections(
          offers: 'productos',
          productCount: 0,
          serviceCount: 0,
          packageCount: 0,
        ),
        <ProfileSection>[],
      );
    });

    test('offers nulo o desconocido cae al orden por defecto', () {
      expect(
        profileSections(
          offers: null,
          productCount: 1,
          serviceCount: 1,
          packageCount: 1,
        ),
        [ProfileSection.productos, ProfileSection.servicios, ProfileSection.paquetes],
      );
      expect(
        profileSections(
          offers: 'loquesea',
          productCount: 0,
          serviceCount: 0,
          packageCount: 0,
        ),
        <ProfileSection>[],
      );
    });

    test('el dueño ve TODAS las secciones aunque estén vacías, en el orden '
        'de offers', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 0,
          serviceCount: 2,
          packageCount: 0,
          includeEmpty: true,
        ),
        [ProfileSection.servicios, ProfileSection.paquetes, ProfileSection.productos],
      );
    });

    test('el visitante, en ese mismo caso, sigue viendo solo lo que tiene '
        'filas', () {
      expect(
        profileSections(
          offers: 'servicios',
          productCount: 0,
          serviceCount: 2,
          packageCount: 0,
        ),
        [ProfileSection.servicios],
      );
    });

    test('includeEmpty con offers desconocido usa el orden por defecto '
        'completo', () {
      expect(
        profileSections(
          offers: null,
          productCount: 0,
          serviceCount: 0,
          packageCount: 0,
          includeEmpty: true,
        ),
        [ProfileSection.productos, ProfileSection.servicios, ProfileSection.paquetes],
      );
    });
  });
}
