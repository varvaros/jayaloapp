/// Ventana de "¡Tienes ofertas!" al entrar a la app (pedido PO 2026-08-11).
///
/// Al montar el shell, si el usuario tiene novedades sin ver se le celebra con
/// una ventana simpática y un CTA directo a donde están:
///   • CLIENTE: notificaciones `offer_new` sin leer → "¡Tienes ofertas nuevas!"
///   • PROVEEDOR: `offer_accepted` sin leer → "¡Te dijeron que SÍ!"
///
/// Anti-fastidio: se recuerda (SharedPreferences) la notificación más reciente
/// ya anunciada — la ventana solo reaparece cuando llega algo NUEVO desde el
/// último anuncio, no en cada arranque con el mismo lote pendiente. Todo es
/// best-effort: cualquier fallo de red se traga en silencio (la campana y los
/// badges siguen contando la historia completa).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart' show supa;
import 'jayalo_loader.dart';

/// Guard por ejecución: aunque el shell se re-monte (cambio de rol, hot
/// restart de sesión), la ventana no se repite dentro del mismo arranque.
bool _yaMostradaEstaSesion = false;

@visibleForTesting
void resetNewOffersPopupForTest() => _yaMostradaEstaSesion = false;

/// Copys de la ventana según rol y cantidad. Pura y pública para testear.
({String titulo, String detalle, String cta}) newOffersCopy({
  required bool esProveedor,
  required int count,
}) {
  if (esProveedor) {
    return (
      titulo: '¡Te dijeron que SÍ! 🥳',
      detalle: count == 1
          ? 'Un cliente aceptó tu oferta. Corre a cerrar el trato antes de que '
              'le dé tiempo de pensarlo dos veces.'
          : '$count clientes aceptaron tus ofertas. Hoy se cierra más de un '
              'trato — no los dejes esperando.',
      cta: 'Ver mis ofertas',
    );
  }
  return (
    titulo: '¡Tienes ofertas nuevas! 🎉',
    detalle: count == 1
        ? 'Un proveedor ya te echó el ojo y te mandó su oferta. Ve a verla '
            'antes de que se enfríe.'
        : '$count proveedores andan detrás de lo tuyo. Ve a compararlos '
            'con calma — tú mandas.',
    cta: 'Ver ofertas',
  );
}

/// Revisa si hay novedades y, si las hay, muestra la ventana. Llamar tras el
/// primer frame del shell (el gate garantiza que el rol ya está resuelto).
Future<void> maybeShowNewOffersPopup(BuildContext context) async {
  if (_yaMostradaEstaSesion) return;
  final esProveedor = roleStore.value == RoleState.provider;
  final kind = esProveedor ? 'offer_accepted' : 'offer_new';

  List<Map<String, dynamic>> rows;
  final String uid;
  try {
    // El acceso a `supa` también va dentro del try: en los widget-tests del
    // shell Supabase no está inicializado (`Supabase.instance` dispara un
    // assert) y la ventana simplemente no existe ahí — mismo patrón que
    // MessagesBadgeStore.
    final id = supa.auth.currentUser?.id;
    if (id == null) return;
    uid = id;
    rows = List<Map<String, dynamic>>.from(
      await supa
          .from('notifications')
          .select('id,created_at')
          .eq('user_id', uid)
          .eq('kind', kind)
          .isFilter('read_at', null)
          .order('created_at', ascending: false)
          .limit(30),
    );
  } catch (_) {
    return; // sin red (o sin Supabase, en tests) no se molesta a nadie
  }
  if (rows.isEmpty) return;

  final masReciente = rows.first['created_at']?.toString() ?? '';
  final prefs = await SharedPreferences.getInstance();
  final prefKey = 'offers_popup_last.$kind.$uid';
  // Mismo lote que la última vez = ya se anunció; solo celebra lo nuevo.
  if (prefs.getString(prefKey) == masReciente) return;

  if (!context.mounted) return;
  _yaMostradaEstaSesion = true;
  await prefs.setString(prefKey, masReciente);

  final copy = newOffersCopy(esProveedor: esProveedor, count: rows.length);
  final destino = esProveedor ? '/provider/offers' : '/client';
  JayaloHaptics.sent();
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: copy.titulo,
    barrierColor: Colors.black38,
    transitionDuration: JayaloMotion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 320),
    // Mismo lenguaje de entrada que las celebraciones: zoom-in con rebote.
    transitionBuilder: (context, anim, _, child) {
      final scale = Tween<double>(begin: .82, end: 1).animate(
        CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        ),
      );
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
    pageBuilder: (dialogCtx, _, _) => _NewOffersDialog(
      titulo: copy.titulo,
      detalle: copy.detalle,
      cta: copy.cta,
      onVer: () {
        Navigator.of(dialogCtx).pop();
        // `go` y no `push`: el destino es una pestaña del shell.
        context.go(destino);
      },
    ),
  );
}

class _NewOffersDialog extends StatelessWidget {
  const _NewOffersDialog({
    required this.titulo,
    required this.detalle,
    required this.cta,
    required this.onVer,
  });

  final String titulo;
  final String detalle;
  final String cta;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Jayi de fiesta: la misma mascota del loader, en grande.
                const Center(child: JayaloMascot(size: 84)),
                const SizedBox(height: 14),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: jayaloHead(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detalle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onVer,
                  child: Text(cta),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Ahora no',
                    style: TextStyle(
                        fontSize: 13.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
