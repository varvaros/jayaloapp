// Que cada pose pinte SU escena, comprobado en píxeles, y que la moneda sea
// DORADA de verdad (única figura no violeta del intro).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/jayi_scene.dart';

void main() {
  Future<ui.Image> pintar(
    WidgetTester t,
    JayiPose pose, {
    bool reduced = true,
    Duration? after,
  }) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 220, child: JayiScene(pose: pose)),
            ),
          ),
        ),
      ),
    );
    if (after != null) {
      await t.pump(after);
    } else {
      await t.pumpAndSettle();
    }
    late ui.Image img;
    await t.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      img = await render.toImage(pixelRatio: 1);
    });
    return img;
  }

  Future<List<int>> png(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  testWidgets('las 5 poses son visualmente DISTINTAS entre sí', (t) async {
    final porPose = <JayiPose, List<int>>{};
    for (final pose in JayiPose.values) {
      final img = await pintar(t, pose);
      await t.runAsync(() async => porPose[pose] = await png(img));
      img.dispose();
    }
    final poses = JayiPose.values;
    for (var i = 0; i < poses.length; i++) {
      for (var j = i + 1; j < poses.length; j++) {
        expect(
          porPose[poses[i]],
          isNot(equals(porPose[poses[j]])),
          reason: '${poses[i]} y ${poses[j]} pintan lo mismo',
        );
      }
    }
  });

  testWidgets('la moneda es DORADA: hay píxeles con rojo alto y azul bajo', (
    t,
  ) async {
    final img = await pintar(t, JayiPose.coin);
    late int dorados;
    await t.runAsync(() async {
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = data.buffer.asUint8List();
      dorados = 0;
      for (var i = 0; i < px.length; i += 4) {
        final r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3];
        if (a > 200 && r > 200 && g > 140 && b < 120) dorados++;
      }
    });
    img.dispose();
    expect(
      dorados,
      greaterThan(150),
      reason: 'la moneda mide r=16 en un lienzo de 220: cientos de píxeles',
    );
  });

  testWidgets(
    'el pulgar arriba NO pinta oro (la moneda es lo único no violeta)',
    (t) async {
      final img = await pintar(t, JayiPose.thumbsUp);
      late int dorados;
      await t.runAsync(() async {
        final data = (await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final px = data.buffer.asUint8List();
        dorados = 0;
        for (var i = 0; i < px.length; i += 4) {
          if (px[i + 3] > 200 &&
              px[i] > 200 &&
              px[i + 1] > 140 &&
              px[i + 2] < 120) {
            dorados++;
          }
        }
      });
      img.dispose();
      expect(dorados, 0);
    },
  );
}
