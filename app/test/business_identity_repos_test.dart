import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

void main() {
  test('businessImagePath espeja la ruta de la web y arranca con el uid', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'covers', ext: 'png', ts: 123);
    expect(p, 'u1/covers/b1-123.png'); // RLS: primera carpeta = auth.uid()
  });
  test('businessImagePath para logo no repite el patrón viejo', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'logos', ext: 'jpg', ts: 9);
    expect(p, 'u1/logos/b1-9.jpg');
  });

  group('isMissingServicesColumnError', () {
    test('código 42703 (undefined_column) cuenta como columna faltante', () {
      expect(
        isMissingServicesColumnError(
          PostgrestException(message: 'column "services" does not exist', code: '42703'),
        ),
        isTrue,
      );
    });
    test('mensaje que nombra "column" y "services" sin código cuenta igual', () {
      expect(
        isMissingServicesColumnError(
          PostgrestException(
            message: 'Could not find the services column of provider_businesses',
          ),
        ),
        isTrue,
      );
    });
    test('timeout de red NO cuenta — debe propagar', () {
      expect(
        isMissingServicesColumnError(
          PostgrestException(message: 'Connection timed out', code: '57014'),
        ),
        isFalse,
      );
    });
    test('token vencido / 401 NO cuenta — debe propagar', () {
      expect(
        isMissingServicesColumnError(
          PostgrestException(message: 'JWT expired', code: '401'),
        ),
        isFalse,
      );
    });
    test('mensaje que solo nombra "services" sin "column" NO cuenta', () {
      expect(
        isMissingServicesColumnError(
          PostgrestException(message: 'services temporarily unavailable'),
        ),
        isFalse,
      );
    });
  });
}
