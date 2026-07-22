import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';

void main() {
  group('storeItemChatCaption', () {
    test('producto: nombre, precio, estado, envío y descripción', () {
      final caption = storeItemChatCaption({
        'kind': 'producto',
        'name': 'Abanico de pedestal',
        'description': 'Tres velocidades, poco uso.',
        'condition': 'usado',
        'offers_shipping': true,
        'offers_installation': false,
      }, priceLabel: 'RD\$2,500');
      expect(caption, contains('🛍️ De mi tienda: Abanico de pedestal'));
      expect(caption, contains('Precio: RD\$2,500'));
      expect(caption, contains('Estado: Usado'));
      expect(caption, contains('🚚 Con envío disponible'));
      expect(caption, contains('Tres velocidades, poco uso.'));
      expect(caption, isNot(contains('instalación')));
    });

    test('servicio: sin estado, con emoji de herramienta', () {
      final caption = storeItemChatCaption({
        'kind': 'servicio',
        'name': 'Instalación de aires',
        'description': '',
        'condition': 'nuevo', // presente pero NO aplica a servicios
      }, priceLabel: 'desde RD\$1,500');
      expect(caption, contains('🛠️ De mi tienda: Instalación de aires'));
      expect(caption, contains('Precio: desde RD\$1,500'));
      expect(caption, isNot(contains('Estado')));
    });

    test('descripción larga se recorta a 240', () {
      final caption = storeItemChatCaption({
        'kind': 'producto',
        'name': 'X',
        'description': 'a' * 500,
      }, priceLabel: 'Consultar precio');
      final descLine = caption.split('\n').last;
      expect(descLine.length, 240);
    });
  });
}
