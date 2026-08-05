import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/features/provider/offer_center_menu.dart';

void main() {
  void nada() {}

  List<CenterMenuItem> menu({required bool busy, required int fotos}) =>
      buildOfferCenterMenu(
        busy: busy,
        photoCount: fotos,
        maxPhotos: 5,
        onCamera: nada,
        onGallery: nada,
        onStore: nada,
        onPortfolio: nada,
      );

  bool viva(List<CenterMenuItem> m, String label) =>
      m.firstWhere((i) => i.label == label).enabled;

  test('los cuatro destinos, siempre, y en este orden', () {
    expect(menu(busy: false, fotos: 0).map((i) => i.label).toList(),
        ['Cámara', 'Galería', 'Mi tienda', 'Trabajos']);
  });

  test('con sitio para fotos, los cuatro vivos', () {
    final m = menu(busy: false, fotos: 2);
    expect(m.every((i) => i.enabled), isTrue);
  });

  test('al tope de fotos se apagan los tres de FOTO, pero "Mi tienda" sigue '
      'vivo: además autocompleta precio, color, envío y estado', () {
    final m = menu(busy: false, fotos: 5);
    expect(viva(m, 'Cámara'), isFalse);
    expect(viva(m, 'Galería'), isFalse);
    expect(viva(m, 'Trabajos'), isFalse);
    expect(viva(m, 'Mi tienda'), isTrue);
  });

  test('enviando la oferta, todo apagado', () {
    expect(menu(busy: true, fotos: 0).any((i) => i.enabled), isFalse);
  });

  test('el menú es igual POR VALOR entre reconstrucciones equivalentes: el '
      'formulario se rearma con cada tecla del campo de precio', () {
    expect(menu(busy: false, fotos: 1), equals(menu(busy: false, fotos: 1)));
    expect(menu(busy: false, fotos: 1), isNot(equals(menu(busy: false, fotos: 5))));
  });
}
