import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_materials.dart';

void main() {
  group('materialsChoiceRequired', () {
    test('servicio: siempre se exige, con o sin instalación', () {
      expect(materialsChoiceRequired(isService: true, offersInstallation: false), isTrue);
      expect(materialsChoiceRequired(isService: true, offersInstallation: true), isTrue);
    });

    test('producto: solo si ofrece instalación', () {
      expect(materialsChoiceRequired(isService: false, offersInstallation: false), isFalse);
      expect(materialsChoiceRequired(isService: false, offersInstallation: true), isTrue);
    });
  });

  group('materialsValueForPayload', () {
    test('cuando no aplica, NULL aunque hubiera elección previa', () {
      expect(
        materialsValueForPayload(
            isService: false, offersInstallation: false, includesMaterials: true),
        isNull,
      );
    });

    test('cuando aplica, pasa el valor elegido tal cual', () {
      expect(
        materialsValueForPayload(
            isService: true, offersInstallation: false, includesMaterials: true),
        isTrue,
      );
      expect(
        materialsValueForPayload(
            isService: true, offersInstallation: false, includesMaterials: false),
        isFalse,
      );
    });

    test('aplica pero sin elegir: NULL', () {
      expect(
        materialsValueForPayload(
            isService: true, offersInstallation: false, includesMaterials: null),
        isNull,
      );
    });

    test('producto con instalación (la otra combinación que aplica): pasa el valor elegido tal cual', () {
      expect(
        materialsValueForPayload(
            isService: false, offersInstallation: true, includesMaterials: true),
        isTrue,
      );
      expect(
        materialsValueForPayload(
            isService: false, offersInstallation: true, includesMaterials: false),
        isFalse,
      );
    });
  });
}
