import 'package:flutter/material.dart';

/// Palabra cualitativa de una nota 1-10. Espejo de `ratingWord10` de
/// `features/chat/widgets/rating_form.dart` (allí se queda porque los formularios
/// la usan con su propio layout).
String starScoreWord(num n) => n <= 0
    ? ''
    : n <= 3
        ? 'Malo'
        : n <= 5
            ? 'Regular'
            : n <= 7
                ? 'Bueno'
                : n <= 9
                    ? 'Muy bueno'
                    : 'Excelente';

/// Cinco estrellas que representan una nota **1-10**, con relleno CONTINUO.
///
/// Mockup aprobado por el PO el 2026-08-17 (`Downloads/estrellas-medias.html`):
/// cada estrella vale 2 puntos, así que un 7 son tres estrellas y media. El
/// relleno **no se redondea**: un promedio de 7,4 deja la cuarta estrella al 70 %.
/// Eso es deliberado — los promedios que llegan de las RPC son decimales
/// (`round(avg(rating),1)`) y redondear a media estrella tiraría precisión que sí
/// se puede pintar.
///
/// ⚠️ POR QUÉ NO `Icons.star_half`: Material pinta la mitad vacía como CONTORNO y
/// el mockup la quiere **gris sólida**; y `star_half` solo sabe de mitades, así que
/// obligaría a redondear los decimales. El coste de hacerlo bien son ~10 líneas,
/// una sola vez.
///
/// ⚠️ POR QUÉ `Align(widthFactor:)` Y NO UN `LayoutBuilder`: este widget se monta
/// bajo `SliverFillRemaining(hasScrollBody: false)` (ver el contrato en
/// `request_detail_sheet.dart:80-86`), donde **todo descendiente debe responder a
/// `getMaxIntrinsicHeight`**. Un `LayoutBuilder` anidado revienta en layout y
/// `flutter analyze` NO lo caza. `Align`/`ClipRect` sí propagan intrínsecas.
///
/// ⚠️ ANTES DE ESTE WIDGET había TRES copias a mano en la app, con redondeos que ya
/// divergían (solo una tenía `clamp`), y cinco pantallas que pintaban el número
/// crudo 1-10 pegado a una estrella — o sea que un **4,8/10 (malo) se leía como
/// 4,8/5 (excelente)**, justo donde el cliente decide gastar créditos.
class StarScore extends StatelessWidget {
  const StarScore({
    super.key,
    required this.score,
    this.size = 16,
    this.showNumber = true,
    this.numberStyle,
  });

  /// Nota sobre 10. `0` o menos = sin nota: se pintan las cinco vacías.
  final double score;

  /// Alto y ancho de cada estrella.
  final double size;

  /// Escribe «7 / 10» al lado. Va en `true` por defecto a propósito: sin el
  /// sufijo, cinco estrellas invitan a leer la nota como si fuera sobre 5.
  final bool showNumber;

  final TextStyle? numberStyle;

  static const _oro = Color(0xFFF2B705);

  /// «8» si es entero, «7.4» si no. Los ratings individuales son enteros y los
  /// promedios decimales; escribir «8.0» en una reseña suelta se lee raro.
  static String formatScore(double s) =>
      s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final apagada = cs.onSurfaceVariant.withValues(alpha: .32);

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 5; i++)
        Stack(children: [
          Icon(Icons.star_rounded, size: size, color: apagada),
          // Fracción de ESTA estrella: cada una vale 2 puntos de la escala 1-10.
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: (((score - i * 2) / 2).clamp(0.0, 1.0)).toDouble(),
              child: Icon(Icons.star_rounded, size: size, color: _oro),
            ),
          ),
        ]),
      if (showNumber && score > 0) ...[
        SizedBox(width: size * .32),
        Text('${formatScore(score)} / 10',
            style: numberStyle ??
                TextStyle(
                    fontSize: size * .72,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
      ],
    ]);
  }
}
