import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estado de EMBUDO por conversación — herramienta PRIVADA del proveedor
/// (pedido PO 2026-07-22) para llevar su funnel de ventas. Se persiste en la BD
/// (tabla `provider_funnel_status`, RLS solo-dueño → el cliente NUNCA lo ve),
/// así sincroniza entre dispositivos y sobrevive a reinstalar. Antes vivía solo
/// en SharedPreferences (local) — el PO revirtió esa decisión (2026-07-22).
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
  static const _table = 'provider_funnel_status';
  final Map<String, String> _byConv = {};
  bool _loaded = false;
  String? _loadedForUid;

  SupabaseClient get _db => Supabase.instance.client;

  /// Carga el embudo del proveedor desde la BD (solo sus filas por RLS).
  /// Best-effort: sin red se arranca vacío. Se recarga si cambia el usuario
  /// logueado (los datos son por proveedor, no por dispositivo).
  Future<void> ensureLoaded() async {
    final uid = _db.auth.currentUser?.id;
    if (_loaded && _loadedForUid == uid) return;
    _loaded = true;
    _loadedForUid = uid;
    _byConv.clear();
    if (uid == null) {
      notifyListeners();
      return;
    }
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _db
            .from(_table)
            .select('conversation_id,status')
            .eq('user_id', uid),
      );
      for (final r in rows) {
        final c = r['conversation_id'] as String?;
        final s = r['status'] as String?;
        if (c != null && s != null && s.isNotEmpty) _byConv[c] = s;
      }
    } catch (_) {
      // Best-effort: sin persistencia se arranca vacío.
    }
    notifyListeners();
  }

  String? statusKey(String convId) => _byConv[convId];

  Future<void> setStatus(String convId, String? key) async {
    // Optimista en memoria para respuesta inmediata; la BD es la fuente real.
    if (key == null || key.isEmpty) {
      _byConv.remove(convId);
    } else {
      _byConv[convId] = key;
    }
    notifyListeners();
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      if (key == null || key.isEmpty) {
        await _db
            .from(_table)
            .delete()
            .eq('user_id', uid)
            .eq('conversation_id', convId);
      } else {
        await _db.from(_table).upsert({
          'user_id': uid,
          'conversation_id': convId,
          'status': key,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,conversation_id');
      }
    } catch (_) {}
  }
}

final funnelStatusStore = FunnelStatusStore();
