// El paso 1 del alta de proveedor. Pura para poder fijarla sin montar la
// pantalla (que en `initState` habla con Supabase).
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/provider_signup.dart';

void main() {
  bool valid({
    String name = 'Repuestos El Primo',
    String profession = 'Plomero',
    String type = 'informal',
    String rnc = '',
  }) => providerStep1Valid(
    businessName: name,
    profession: profession,
    businessType: type,
    rnc: rnc,
  );

  test('con nombre y profesion se puede avanzar', () {
    expect(valid(), isTrue);
  });

  test('sin nombre de negocio no se avanza', () {
    expect(valid(name: '  '), isFalse);
  });

  group('la profesion es OBLIGATORIA para los TRES tipos (PO 2026-08-20)', () {
    // Antes solo se pedia —y como "(opcional)"— cuando el tipo era `tecnico`,
    // asi que la mayoria de proveedores acababa sin profesion en su ficha.
    for (final type in ['informal', 'tecnico', 'formal']) {
      test('sin profesion no se avanza siendo $type', () {
        expect(
          valid(profession: '   ', type: type, rnc: '131234567'),
          isFalse,
        );
      });

      test('con profesion si se avanza siendo $type', () {
        expect(
          valid(profession: 'Electricista', type: type, rnc: '131234567'),
          isTrue,
        );
      });
    }
  });

  test('formal sin RNC sigue sin poder avanzar', () {
    expect(valid(type: 'formal', rnc: ''), isFalse);
  });

  test('formal con RNC y profesion avanza', () {
    expect(valid(type: 'formal', rnc: '131234567'), isTrue);
  });

  test('el RNC solo se exige a los formales', () {
    expect(valid(type: 'tecnico', rnc: ''), isTrue);
  });
}
