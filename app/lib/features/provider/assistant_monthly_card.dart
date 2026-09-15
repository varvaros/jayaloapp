import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/assistant_client.dart';
import '../../data/repos.dart';
import '../shared/moneda.dart';

/// El plan mensual del asistente de ventas, dentro de la tienda de créditos.
///
/// Se paga con **créditos**, no con dinero: no toca Play Billing ni su
/// comisión. Por eso vive separada de las tarjetas de paquetes.
///
/// Carga sola y con su propio try, como `_cargarSaldo`: que no se sepa el
/// estado de la suscripción no puede dejar sin tienda a quien viene a recargar.
class AssistantMonthlyCard extends StatefulWidget {
  const AssistantMonthlyCard({
    super.key,
    this.client,
    this.loadBusinesses,
    this.tokenProvider,
  });

  final AssistantClient? client;
  final Future<List<({String id, String name})>> Function()? loadBusinesses;
  final String? Function()? tokenProvider;

  @override
  State<AssistantMonthlyCard> createState() => _AssistantMonthlyCardState();
}

class _AssistantMonthlyCardState extends State<AssistantMonthlyCard> {
  late final AssistantClient _client = widget.client ?? AssistantClient();

  /// Ordenados por `created_at` ascendente, IGUAL que el servidor. Nunca se
  /// elige aquí: el servidor siempre resuelve el negocio con el que activa el
  /// asistente como «el primero de esta lista» (`conversations` no tiene
  /// `business_id`), así que la tarjeta no puede ofrecer un negocio distinto
  /// — hacerlo cobraría dos créditos por chat, indefinidamente, sin avisar.
  List<({String id, String name})> _negocios = const [];
  SubscriptionInfo? _info;
  bool _ocupado = false;
  bool _cargando = false;

  /// El proveedor no tiene ningún negocio: no hay nada que ofrecer, y no es
  /// un fallo — no aplica reintentar.
  bool _sinNegocio = false;

  /// La ÚLTIMA carga (inicial o recarga) falló.
  ///
  /// Si nunca hubo [_info] pintada, el efecto es el de siempre: invisible
  /// (`build` corta antes de mirar esta bandera). Pero si YA había algo
  /// pintado — p. ej. la recarga que sigue a `_suscribir` — esta bandera SÍ
  /// importa: un fallo de red no puede borrar lo que el proveedor ya vio.
  bool _error = false;

  String? get _token => widget.tokenProvider != null
      ? widget.tokenProvider!()
      : Supabase.instance.client.auth.currentSession?.accessToken;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final negocios =
          await (widget.loadBusinesses ?? myBusinessesForAssistant)();
      if (negocios.isEmpty) {
        if (!mounted) return;
        setState(() {
          _sinNegocio = true;
          _error = false;
        });
        return;
      }
      final id = negocios.first.id;
      final t = _token;
      if (t == null) {
        if (!mounted) return;
        setState(() => _error = true);
        return;
      }
      final info = await _client.subscription(businessId: id, accessToken: t);
      if (!mounted) return;
      setState(() {
        _negocios = negocios;
        _info = info;
        _error = false;
        _sinNegocio = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _suscribir() async {
    final t = _token;
    if (t == null || _negocios.isEmpty) return;
    final id = _negocios.first.id;
    setState(() => _ocupado = true);
    try {
      final r = await _client.subscribe(businessId: id, accessToken: t);
      if (!mounted) return;
      _aviso(r.charged > 0
          ? 'Plan mensual activo (${r.charged} créditos).'
          : 'Ya tenías el plan mensual activo.');
      await _cargar();
    } on AssistantException catch (e) {
      if (e.sinSaldo) {
        final faltan = (e.cost ?? 0) - (e.balance ?? 0);
        _aviso(faltan > 0
            ? 'Te faltan $faltan créditos para el plan mensual.'
            : 'No tienes créditos suficientes.');
      } else {
        _aviso(e.message);
      }
    } catch (_) {
      _aviso('No se pudo activar el plan. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// Fecha en el calendario LOCAL. `toIso8601String()` daría el día de UTC, que
  /// en Santo Domingo puede ser el siguiente.
  String _fechaCorta(DateTime d) {
    final l = d.toLocal();
    return '${l.day} de ${_meses[l.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_sinNegocio) return const SizedBox.shrink();
    final info = _info;
    // Sin nada pintado todavía (cargando, o la PRIMERA carga falló):
    // invisible, igual que siempre — no hay nada que evaporar. Ver el
    // comentario de [_error]: lo que cambia es la recarga DESPUÉS de haber
    // pintado algo, más abajo.
    if (info == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final activa = info.activeUntil != null;
    final variosNegocios = _negocios.length > 1;
    // La RPC calcula el coste con GREATEST(1, …): un coste ≤ 0 nunca es
    // legítimo, siempre significa que no llegó. El precio no se inventa en
    // el cliente, así que sin coste válido no se pinta el botón.
    final precioValido = info.monthlyCost > 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, size: 17, color: cs.primary),
            const SizedBox(width: 6),
            const Text('Plan mensual del asistente',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(
            activa
                ? 'Suscripción activa hasta el ${_fechaCorta(info.activeUntil!)}.'
                : 'Sin suscripción mensual.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            'Todos los chats de este negocio incluidos por 30 días.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          // Nunca se elige el negocio aquí (ver el comentario de _negocios):
          // con más de uno, la tarjeta al menos DICE a cuál se aplica. Con
          // uno solo, nada cambia en pantalla.
          if (variosNegocios) ...[
            const SizedBox(height: 2),
            Text(
              'Se aplica a ${_negocios.first.name}.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          if (_error) ...[
            const SizedBox(height: 8),
            _avisoRecarga(context),
          ],
          const SizedBox(height: 10),
          if (precioValido)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _ocupado ? null : _suscribir,
                child: _ocupado
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(activa ? 'Renovar' : 'Activar'),
                        const SizedBox(width: 6),
                        const MonedaJayalo(size: 14),
                        const SizedBox(width: 3),
                        Text('${info.monthlyCost}'),
                      ]),
              ),
            ),
        ],
      ),
    );
  }

  /// Ya había [_info] pintada y la ÚLTIMA recarga falló (p. ej. al refrescar
  /// después de suscribirse): se avisa sin borrar lo que ya se sabía.
  Widget _avisoRecarga(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, size: 14, color: cs.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'No se pudo actualizar. Puede que esto ya no sea lo más reciente.',
            style: TextStyle(fontSize: 11, color: cs.error),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          onPressed: _cargando ? null : _cargar,
          child: const Text('Reintentar', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}
