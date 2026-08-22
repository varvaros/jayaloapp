import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_materials.dart';

void main() {
  group('materialsChoiceRequired', () {
    test('servicio de un oficio CON materiales: se exige', () {
      expect(
          materialsChoiceRequired(
              isService: true,
              offersInstallation: false,
              serviceUsesMaterials: true),
          isTrue);
      expect(
          materialsChoiceRequired(
              isService: true,
              offersInstallation: true,
              serviceUsesMaterials: true),
          isTrue);
    });

    test('servicio de un oficio SIN materiales: NO se exige', () {
      // El caso del PO: un abogado o un diseñador gráfico no compra materiales.
      expect(
          materialsChoiceRequired(
              isService: true,
              offersInstallation: false,
              serviceUsesMaterials: false),
          isFalse);
    });

    test('producto: solo si ofrece instalación', () {
      expect(
          materialsChoiceRequired(
              isService: false,
              offersInstallation: false,
              serviceUsesMaterials: false),
          isFalse);
      expect(
          materialsChoiceRequired(
              isService: false,
              offersInstallation: true,
              serviceUsesMaterials: false),
          isTrue,
          reason: 'lo que se instala son cosas, lleve o no materiales el oficio');
    });
  });

  group('categoriesUseMaterials (gate por oficio, PO 2026-08-22)', () {
    test('oficios sin materiales: NO se pregunta', () {
      expect(categoriesUseMaterials(['legal']), isFalse);
      expect(categoriesUseMaterials(['marketing']), isFalse);
      expect(categoriesUseMaterials(['legal', 'redaccion']), isFalse,
          reason: 'un abogado que redacta sigue sin comprar materiales');
    });

    test('oficios con materiales: se pregunta', () {
      expect(categoriesUseMaterials(['construccion']), isTrue);
      expect(categoriesUseMaterials(['plomeria']), isTrue);
      expect(categoriesUseMaterials(['climatizacion']), isTrue);
    });

    test('mezcla: basta UNA con materiales', () {
      expect(categoriesUseMaterials(['legal', 'construccion']), isTrue);
    });

    test('sin categorías o desconocida: se pregunta (como antes)', () {
      expect(categoriesUseMaterials([]), isTrue,
          reason: 'solicitud vieja o ruteo sin categorías: no perder la pregunta');
      expect(categoriesUseMaterials(['']), isTrue);
      expect(categoriesUseMaterials(['categoria_que_no_existe_aun']), isTrue,
          reason: 'una categoría nueva conserva el comportamiento de siempre');
    });
  });

  group('materialsValueForPayload', () {
    test('cuando no aplica, NULL aunque hubiera elección previa', () {
      expect(
        materialsValueForPayload(
            isService: false,
            offersInstallation: false,
            serviceUsesMaterials: false,
            includesMaterials: true),
        isNull,
      );
    });

    test('servicio SIN materiales: NULL aunque hubiera contestado antes', () {
      expect(
        materialsValueForPayload(
            isService: true,
            offersInstallation: false,
            serviceUsesMaterials: false,
            includesMaterials: true),
        isNull,
        reason: 'no se afirma nada sobre materiales de un trabajo que no tiene',
      );
    });

    test('cuando aplica, pasa el valor elegido tal cual', () {
      expect(
        materialsValueForPayload(
            isService: true,
            offersInstallation: false,
            serviceUsesMaterials: true,
            includesMaterials: true),
        isTrue,
      );
      expect(
        materialsValueForPayload(
            isService: true,
            offersInstallation: false,
            serviceUsesMaterials: true,
            includesMaterials: false),
        isFalse,
      );
    });

    test('aplica pero sin elegir: NULL', () {
      expect(
        materialsValueForPayload(
            isService: true,
            offersInstallation: false,
            serviceUsesMaterials: true,
            includesMaterials: null),
        isNull,
      );
    });

    test('producto con instalación: pasa el valor elegido tal cual', () {
      expect(
        materialsValueForPayload(
            isService: false,
            offersInstallation: true,
            serviceUsesMaterials: false,
            includesMaterials: true),
        isTrue,
      );
      expect(
        materialsValueForPayload(
            isService: false,
            offersInstallation: true,
            serviceUsesMaterials: false,
            includesMaterials: false),
        isFalse,
      );
    });
  });
}
