import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/phone.dart';

void main() {
  test('composeRdWhatsapp arma E.164', () {
    expect(composeRdWhatsapp('809', '5551234'), '+18095551234');
  });
  test('acepta los tres prefijos', () {
    expect(kRdPrefixes, ['809', '829', '849']);
  });
  test('vacío si no son 7 dígitos', () {
    expect(composeRdWhatsapp('809', '12345'), '');
    expect(composeRdWhatsapp('809', '12345678'), '');
  });
  test('ignora no-dígitos', () {
    expect(composeRdWhatsapp('829', '555-1234'), '+18295551234');
  });
}
