import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_seed.dart';

void main() {
  test('toma title y prefiere image_url primaria', () {
    final s = RequestSeed.fromRow({
      'title': 'Taladro',
      'image_url': 'https://x/p.jpg',
      'image_urls': ['https://x/a.jpg'],
    });
    expect(s.title, 'Taladro');
    expect(s.imageUrl, 'https://x/p.jpg');
  });

  test('cae a image_urls.first si no hay primaria', () {
    final s = RequestSeed.fromRow({
      'title': 'Taladro',
      'image_url': null,
      'image_urls': ['https://x/a.jpg', 'https://x/b.jpg'],
    });
    expect(s.imageUrl, 'https://x/a.jpg');
  });

  test('imageUrl null cuando no hay fotos', () {
    final s = RequestSeed.fromRow({'title': 'Taladro'});
    expect(s.imageUrl, isNull);
    expect(s.title, 'Taladro');
  });
}
