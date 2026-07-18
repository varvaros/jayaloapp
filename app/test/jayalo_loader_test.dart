import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/brand.dart';
import 'package:jayalo_app/features/shared/jayalo_loader.dart';

/// El isotipo está portado A MANO desde `isojayalo.svg` / `JayaloLoader.tsx`
/// (coordenadas del viewBox 200x200). Un error de geometría no lo detectan ni
/// `analyze` ni los tests de dominio, así que aquí se PINTA de verdad y se
/// muestrean píxeles en puntos conocidos de la silueta.
void main() {
  const size = 200.0; // 1 px = 1 unidad del viewBox

  Color Function(int x, int y) pixelReaderFor(ByteData bytes) => (x, y) {
        final i = (y * size.toInt() + x) * 4;
        return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      };

  testWidgets('la mascota dibuja cuerpo, ojo y pupila donde manda el SVG',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: const JayaloMascot(size: size),
        ),
      ),
    ));

    late ByteData bytes;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    final at = pixelReaderFor(bytes);

    // Cuerpo: rect (29,42)-(165,177) relleno del violeta de la mascota.
    expect(at(100, 150), JayaloColors.mascot, reason: 'centro del cuerpo');

    // Ojo: círculo blanco en (67,86) r29 — se muestrea lejos de la pupila.
    expect(at(75, 78), const Color(0xFFFFFFFF), reason: 'blanco del ojo');

    // Pupila estática mirando abajo-izquierda: (58,96) r9.5.
    expect(at(58, 96), JayaloColors.mascot, reason: 'pupila');

    // Fuera de la silueta no se pinta nada (esquina inferior izquierda).
    expect(at(5, 195).a, 0, reason: 'fondo transparente');
  });

  testWidgets('el loader animado late sin repintar de más ni tirar excepciones',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: JayaloLoaderBlock(label: 'Cargando')),
    ));
    expect(find.text('Cargando'), findsOneWidget);
    // Avanza el ciclo: cubre parpadeo, escaneo de pupila y pulso de puntos.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });
}
