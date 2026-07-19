import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

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
}
