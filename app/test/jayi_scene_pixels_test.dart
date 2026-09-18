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

  testWidgets('cambiar de pose ANIMA: a 100 ms el frame difiere del final', (
    t,
  ) async {
    final key = GlobalKey();
    Widget host(JayiPose pose) => MediaQuery(
      data: const MediaQueryData(disableAnimations: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 220, child: JayiScene(pose: pose)),
          ),
        ),
      ),
    );
    Future<List<int>> shot() async {
      late List<int> bytes;
      await t.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await render.toImage(pixelRatio: 1);
        bytes = (await img.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        img.dispose();
      });
      return bytes;
    }

    // OJO con la referencia: comparar «100 ms después del cambio» contra el
    // mismo widget 900 ms MÁS TARDE no prueba nada — el flote ocioso ya mueve
    // la escena entre dos instantes cualesquiera, así que esos dos frames
    // difieren aunque el cambio de pose sea instantáneo. La referencia tiene
    // que estar en el MISMO segundo del reloj: la misma lámina, quieta.
    await t.pumpWidget(host(JayiPose.thumbsUp));
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 100));
    final quieto = await shot();

    // GUARDIA de la referencia: la comparación de abajo solo vale si dos
    // escenas montadas con el MISMO calendario dan el mismo píxel. Si un
    // cambio futuro desalinea el reloj, esto falla aquí y no deja pasar el
    // `isNot` de abajo por la razón equivocada.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(JayiPose.thumbsUp));
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 100));
    final quieto2 = await shot();
    expect(
      quieto2,
      equals(quieto),
      reason: 'dos montajes idénticos deben pintar lo mismo en el mismo frame',
    );

    await t.pumpWidget(const SizedBox()); // desmontar: el reloj vuelve a 0
    await t.pumpWidget(host(JayiPose.open));
    await t.pump(const Duration(seconds: 2)); // el aterrizaje ya terminó
    await t.pumpWidget(host(JayiPose.thumbsUp));
    await t.pump(const Duration(milliseconds: 100));
    final medio = await shot();

    expect(
      medio,
      isNot(equals(quieto)),
      reason: 'el pulgar debe estar subiendo a los 100 ms',
    );
  });

  // Una vez por pose ENTRANTE: el estado final no puede depender de por dónde
  // se llegó. Se entra desde la pose siguiente del enum, así que cada accesorio
  // aparece una vez como entrante y otra como saliente.
  for (final destino in JayiPose.values) {
    final desde =
        JayiPose.values[(JayiPose.values.indexOf(destino) + 1) %
            JayiPose.values.length];
    testWidgets(
      'con reduce-motion el cambio de pose es INSTANTÁNEO y sin accesorio '
      'saliente ($desde → $destino)',
      (t) async {
        final a = await pintar(t, destino);
        late List<int> directo;
        await t.runAsync(() async => directo = await png(a));
        a.dispose();

        // Montar en otra pose, cambiar, y sin dejar pasar tiempo debe pintar
        // exactamente lo mismo que montar directo en la pose de destino.
        final key = GlobalKey();
        Widget host(JayiPose pose) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(width: 220, child: JayiScene(pose: pose)),
              ),
            ),
          ),
        );
        await t.pumpWidget(host(desde));
        await t.pump();
        await t.pumpWidget(host(destino));
        await t.pump();
        late List<int> cambiado;
        await t.runAsync(() async {
          final render =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await render.toImage(pixelRatio: 1);
          cambiado = (await img.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          img.dispose();
        });
        expect(cambiado, equals(directo));
      },
    );
  }
}
