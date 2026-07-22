import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado de EMBUDO por conversación — herramienta PRIVADA del proveedor
/// (pedido PO 2026-07-22) para llevar su funnel de ventas. NO se guarda en la
/// BD (el cliente NUNCA lo ve): vive local en el dispositivo
/// (SharedPreferences), un estado por conversación. Se pierde al reinstalar y
/// no sincroniza entre dispositivos — decisión explícita del PO.
class FunnelStatus {
  const FunnelStatus(this.key, this.label, this.emoji, this.color);
  final String key;
  final String label;
  final String emoji;
  final Color color;
}

/// Etapas del embudo + alertas (orden = flujo natural). Tu lista + sugerencias.
const funnelStatuses = <FunnelStatus>[
  FunnelStatus('negociando', 'Negociando', '💬', Color(0xFF6366F1)),
  FunnelStatus('avanzado', 'Avanzado', '🔥', Color(0xFF7C3AED)),
  FunnelStatus('pago', 'Pagó', '💰', Color(0xFF16A34A)),
  FunnelStatus('esperando_envio', 'Esperando envío', '📦', Color(0xFFD97706)),
  FunnelStatus('entregado', 'Entregado', '✅', Color(0xFF15803D)),
  FunnelStatus('cuidado', 'Cuidado', '⚠️', Color(0xFFEA580C)),
  FunnelStatus('molesto', 'Molesto', '😠', Color(0xFFDC2626)),
  FunnelStatus('perdido', 'Perdido', '❌', Color(0xFF991B1B)),
];

FunnelStatus? funnelStatusByKey(String? key) {
  if (key == null) return null;
  for (final s in funnelStatuses) {
    if (s.key == key) return s;
  }
  return null;
}

class FunnelStatusStore extends ChangeNotifier {
  static const _prefix = 'funnel_status_';
  final Map<String, String> _byConv = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final v = sp.getString(k);
        if (v != null && v.isNotEmpty) _byConv[k.substring(_prefix.length)] = v;
      }
    } catch (_) {
      // Best-effort: sin persistencia se arranca vacío.
    }
    notifyListeners();
  }

  String? statusKey(String convId) => _byConv[convId];

  Future<void> setStatus(String convId, String? key) async {
    if (key == null || key.isEmpty) {
      _byConv.remove(convId);
    } else {
      _byConv[convId] = key;
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      if (key == null || key.isEmpty) {
        await sp.remove('$_prefix$convId');
      } else {
        await sp.setString('$_prefix$convId', key);
      }
    } catch (_) {}
  }
}

final funnelStatusStore = FunnelStatusStore();
