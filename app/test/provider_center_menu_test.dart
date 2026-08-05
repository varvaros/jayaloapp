import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/center_action.dart';
import 'package:jayalo_app/features/provider/offer_center_menu.dart';

void main() {
  void nada() {}

  List<CenterMenuItem> menu({
    required bool busy,
    required int fotos,
    VoidCallback? onCapHit,
  }) =>
      buildOfferCenterMenu(
        busy: busy,
        photoCount: fotos,
        maxPhotos: 5,
        onCamera: nada,
        onGallery: nada,
        onStore: nada,
        onPortfolio: nada,
        onCapHit: onCapHit ?? nada,
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

  test('al tope de fotos (no ocupado) los tres de FOTO llevan onDisabledTap: '
      'apagados-por-tope SÍ tienen algo que avisar', () {
    var avisos = 0;
    void avisar() => avisos++;
    final m = menu(busy: false, fotos: 5, onCapHit: avisar);

    for (final label in ['Cámara', 'Galería', 'Trabajos']) {
      final item = m.firstWhere((i) => i.label == label);
      expect(item.enabled, isFalse);
      expect(item.onDisabledTap, same(avisar),
          reason: '$label apagado por TOPE debe avisar por qué');
    }
    m.firstWhere((i) => i.label == 'Cámara').onDisabledTap!();
    expect(avisos, 1);

    // "Mi tienda" no se apaga nunca por tope: no lleva aviso.
    expect(m.firstWhere((i) => i.label == 'Mi tienda').onDisabledTap, isNull);
  });

  test('ocupado (busy) los apagados NO llevan onDisabledTap: no hay nada '
      'que avisar, solo esperar', () {
    var avisos = 0;
    void avisar() => avisos++;
    final m = menu(busy: true, fotos: 0, onCapHit: avisar);

    for (final item in m) {
      expect(item.enabled, isFalse);
      expect(item.onDisabledTap, isNull,
          reason: '${item.label} apagado por BUSY debe quedar inerte');
    }
    expect(avisos, 0);
  });
}
