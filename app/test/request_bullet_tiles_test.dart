import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/request_bullet_tiles.dart';

void main() {
  test('parte «Etiqueta: valor» en filas y respeta el orden', () {
    final r = requestBulletRows(const [
      'Producto: Sillas plásticas apilables',
      'Cantidad: 500 unidades',
      'Marca: Cualquiera (opción confiable)',
    ]);
    expect(r.rows, hasLength(3));
    expect(r.rows[0].$2, 'Producto');
    expect(r.rows[0].$3, 'Sillas plásticas apilables');
    expect(r.rows[1].$2, 'Cantidad');
    expect(r.rows[2].$3, 'Cualquiera (opción confiable)');
    expect(r.freeText, isEmpty);
  });

  test('lo que no encaja sobrevive ÍNTEGRO como texto libre', () {
    final r = requestBulletRows(const [
      'Cantidad: 500 unidades',
      'Que sean resistentes al sol y sin brazos',
      // Etiqueta demasiado larga = frase con dos puntos dentro, no un dato.
      'Muy importante que el proveedor entregue antes: del viernes',
    ]);
    expect(r.rows, hasLength(1));
    expect(r.freeText, [
      'Que sean resistentes al sol y sin brazos',
      'Muy importante que el proveedor entregue antes: del viernes',
    ]);
  });

  test('bullets vacíos o sin valor no producen filas fantasma', () {
    final r = requestBulletRows(const ['', '  ', 'Marca:', ': valor']);
    expect(r.rows, isEmpty);
    expect(r.freeText, ['Marca:', ': valor']);
  });

  test('el ícono casa por etiqueta, con o sin tilde, y cae en neutro', () {
    final r = requestBulletRows(const [
      'Logística: Entrega en negocio',
      'Ubicación de entrega: Distrito Nacional',
      'Rareza: sin ícono propio',
    ]);
    expect(r.rows[0].$1, Icons.local_shipping_outlined);
    expect(r.rows[1].$1, Icons.place_outlined);
    expect(r.rows[2].$1, Icons.notes_outlined);
  });

  // El matcher elige el ícono por PALABRA dentro del texto del bullet. Al renombrar
  // «Envío» a «Traslado» (2026-08-17) el camión se perdía en silencio: no rompe
  // ningún test de compilación, solo pinta el ícono neutro de nota.
  test('«Traslado» sigue llevando camión, y «Envío» de bullets viejos también', () {
    expect(iconForLabel('Traslado'), Icons.local_shipping_outlined);
    expect(iconForLabel('Traslado a domicilio'), Icons.local_shipping_outlined);
    expect(iconForLabel('Envío'), Icons.local_shipping_outlined);
  });
}
