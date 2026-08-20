// Que cada lámina pinte SU escena, comprobado en píxeles.
//
// La queja del PO era exactamente esta: las tres láminas enseñaban la misma
// imagen mientras el texto cambiaba. Un test de widgets no la habría cazado
// —el árbol era distinto, el render era el mismo—, así que aquí se rasteriza
// cada escena y se comparan los bytes.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/jayi_scene.dart';

void main() {
  /// Rasteriza una escena a PNG. Con las animaciones apagadas el frame es
  /// determinista (estado base), así que dos corridas dan los mismos bytes.
  Future<List<int>> pintar(WidgetTester t, JayiSceneKind kind) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 220, child: JayiScene(kind: kind)),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    late List<int> bytes;
    await t.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await render.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
      img.dispose();
    });
    return bytes;
  }

  testWidgets('las 5 escenas son visualmente DISTINTAS entre sí', (t) async {
    final porEscena = <JayiSceneKind, List<int>>{};
    for (final kind in JayiSceneKind.values) {
      porEscena[kind] = await pintar(t, kind);
    }

    // Ninguna escena puede pintar lo mismo que otra: si el día de mañana
    // alguien vuelve a poner un fondo compartido en vez de la ilustración de
    // cada lámina, este test lo caza.
    final kinds = JayiSceneKind.values;
    for (var i = 0; i < kinds.length; i++) {
      for (var j = i + 1; j < kinds.length; j++) {
        expect(
          porEscena[kinds[i]],
          isNot(equals(porEscena[kinds[j]])),
          reason: '${kinds[i]} y ${kinds[j]} pintan lo mismo',
        );
      }
    }
  });

  testWidgets('la escena pinta algo de verdad, no un lienzo en blanco', (
    t,
  ) async {
    // Un fallo de coordenadas que dejara todo fuera del viewport daría un PNG
    // válido pero vacío, y el test de arriba seguiría pasando por el ruido de
    // la compresión. Aquí se cuenta cuánto píxel NO transparente hay.
    final key = GlobalKey();
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 220,
                child: JayiScene(kind: JayiSceneKind.common),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    late int opacos;
    late int total;
    await t.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await render.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = data!.buffer.asUint8List();
      total = px.length ~/ 4;
      opacos = 0;
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] > 200) opacos++;
      }
      img.dispose();
    });

    // Jayi ocupa ~112x112 de un lienzo de 220x173: bastante más del 5 %.
    expect(
      opacos / total,
      greaterThan(.05),
      reason: 'la escena salió casi vacía: $opacos de $total píxeles',
    );
  });
}
