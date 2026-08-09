import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

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
}
