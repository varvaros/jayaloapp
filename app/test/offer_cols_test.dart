import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// `showOfferContactSheet` resuelve el NOMBRE del cliente con
/// `customerPublicProfile`, que no marca nada, en vez de con
/// `get_unlocked_offer_contact`, que MARCA `whatsapp_revealed_at`. Para eso
/// necesita el `customer_id` de la oferta, y la fila que recibe sale de
/// `offerCols`. Sin esta columna la hoja perdería el nombre en silencio.
void main() {
  test('offerCols trae customer_id', () {
    expect(offerCols.split(',').map((c) => c.trim()), contains('customer_id'));
  });
}
