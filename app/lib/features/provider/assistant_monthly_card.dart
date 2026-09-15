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
  List<({String id, String name})> _negocios = const [];
  String? _elegido;
  SubscriptionInfo? _info;
  bool _ocupado = false;
  bool _roto = false;

  String? get _token => widget.tokenProvider != null
      ? widget.tokenProvider!()
      : Supabase.instance.client.auth.currentSession?.accessToken;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final negocios =
          await (widget.loadBusinesses ?? myBusinessesForAssistant)();
      if (negocios.isEmpty) {
        if (mounted) setState(() => _roto = true);
        return;
      }
      final id = _elegido ?? negocios.first.id;
      final t = _token;
      if (t == null) {
        if (mounted) setState(() => _roto = true);
        return;
      }
      final info = await _client.subscription(businessId: id, accessToken: t);
      if (!mounted) return;
      setState(() {
        _negocios = negocios;
        _elegido = id;
        _info = info;
        _roto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _roto = true);
    }
  }

  Future<void> _suscribir() async {
    final t = _token;
    final id = _elegido;
    if (t == null || id == null) return;
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
    final info = _info;
    if (_roto || info == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final activa = info.activeUntil != null;

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
          // El selector SOLO existe con más de un negocio: hoy ningún proveedor
          // tiene dos, y una lista de un elemento sería ruido.
          if (_negocios.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _elegido,
              isExpanded: true,
              items: [
                for (final n in _negocios)
                  DropdownMenuItem(value: n.id, child: Text(n.name)),
              ],
              onChanged: _ocupado
                  ? null
                  : (v) {
                      setState(() => _elegido = v);
                      _cargar();
                    },
            ),
          ],
          const SizedBox(height: 10),
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
}
