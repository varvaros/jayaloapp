import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/assistant_client.dart';
import '../../shared/moneda.dart';
import 'assistant_bar_view.dart';

/// El mando del asistente de ventas dentro del chat del proveedor.
///
/// Se lo come todo él —estado, llamadas y avisos— a propósito:
/// `chat_screen.dart` son 1662 líneas y esta barra solo le añade cuatro.
///
/// [tokenProvider] y [client] existen para la batería. En producción salen de
/// la sesión viva y de un `AssistantClient` de verdad.
class AssistantBar extends StatefulWidget {
  const AssistantBar({
    super.key,
    required this.conversationId,
    this.client,
    this.tokenProvider,
    this.onReplied,
  });

  final String conversationId;
  final AssistantClient? client;
  final String? Function()? tokenProvider;

  /// El asistente acaba de escribir: la pantalla recarga los mensajes.
  final VoidCallback? onReplied;

  @override
  State<AssistantBar> createState() => _AssistantBarState();
}

class _AssistantBarState extends State<AssistantBar> {
  late final AssistantClient _client = widget.client ?? AssistantClient();
  AssistantState? _estado;
  bool _ocupado = false;

  /// Distinto de `_estado == null`: si la primera lectura falla, la barra no se
  /// pinta en absoluto. Nunca se inventa un estado.
  bool _roto = false;

  String? get _token => widget.tokenProvider != null
      ? widget.tokenProvider!()
      : Supabase.instance.client.auth.currentSession?.accessToken;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  Future<void> _refrescar() async {
    final t = _token;
    if (t == null) {
      if (mounted) setState(() => _roto = true);
      return;
    }
    try {
      final s = await _client.state(
          conversationId: widget.conversationId, accessToken: t);
      if (!mounted) return;
      setState(() {
        _estado = s;
        _roto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _roto = true);
    }
  }

  void _aviso(String msg, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), action: accion));
  }

  /// El único fallo con camino de salida: sin saldo se va a la tienda, no se
  /// deja al proveedor con un aviso seco.
  void _avisoDeFallo(Object e) {
    if (e is AssistantException && e.sinSaldo) {
      final faltan = (e.cost ?? 0) - (e.balance ?? 0);
      _aviso(
        faltan > 0
            ? 'Te faltan $faltan créditos para esto.'
            : 'No tienes créditos suficientes.',
        accion: SnackBarAction(
          label: 'Recargar',
          onPressed: () => context.push('/tienda-creditos'),
        ),
      );
      return;
    }
    _aviso(
        e is AssistantException ? e.message : 'No se pudo completar la acción.');
  }

  Future<void> _conOcupado(Future<void> Function(String token) accion) async {
    final t = _token;
    if (t == null) return;
    setState(() => _ocupado = true);
    try {
      await accion(t);
      await _refrescar();
    } catch (e) {
      _avisoDeFallo(e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _activar() => _conOcupado((t) async {
        final r = await _client.activate(
            conversationId: widget.conversationId, accessToken: t);
        if (r.alreadyActive) {
          _aviso('El asistente ya estaba activo en este chat.');
        } else if (r.charged > 0) {
          _aviso('Asistente activado (${r.charged} créditos).');
        } else if (r.billingMode == 'monthly') {
          _aviso('Asistente activado (plan mensual).');
        } else {
          _aviso('Asistente activado.');
        }
      });

  Future<void> _pausar(bool pausar) => _conOcupado((t) async {
        await _client.pause(
            conversationId: widget.conversationId,
            paused: pausar,
            accessToken: t);
        _aviso(pausar ? 'Asistente pausado.' : 'Asistente reactivado.');
      });

  /// Enciende el interruptor maestro sin salir del chat. No cobra: el chat ya
  /// se pagó al activarlo.
  Future<void> _encender() => _conOcupado((t) async {
        await _client.enable(
            conversationId: widget.conversationId, accessToken: t);
        _aviso('Asistente encendido.');
      });

  Future<void> _responder() => _conOcupado((t) async {
        final r = await _client.reply(
            conversationId: widget.conversationId, accessToken: t);
        if (r.sent) {
          _aviso('El asistente respondió.');
          widget.onReplied?.call();
        } else {
          _aviso('No se generó respuesta.');
        }
      });

  @override
  Widget build(BuildContext context) {
    if (_roto) return const SizedBox.shrink();
    final v = assistantBarView(_estado);
    if (v.kind == AssistantBarKind.loading) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final pausado = v.kind == AssistantBarKind.paused;
    final apagado = v.kind == AssistantBarKind.disabled;
    final fondo = apagado
        ? cs.surfaceContainerHighest
        : pausado
            ? const Color(0x22F2B705)
            : cs.primaryContainer;
    final tinta = apagado ? cs.onSurfaceVariant : cs.onPrimaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: fondo,
      child: Row(
        children: [
          Icon(apagado ? Icons.smart_toy_outlined : Icons.auto_awesome,
              size: 16, color: tinta),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              switch (v.kind) {
                AssistantBarKind.disabled => 'Asistente IA apagado',
                AssistantBarKind.off => 'Asistente IA',
                AssistantBarKind.on => 'Asistente IA activo',
                AssistantBarKind.paused => 'Asistente IA pausado',
                AssistantBarKind.loading => '',
              },
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: tinta),
            ),
          ),
          if (v.handover) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0x33F2B705),
                  borderRadius: BorderRadius.circular(999)),
              child: const Text('Cliente pidió humano',
                  style: TextStyle(fontSize: 10.5)),
            ),
          ],
          const Spacer(),
          if (_ocupado)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            // El maestro apagado se enciende AQUÍ y gratis. La configuración del
            // asistente (guion, FAQ, objetivos) sigue siendo web-only, pero
            // ENCENDERLO no tiene por qué serlo: con el maestro apagado el motor
            // sale de vacío y el chat se queda mudo sin salida dentro de la app.
            if (apagado)
              FilledButton(
                onPressed: _encender,
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Text('Encender', style: TextStyle(fontSize: 12.5)),
              ),
            if (v.kind == AssistantBarKind.off)
              FilledButton(
                onPressed: _activar,
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Activar', style: TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 4),
                  const MonedaJayalo(size: 13),
                  const SizedBox(width: 2),
                  Text('${v.cost}', style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            if (v.kind == AssistantBarKind.on) ...[
              IconButton(
                tooltip: 'Responder ahora',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.bolt, size: 18, color: tinta),
                onPressed: _responder,
              ),
              IconButton(
                tooltip: 'Pausar',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.pause, size: 18, color: tinta),
                onPressed: () => _pausar(true),
              ),
            ],
            if (pausado)
              IconButton(
                tooltip: 'Reactivar',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.play_arrow, size: 18, color: tinta),
                onPressed: () => _pausar(false),
              ),
          ],
        ],
      ),
    );
  }
}
