/// El estado «esperando» del cliente, pero VIVO: un reloj en avance rápido y
/// tres puntos que rebotan.
///
/// Por qué existe (pedido PO 2026-09-18): una solicitud recién publicada se
/// quedaba con una píldora quieta que decía «Esperando ofertas». Quieta y en
/// pasiva, se lee como que el sistema se detuvo. El movimiento no añade
/// información — dice que sigue trabajando.
///
/// ⚠️ Bucles en `repeat()` hay ya una veintena en la app (la mascota de los
/// estados vacíos, el titileo de las cabeceras de Reputación, el
/// "escribiendo" del chat…). Lo que NO había es uno dentro de la TARJETA de
/// una lista, que es justo la objeción que `motion.dart` documenta al
/// explicar por qué el saludo del borde violeta es finito: «un latido
/// perpetuo … habría costado repintar la tarjeta mientras estuviera en
/// pantalla, en una LISTA». Esa objeción se paga con dos cosas, no se ignora:
///   1. [idle] — quien lo monta en una LISTA pasa UN solo controlador
///      compartido por toda la pantalla (patrón de `stats_screen.dart`), en
///      vez de un ticker por tarjeta.
///   2. El repintado va dentro de un [RepaintBoundary] del tamaño del glifo,
///      así que el bucle no ensucia la tarjeta que lo contiene.
/// Si algún día esto se monta sin [idle] dentro de un `ListView`, la objeción
/// de `motion.dart` vuelve a aplicar tal cual.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion.dart';

/// El copy oficial del estado. Vive aquí y no en cada pantalla para que la
/// tarjeta de la lista y el detalle no puedan divergir.
const buscandoProveedoresCopy = 'Buscando proveedores';

/// Cuántas veces rebotan los puntos en UNA vuelta del reloj.
///
/// Es un entero A PROPÓSITO: reloj y puntos salen del MISMO controlador, así
/// que un divisor no entero haría que los puntos dieran un salto en la costura
/// de cada vuelta. Con 6, cada rebote dura 800ms — prácticamente el compás de
/// 900ms que `typing_indicator.dart` fijó para "alguien está escribiendo".
const _puntosPorVuelta = 6;

/// Atraso de cada punto respecto del anterior, igual que en el chat: a un
/// tercio del ciclo los tres quedan repartidos parejo y el rebote se lee como
/// una ola, no como tres puntos sueltos.
const _puntoAtraso = 1 / 3;

/// Cuánto sube el punto en lo más alto, en píxeles. Más corto que el del chat
/// (5.0) porque aquí vive dentro de una píldora de 11pt, no de una burbuja.
const _puntoSalto = 2.5;

const _puntoTam = 3.0;
const _puntoHueco = 2.5;

/// Dónde se queda el reloj cuando NO se mueve (test, o "reducir animaciones").
///
/// No es 0: con las dos manecillas juntas en las 12 el glifo se lee como un
/// reloj en blanco. A 1/6 de vuelta la manecilla larga marca las 2 y se
/// reconoce como reloj de un vistazo.
const _relojReposo = 1 / 6;

/// Vaivén 0→1→0 suavizado. Tercera copia deliberada del `_pingPong` de
/// `jayalo_loader.dart` (la segunda es `typing_indicator.dart`): es el mismo
/// gesto y conviene que se vea igual, pero allá es privado del loader y
/// exportarlo abriría API del isotipo de marca para un uso que no tiene nada
/// que ver con él.
double _pingPong(double t) {
  final p = t % 1.0;
  return Curves.easeInOut.transform(p < .5 ? p * 2 : (1 - p) * 2);
}

/// Reloj + etiqueta + tres puntos, en una fila que se puede meter dentro de
/// cualquier píldora.
///
/// CONTRATO DE LAYOUT: alto INTRÍNSECO conocido y ancho que no cambia con el
/// tiempo. Los dos importan:
///   - El detalle del cliente vive en un `SliverFillRemaining(hasScrollBody:
///     false)`, que le pide `getMaxIntrinsicHeight` a su hijo; un
///     `LayoutBuilder` o un `AspectRatio` aquí adentro reventaría en tiempo de
///     layout y `flutter analyze` no diría nada.
///   - Los puntos son CÍRCULOS y no el texto «...» justamente para que la
///     píldora no cambie de ancho seis veces por vuelta: se mueven con
///     `Transform.translate`, que no participa del layout.
class BuscandoIndicator extends StatefulWidget {
  const BuscandoIndicator({
    super.key,
    required this.label,
    required this.estilo,
    this.reloj = true,
    this.idle,
  });

  /// El texto de la píldora. El reloj y los puntos son el adorno; esto es la
  /// información, y es lo que oye un lector de pantalla.
  final String label;

  /// Estilo del texto. Su `color` es TAMBIÉN la tinta del reloj y de los
  /// puntos — un solo color por píldora, para que el chip lila y la píldora
  /// violeta del riel no tengan que repetir la decisión.
  final TextStyle estilo;

  /// Si la fila lleva reloj. El riel de progreso lo apaga: ahí la píldora es
  /// un hito de una línea de tres pasos y un reloj dentro sería un segundo
  /// ícono compitiendo con los aros de los otros pasos.
  final bool reloj;

  /// El reloj COMPARTIDO de la pantalla, de 0 a 1 por vuelta. En una lista se
  /// pasa siempre (ver la nota de arriba). Si es null, la fila monta su propio
  /// controlador — correcto para una hoja suelta como el detalle.
  final Animation<double>? idle;

  @override
  State<BuscandoIndicator> createState() => _BuscandoIndicatorState();
}

class _BuscandoIndicatorState extends State<BuscandoIndicator>
    with SingleTickerProviderStateMixin {
  /// Solo existe cuando nadie nos pasó [BuscandoIndicator.idle].
  ///
  /// Se crea en `initState` y NO como `late final … = AnimationController(…)`:
  /// con "reducir animaciones" el build no toca el campo y un `late final` se
  /// inicializaría dentro de `dispose()`, donde `createTicker` va a buscar el
  /// `TickerMode` de un elemento ya desactivado. Mismo gotcha que documentan
  /// `jayalo_loader.dart` y `typing_indicator.dart`.
  AnimationController? _propio;

  /// `Platform.environment` y no `bool.fromEnvironment`: ese dart-define NO
  /// está definido bajo `flutter test` (gotcha ya documentado en
  /// `_SectionGlyphPill` y en `conversations_screen.dart`). Sin esto, un
  /// ticker en `repeat()` deja cualquier test que monte «Mis solicitudes»
  /// esperando para siempre y muere con "Pending timers".
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');

  bool _quieto = false;

  @override
  void initState() {
    super.initState();
    if (widget.idle == null) {
      _propio = AnimationController(
        vsync: this,
        duration: JayaloMotion.idleCycle,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _quieto = _enTest || JayaloMotion.reduced(context);
    final c = _propio;
    if (c == null) return;
    if (_quieto) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    _propio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.estilo.color ?? Theme.of(context).colorScheme.onSurface;
    // Quieto = sin animación que escuchar. El reloj y los puntos saben
    // pintarse en reposo, así que la fila se ve igual de completa.
    final t = _quieto ? null : (widget.idle ?? _propio);
    final alto = widget.estilo.fontSize ?? 11;

    return Semantics(
      label: widget.label,
      // SIN `liveRegion`: esto no aparece y desaparece como el "escribiendo"
      // del chat — vive en pantalla todo el rato que dure la fase, y un
      // lector de pantalla anunciándolo en bucle sería insoportable.
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.reloj) ...[
              _Reloj(giro: t, ink: ink, tam: alto + 2),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.estilo,
              ),
            ),
            const SizedBox(width: 5),
            _Puntos(onda: t, ink: ink),
          ],
        ),
      ),
    );
  }
}

/// El reloj en avance rápido.
///
/// Dibujado a mano y no `Icons.schedule` girando: ese glifo YA trae las
/// manecillas puestas, así que superponerle una rotando daría un reloj de
/// cuatro agujas.
class _Reloj extends StatelessWidget {
  const _Reloj({required this.giro, required this.ink, required this.tam});

  /// 0..1 por vuelta de la manecilla larga, o null para dibujarlo quieto.
  final Animation<double>? giro;
  final Color ink;
  final double tam;

  @override
  Widget build(BuildContext context) {
    final g = giro;
    final cara = SizedBox(
      width: tam,
      height: tam,
      child: g == null
          ? CustomPaint(
              painter: _RelojPainter(t: _relojReposo, ink: ink),
            )
          : AnimatedBuilder(
              animation: g,
              builder: (context, _) => CustomPaint(
                painter: _RelojPainter(t: g.value, ink: ink),
              ),
            ),
    );
    // El bucle repinta ESTO, no la tarjeta que lo contiene.
    return g == null ? cara : RepaintBoundary(child: cara);
  }
}

class _RelojPainter extends CustomPainter {
  const _RelojPainter({required this.t, required this.ink});

  final double t;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - .7;
    final esfera = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true
      ..color = ink;
    canvas.drawCircle(c, r, esfera);

    void manecilla(double vueltas, double largo, double grosor) {
      final a = 2 * math.pi * vueltas - math.pi / 2; // 0 = las 12
      canvas.drawLine(
        c,
        c + Offset(math.cos(a), math.sin(a)) * (r * largo),
        Paint()
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..color = ink,
      );
    }

    // La corta va a 1/12 de la larga, como un reloj de verdad: es lo que hace
    // que el conjunto se lea como tiempo corriendo y no como algo girando.
    manecilla(t / 12, .46, 1.4);
    manecilla(t, .72, 1.2);
  }

  @override
  bool shouldRepaint(_RelojPainter old) => old.t != t || old.ink != ink;
}

/// Los tres puntos que rebotan, con ancho fijo.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.onda, required this.ink});

  /// 0..1 por vuelta del reloj (los puntos van a [_puntosPorVuelta] rebotes
  /// por vuelta), o null para dejarlos quietos.
  final Animation<double>? onda;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    Widget punto(int i) {
      final base = Container(
        width: _puntoTam,
        height: _puntoTam,
        decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
      );
      final o = onda;
      // Quietos: los tres opacos y a ras. La palabra ya dice lo que pasa; el
      // rebote es el adorno, no la información.
      if (o == null) return base;
      return AnimatedBuilder(
        animation: o,
        builder: (context, child) {
          final k = _pingPong(o.value * _puntosPorVuelta - i * _puntoAtraso);
          return Transform.translate(
            offset: Offset(0, -_puntoSalto * k),
            // La opacidad acompaña al salto (igual que en el chat): sin ella
            // el grupo se ve plano.
            child: Opacity(opacity: .45 + .55 * k, child: child),
          );
        },
        child: base,
      );
    }

    final fila = SizedBox(
      // Alto reservado para el salto: así la píldora no cambia de tamaño
      // mientras rebotan.
      height: _puntoTam + _puntoSalto,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : _puntoHueco),
              child: punto(i),
            ),
        ],
      ),
    );
    return onda == null ? fila : RepaintBoundary(child: fila);
  }
}
