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

  group('requestRequirementCols', () {
    test('nombra las cinco columnas de requisitos', () {
      for (final col in const [
        'with_shipping',
        'with_installation',
        'requires_evaluation',
        'requires_fiscal_receipt',
        'requires_state_supplier',
      ]) {
        expect(requestRequirementCols, contains(col), reason: 'falta $col');
      }
    });

    test('no lleva espacios: va concatenada dentro de un select de PostgREST', () {
      expect(requestRequirementCols, isNot(contains(' ')));
    });

    test('las cinco, separadas por coma, en este orden exacto', () {
      // Los dos tests de arriba pasarían igual si la constante se rompiera a
      // 'with_shippingwith_installation...' (sin comas): cada nombre sigue
      // siendo substring y no hay espacios. Este test fija la lista exacta que
      // resulta de partir por coma, así que una coma perdida SÍ lo revienta.
      expect(requestRequirementCols.split(','), [
        'with_shipping',
        'with_installation',
        'requires_evaluation',
        'requires_fiscal_receipt',
        'requires_state_supplier',
      ]);
    });
  });

  group('requirementsForRequests', () {
    test('con lista vacía devuelve mapa vacío SIN tocar la red', () async {
      // Sin este corto‑circuito el test reventaría al tocar `supa`, que no está
      // inicializado en un test de unidad. Que pase es la prueba de que existe.
      expect(await requirementsForRequests(const []), isEmpty);
    });
  });

  group('offerFields', () {
    // El mapa lo COMPARTEN makeOffer y updateOffer. El UPDATE de estas dos
    // columnas está denegado en la base a propósito (son una foto del momento
    // de ofertar), así que si se colaran aquí, PostgREST tumbaría la fila
    // entera y "mejorar oferta" dejaría de funcionar del todo — un fallo que
    // no aparece hasta que alguien edita una oferta. Este test es la única
    // barrera automática que existe contra eso.
    test('NO lleva las capacidades del proveedor', () {
      final fields = offerFields(price: 100.0, message: 'hola');
      expect(fields.containsKey('has_fiscal_receipt'), isFalse);
      expect(fields.containsKey('is_state_supplier'), isFalse);
    });

    test('sigue llevando lo que sí es editable', () {
      final fields = offerFields(price: 100.0, message: 'hola');
      expect(fields['price'], 100.0);
      expect(fields['message'], 'hola');
      expect(fields.containsKey('offers_shipping'), isTrue);
    });
  });

  group('packagePayload (hallazgo C-1, revisión final)', () {
    // `provider_packages.price` es NOT NULL DEFAULT 0: guardar un paquete
    // con el precio en blanco (price: null desde PackageEditorScreen) mandaba
    // 'price': null explícito y el INSERT/UPDATE reventaba con 23502. El
    // payload debe llevar 0 en su lugar.
    test('precio vacío (null) → el payload lleva price 0, no null', () {
      final payload = packagePayload(
        businessId: 'biz-1',
        name: 'Plan Básico',
        items: const ['Corte'],
      );
      expect(payload['price'], 0);
    });

    test('con precio, el payload lo conserva tal cual', () {
      final payload = packagePayload(
        businessId: 'biz-1',
        name: 'Plan Full',
        price: 1500,
        items: const ['Corte', 'Lavado'],
      );
      expect(payload['price'], 1500);
    });
  });
}
