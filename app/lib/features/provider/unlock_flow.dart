/// Flujo compartido de DESBLOQUEO del contacto de una oferta aceptada.
///
/// Extraído de `my_offers_screen.dart` (2026-07-21) porque el PO pidió que el
/// botón "Desbloquear" salga en TODOS los lugares donde se abre una oferta
/// aceptada (Mis ofertas Y el detalle de la solicitud "Ya ofertaste"), no solo
/// en la lista.
///
/// ⚠️ BUG RAÍZ arreglado 2026-07-21 (el PO lo pidió 4 veces): el flujo llamaba
/// `can_reveal_offer_whatsapp` ANTES de desbloquear como "barrera de dinero".
/// Pero ese RPC exige `unlocked_at IS NOT NULL` (solo dice si se puede REVELAR
/// el WhatsApp de una oferta YA pagada), así que ANTES de pagar SIEMPRE daba
/// false → nunca aparecía "Desbloquear contacto", salía "Contacto aún no
/// disponible". La web (ProviderOffersSection.tsx) NO hace esa comprobación:
/// muestra el botón de desbloquear siempre que la oferta esté aceptada y usa
/// `can_reveal_offer_whatsapp` SOLO después de pagar (para el botón "ver
/// WhatsApp"). `try_unlock_offer` tampoco revisa revelabilidad. Aquí se replica
/// la web: al aceptar → hold + costo → cobrar; la revelabilidad solo afecta lo
/// que se muestra DESPUÉS (la hoja de contacto ya cae con gracia al chat si el
/// cliente no tiene WhatsApp verificado). Barreras que SÍ se conservan:
///   • Saldo insuficiente → ofrecer recargar, nunca lanzar a un cobro fallido.
///   • Contacto YA pagado: un fallo de red jamás se presenta como "no hay
///     contacto" — siempre Reintentar.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../../domain/recharge.dart';
import '../shared/brand_kit.dart';
import '../shared/celebration.dart';

/// Costo estimado (en créditos) de desbloquear una oferta. El server lo
/// recalcula e IGNORA lo enviado (regla de seguridad del proyecto).
int estimatedUnlockCost(Map<String, dynamic> o) {
  final c = pointsForOffer(
    price: (o['price'] as num?)?.toDouble(),
    priceMin: (o['price_min'] as num?)?.toDouble(),
    priceMax: (o['price_max'] as num?)?.toDouble(),
    pricingMode: o['pricing_mode'] as String?,
    hourlyRate: (o['hourly_rate'] as num?)?.toDouble(),
    estimatedHours: (o['estimated_hours'] as num?)?.toDouble(),
  );
  return c < 1 ? 1 : c;
}

void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

/// ADR-0031: el pago SIEMPRE ocurre fuera de la app (navegador del sistema).
/// Intenta abrir con un magic link autenticado (evita el segundo login);
/// si falla, cae al link plano (el usuario puede necesitar loguearse ahí).
Future<void> openProviderWallet(BuildContext context) async {
  Uri target = Uri.parse(AppConfig.walletUrl);
  try {
    target = Uri.parse(await createWalletLoginLink());
  } catch (_) {}
  var ok = false;
  try {
    ok = await launchUrl(target, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    _snack(context, 'No se pudo abrir el navegador. Visita jayalo.com para recargar.');
  }
}

/// Arranca el flujo completo: chequeo de revelable → hoja de desbloqueo (hold
/// + costo + saldo) → celebración → hoja de contacto. [onChanged] se llama
/// tras cualquier mutación (desbloqueo o venta marcada) para que quien llamó
/// refresque su vista.
Future<void> startUnlockFlow(
  BuildContext context,
  Map<String, dynamic> offer, {
  Future<void> Function()? onChanged,
}) async {
  // SIN comprobación previa de revelabilidad (ver el bug raíz en la cabecera):
  // se va directo a la hoja de "Desbloquear contacto", igual que la web.
  // Saldo fresco para decidir hold vs recargar.
  int? balance;
  try {
    balance = await walletBalance();
  } catch (_) {
    balance = null; // shouldOfferRecharge trata null como "sin saldo"
  }
  if (!context.mounted) return;
  final cost = estimatedUnlockCost(offer);
  final needsRecharge = shouldOfferRecharge(balance: balance, cost: cost);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    isScrollControlled: true,
    // Sube casi al centro (pedido PO 2026-07-22): hoja alta con el contenido
    // centrado, en vez de una franja pegada al borde inferior.
    builder: (ctx) => _TallSheet(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded,
                  color: Theme.of(ctx).colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 14),
            Text('Desbloquear contacto',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                'Costo: $cost crédito${cost == 1 ? '' : 's'} · Tu saldo: ${balance ?? 0}',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (needsRecharge)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openProviderWallet(context);
                },
                child: const Text('Saldo insuficiente — Recargar'),
              )
            else
              HoldToConfirmButton(onConfirmed: () async {
                Navigator.pop(ctx);
                final res = await unlockOffer(offer['id'] as String, cost);
                if (!context.mounted) return;
                if (res.ok) {
                  await showUnlockCelebration(context); // 🔓 violeta + candado
                  if (!context.mounted) return;
                  await onChanged?.call();
                  // TODOS los contactos desbloqueados aparecen en el chat
                  // (pedido PO 2026-07-22): se crea la conversación al pagar,
                  // best-effort, sin bloquear el flujo.
                  try {
                    await getOrCreateConversation(
                        kind: 'offer', sourceId: offer['id'] as String);
                  } catch (_) {}
                  // Fila fresca (unlocked_at ya puesto) para la hoja de
                  // contacto; si falla la red se usa la que había.
                  var fresh = offer;
                  try {
                    fresh = await offerForEdit(offer['id'] as String) ?? offer;
                  } catch (_) {}
                  if (!context.mounted) return;
                  showOfferContactSheet(context, fresh, onChanged: onChanged);
                } else {
                  _snack(context, 'No se pudo desbloquear. Intenta de nuevo.');
                }
              }),
          ]),
    ),
  );
}

/// Hoja del contacto YA desbloqueado: nombre + WhatsApp + "marcar completada".
Future<void> showOfferContactSheet(
  BuildContext context,
  Map<String, dynamic> offer, {
  Future<void> Function()? onChanged,
}) async {
  ({String? firstName, String? phone}) contact;
  try {
    contact = await unlockedContact(offer['id'] as String);
  } catch (_) {
    if (!context.mounted) return;
    // Derecho YA pagado: jamás presentar un fallo como "no hay contacto"
    // (el catch silencioso aquí era el bug de dinero 2026-07-16).
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('No pudimos cargar el contacto',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Tu desbloqueo está guardado — no se te volverá a cobrar. '
                  'Revisa tu conexión e intenta de nuevo.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  showOfferContactSheet(context, offer, onChanged: onChanged);
                },
                child: const Text('Reintentar'),
              ),
            ]),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  // ¿El cliente permite WhatsApp? `can_reveal_offer_whatsapp` (post-unlock,
  // aquí SÍ aplica: `unlocked_at` ya está puesto) es true solo si el cliente
  // tiene WhatsApp verificado Y activó "que me contacten por WhatsApp". Si no,
  // el botón de WhatsApp NO aparece (pedido PO 2026-07-22) — solo el chat.
  var canWhatsapp = false;
  if (contact.phone != null) {
    try {
      canWhatsapp = await canRevealOffer(offer['id'] as String);
    } catch (_) {}
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    isScrollControlled: true,
    // Sube casi al centro (pedido PO 2026-07-22): antes quedaba muy abajo.
    builder: (ctx) => _TallSheet(
      heightFactor: .62,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('✅ Contacto desbloqueado',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(canWhatsapp && contact.phone != null
                ? (contact.firstName ?? 'Cliente')
                : 'Escríbele a ${contact.firstName ?? 'tu cliente'} por el '
                    'chat de Jayalo.'),
            const SizedBox(height: 4),
            Text(
                'Da el primer paso: un saludo rápido y tu propuesta cierran más '
                'tratos que esperar a que escriban.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            // Chat interno de Jayalo (kind 'offer', como la web): la vía
            // principal y con respaldo.
            FilledButton.icon(
              onPressed: () async {
                String? convId;
                try {
                  convId = await getOrCreateConversation(
                      kind: 'offer', sourceId: offer['id'] as String);
                } catch (_) {}
                if (!ctx.mounted) return;
                if (convId == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('No se pudo abrir el chat. Intenta de nuevo.')));
                  return;
                }
                Navigator.pop(ctx);
                context.push('/messages/$convId',
                    extra: {'peer_name': contact.firstName});
              },
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Escribir al cliente por el chat'),
            ),
            if (canWhatsapp && contact.phone != null) ...[
              const SizedBox(height: 12),
              _WhatsappReveal(
                  phone: contact.phone!, firstName: contact.firstName),
            ],
            const SizedBox(height: 8),
            if (offer['purchase_completed'] != true)
              OutlinedButton(
                onPressed: () async {
                  await markPurchaseCompleted(offer['id'] as String);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await onChanged?.call();
                },
                child: const Text('¿Se concretó la venta? Marcar completada'),
              ),
          ]),
    ),
  );
}

/// Hoja alta que sube casi al centro (pedido PO 2026-07-22): reserva una
/// fracción de la pantalla y centra su contenido, en vez de una franja pegada
/// al borde inferior. Suma el inset del sistema para no quedar tras el navbar.
class _TallSheet extends StatelessWidget {
  const _TallSheet({required this.child, this.heightFactor = .5});
  final Widget child;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SizedBox(
      width: double.infinity,
      height: mq.size.height * heightFactor,
      child: Padding(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            bottom: mq.viewInsets.bottom + mq.padding.bottom + 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Flexible(child: SingleChildScrollView(child: child))],
        ),
      ),
    );
  }
}

/// Ver el WhatsApp = doble advertencia (pedido PO 2026-07-22): una nota clara
/// de que por WhatsApp NO hay devolución de créditos si el lead no responde
/// (el chat interno sí queda como respaldo), y un hold-to-confirm para abrirlo.
class _WhatsappReveal extends StatelessWidget {
  const _WhatsappReveal({required this.phone, required this.firstName});
  final String phone;
  final String? firstName;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final warnBg = dark ? const Color(0x33F2B705) : const Color(0xFFFFF3D6);
    final warnInk = dark ? const Color(0xFFF2CF7A) : const Color(0xFF8A5A00);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warnBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.info_outline, size: 18, color: warnInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Antes de abrir WhatsApp',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: warnInk, fontSize: 13.5)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            'Si hablas por WhatsApp y el cliente no responde, no hay devolución '
            'de créditos. El chat de Jayalo sí queda como respaldo del contacto. '
            'Mantén presionado si aun así prefieres WhatsApp.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: warnInk)),
        const SizedBox(height: 12),
        HoldToConfirmButton(
          tone: HoldToConfirmTone.free,
          label: 'Mantén para ver WhatsApp',
          onConfirmed: () async {
            final digits = phone.replaceAll(RegExp(r'\D'), '');
            await launchUrl(Uri.parse('https://wa.me/$digits'),
                mode: LaunchMode.externalApplication);
          },
        ),
      ]),
    );
  }
}
