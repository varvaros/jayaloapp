import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/first_offer_chip.dart';

void main() {
  test('copy exacto del chip', () {
    expect(firstOfferChipText, '¡Haz la primera oferta!');
  });

  test('muestra el chip solo con 0 ofertas, sin oferta propia, en marketplace', () {
    expect(
      showFirstOfferChip(
        offersCount: 0,
        hasMyOffer: false,
        isMarketplace: true,
      ),
      true,
    );
  });

  test('desconocido (null) nunca promete de más', () {
    expect(
      showFirstOfferChip(
        offersCount: null,
        hasMyOffer: false,
        isMarketplace: true,
      ),
      false,
    );
  });

  test('con oferta propia no se invita a "ser el primero"', () {
    expect(
      showFirstOfferChip(
        offersCount: 0,
        hasMyOffer: true,
        isMarketplace: true,
      ),
      false,
    );
  });

  test('las tarjetas de interés de tienda no son marketplace', () {
    expect(
      showFirstOfferChip(
        offersCount: 0,
        hasMyOffer: false,
        isMarketplace: false,
      ),
      false,
    );
  });

  test('con al menos una oferta ya no es la primera', () {
    expect(
      showFirstOfferChip(
        offersCount: 1,
        hasMyOffer: false,
        isMarketplace: true,
      ),
      false,
    );
  });
}
