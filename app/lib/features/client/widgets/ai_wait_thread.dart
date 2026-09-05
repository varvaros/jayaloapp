import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../domain/ai_wait_steps.dart';

/// El hilo de pasos que ocupa el hueco de «Pensando…» mientras la IA
/// responde (spec 2026-09-05). Es un widget TONTO: recibe un [AiWaitState]
/// ya calculado (`aiWaitState`) y lo pinta. El reloj y el reporte viven en
/// la pantalla.
///
/// Ámbar para los avisos, nunca rojo: el rojo queda para errores de verdad
/// (misma regla que los estados de error de la web).
class AiWaitThread extends StatelessWidget {
  const AiWaitThread({super.key, required this.state, required this.reduced});

  final AiWaitState state;

  /// `JayaloMotion.reduced(context)`: sin pulso ni entradas animadas.
  final bool reduced;

  static const _ambar = Color(0xFFB8862B);
  static const _ambarFondo = Color(0xFFFBF1DC);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < state.pasos.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _Paso(index: i, paso: state.pasos[i], reduced: reduced, cs: cs),
          ],
          if (state.aviso > 0) ...[
            const SizedBox(height: 12),
            _Aviso(
              titulo: state.aviso == 2 ? kAiWaitAviso2Titulo : kAiWaitAviso1Titulo,
              texto: state.aviso == 2 ? kAiWaitAviso2Texto : kAiWaitAviso1Texto,
              reduced: reduced,
            ),
          ],
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({
    required this.index,
    required this.paso,
    required this.reduced,
    required this.cs,
  });

  final int index;
  final AiWaitStep paso;
  final bool reduced;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final estado = paso.estado;
    final Widget marca = switch (estado) {
      AiWaitStepState.hecho => Container(
          key: ValueKey('ai-wait-hecho-$index'),
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 12, color: Colors.white),
        ),
      AiWaitStepState.activo => _Pulso(
          key: ValueKey('ai-wait-activo-$index'),
          color: cs.primary,
          reduced: reduced,
        ),
      AiWaitStepState.pendiente => Container(
          key: ValueKey('ai-wait-pendiente-$index'),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
        ),
    };
    final texto = Text(
      paso.texto,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.3,
        fontWeight:
            estado == AiWaitStepState.activo ? FontWeight.w600 : FontWeight.w400,
        color: switch (estado) {
          AiWaitStepState.activo => cs.onSurface,
          AiWaitStepState.hecho => cs.onSurface.withValues(alpha: .8),
          AiWaitStepState.pendiente => cs.onSurfaceVariant.withValues(alpha: .55),
        },
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 18, height: 18, child: Center(child: marca)),
        const SizedBox(width: 10),
        Expanded(
          // El paso ACTIVO se anuncia al cambiar: es la única línea que
          // «avanza». Los demás son texto normal.
          child: estado == AiWaitStepState.activo
              ? Semantics(liveRegion: true, child: texto)
              : texto,
        ),
      ],
    );
  }
}

/// Punto violeta con un anillo que se expande (1,4 s). Con `reduced` o bajo
/// `flutter test` se queda quieto: un bucle infinito rompe `pumpAndSettle`.
class _Pulso extends StatefulWidget {
  const _Pulso({super.key, required this.color, required this.reduced});
  final Color color;
  final bool reduced;

  @override
  State<_Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<_Pulso> with SingleTickerProviderStateMixin {
  static final _enTest = Platform.environment.containsKey('FLUTTER_TEST');
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduced && !_enTest) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Pulso old) {
    super.didUpdateWidget(old);
    if (widget.reduced || _enTest) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = Curves.easeOut.transform(_c.value);
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .16),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (!widget.reduced && !_enTest)
                      BoxShadow(
                        color: widget.color.withValues(alpha: .45 * (1 - t)),
                        spreadRadius: 9 * t,
                      ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.titulo, required this.texto, required this.reduced});
  final String titulo;
  final String texto;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final caja = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AiWaitThread._ambarFondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AiWaitThread._ambar,
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(text: '$titulo ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: texto),
          ],
        ),
      ),
    );
    if (reduced) return caja;
    return TweenAnimationBuilder<double>(
      key: ValueKey(titulo),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child),
      ),
      child: caja,
    );
  }
}
