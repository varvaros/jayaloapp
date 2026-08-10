import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/money.dart';
import 'package:jayalo_app/features/shared/brand_kit.dart';

void main() {
  group('fmtMiles', () {
    test('agrupa miles sin símbolo ni decimales', () {
      expect(fmtMiles(600), '600');
      expect(fmtMiles(12000), '12,000');
      expect(fmtMiles(1234567), '1,234,567');
      expect(fmtMiles(null), '');
    });

    test('redondea, nunca .00', () {
      expect(fmtMiles(3000.5), '3,001');
      expect(fmtMiles(6000.0), '6,000');
    });
  });

  group('parseMiles', () {
    test('ida y vuelta con lo que deja el formatter', () {
      expect(parseMiles(fmtMiles(12000)), 12000);
      expect(parseMiles('12,000'), 12000);
      expect(parseMiles('1,234,567'), 1234567);
    });

    test('decimal único al final se redondea (bug ×10 del 08-09)', () {
      expect(parseMiles('3000.0'), 3000);
      expect(parseMiles('3000.50'), 3001);
      expect(parseMiles('3000,5'), 3001);
    });

    test('punto/coma con 3 dígitos sigue siendo separador de miles', () {
      expect(parseMiles('3.000'), 3000);
      expect(parseMiles('1,500'), 1500);
    });

    test('símbolos y basura', () {
      expect(parseMiles('RD\$5000'), 5000);
      expect(parseMiles(''), null);
      expect(parseMiles('RD\$'), null);
      expect(parseMiles('abc'), null);
    });
  });

  group('MilesInputFormatter', () {
    TextEditingValue fmt(String s, {String prev = ''}) =>
        MilesInputFormatter().formatEditUpdate(
            TextEditingValue(text: prev), TextEditingValue(text: s));

    test('agrupa al escribir', () {
      expect(fmt('600').text, '600');
      expect(fmt('12000').text, '12,000');
    });

    test('vaciar el campo lo deja vacío', () {
      expect(fmt('', prev: '12,000').text, '');
      expect(fmt('RD\$', prev: '').text, '');
    });

    test('un pegado con decimales se normaliza redondeando', () {
      expect(fmt('3000.50').text, '3,001');
      expect(fmt('6000.0').text, '6,000');
    });

    test('más de 12 dígitos rechaza el cambio', () {
      expect(fmt('1234567890123', prev: '123,456,789,012').text,
          '123,456,789,012');
    });

    test('el cursor queda al final', () {
      final v = fmt('12000');
      expect(v.selection.baseOffset, v.text.length);
    });
  });
}
