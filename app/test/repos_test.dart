import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/domain/pricing.dart';

/// Blinda el hallazgo de revisión de Task 4: "Negocio verificado" debe salir
/// SOLO de `provider_businesses.business_verified_at` (el RNC, revisado por
/// un admin), nunca de `account_verifications.whatsapp_verified_at` (el OTP
/// de WhatsApp del negocio, una credencial distinta). Si un futuro cambio
/// vuelve a colgar el sello del WhatsApp, este test revienta.
void main() {
  group('businessVerifiedFrom', () {
    test('true cuando business_verified_at tiene fecha', () {
      expect(
        businessVerifiedFrom({'business_verified_at': '2026-01-01T00:00:00Z'}),
        isTrue,
      );
    });

    test('false cuando business_verified_at es null', () {
      expect(businessVerifiedFrom({'business_verified_at': null}), isFalse);
    });

    test(
      'false aunque el WhatsApp del negocio esté confirmado, si business_verified_at es null',
      () {
        // Este es el caso exacto del bug arreglado: un negocio que solo
        // confirmó su WhatsApp (nunca aprobado por RNC) NO debe verse
        // "Negocio verificado".
        expect(
          businessVerifiedFrom({
            'business_verified_at': null,
            'whatsapp_verified_at': '2026-01-01T00:00:00Z',
          }),
          isFalse,
        );
      },
    );

    test(
      'true cuando business_verified_at tiene fecha aunque falte la clave whatsapp_verified_at',
      () {
        // Y el caso inverso: un negocio con RNC aprobado por el admin pero
        // sin (o antes de) el OTP de WhatsApp del negocio SÍ debe verse
        // "Negocio verificado" — la web lo marca igual.
        expect(
          businessVerifiedFrom({'business_verified_at': '2026-02-02T00:00:00Z'}),
          isTrue,
        );
      },
    );
  });

  group('sanitizeCatalogSearchTerm', () {
    test('reemplaza % y , por espacio (paridad con la web)', () {
      expect(sanitizeCatalogSearchTerm('50%, taladro'), '50   taladro');
    });

    test('un término sin caracteres especiales queda igual', () {
      expect(sanitizeCatalogSearchTerm('taladro inalámbrico'),
          'taladro inalámbrico');
    });
  });

  group('providerInbox', () {
    // Bug arreglado 2026-07-19 (Task 9): `providerInbox()` descartaba las
    // filas `source == 'store'` que `get_provider_inbox_unified` YA
    // devuelve — el proveedor nunca veía quién tocó "Me interesa" en su
    // catálogo. `fetcher` es inyectable (mismo patrón que `ProfileStore.loader`
    // en `profile_avatar_button.dart`) para ejercitar el código real que llama
    // a la RPC sin red. Si alguien reintroduce un filtro por `source` — inline
    // o encadenado tras la llamada — este test debe fallar.
    test('devuelve filas de "marketplace" y "store" sin filtrar', () async {
      final fakeRows = [
        {'source': 'marketplace', 'id': '1'},
        {'source': 'store', 'id': '2'},
      ];
      final result = await providerInbox(fetcher: (_) async => fakeRows);
      expect(result, hasLength(2));
      expect(result.map((r) => r['source']),
          containsAll(['marketplace', 'store']));
    });

    test('lista vacía se queda vacía', () async {
      final result = await providerInbox(fetcher: (_) async => const []);
      expect(result, isEmpty);
    });

    test('pasa el `kind` recibido al fetcher', () async {
      String? seen;
      await providerInbox(
        kind: 'producto',
        fetcher: (k) async {
          seen = k;
          return const [];
        },
      );
      expect(seen, 'producto');
    });
  });

  group('productInterestUnlockCost', () {
    test('es 1 — paridad con PRODUCT_INTEREST_COST de la web', () {
      expect(productInterestUnlockCost, 1);
    });
  });

  group('parseBusinessReview', () {
    test('mapea rating, comentario y fecha', () {
      final r = parseBusinessReview({
        'rating': 4,
        'comment': '  Excelente servicio  ',
        'created_at': '2026-07-01T12:00:00Z',
      });
      expect(r.rating, 4.0);
      expect(r.comment, 'Excelente servicio'); // recortado
      expect(r.createdAt.toUtc(), DateTime.utc(2026, 7, 1, 12));
    });

    test('comentario vacío o solo espacios queda null', () {
      expect(parseBusinessReview({'rating': 5, 'comment': '   '}).comment, isNull);
      expect(parseBusinessReview({'rating': 5, 'comment': null}).comment, isNull);
    });

    test('rating ausente cae a 0 y fecha inválida a epoch', () {
      final r = parseBusinessReview({'comment': 'x'});
      expect(r.rating, 0.0);
      expect(r.createdAt.millisecondsSinceEpoch, 0);
    });
  });

  group('partitionStoreItems', () {
    test('separa por kind: servicio a servicios, el resto a productos', () {
      final (prods, servs) = partitionStoreItems([
        {'id': '1', 'kind': 'producto'},
        {'id': '2', 'kind': 'servicio'},
        {'id': '3', 'kind': null}, // sin kind cuenta como producto
      ]);
      expect(prods.map((e) => e['id']), ['1', '3']);
      expect(servs.map((e) => e['id']), ['2']);
    });

    test('lista vacía devuelve dos listas vacías', () {
      final (prods, servs) = partitionStoreItems([]);
      expect(prods, isEmpty);
      expect(servs, isEmpty);
    });
  });
}
