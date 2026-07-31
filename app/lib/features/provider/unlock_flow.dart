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

import 'dart:async'; // unawaited

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/secure_web_launch.dart';
import '../../core/motion.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../../domain/recharge.dart';
import '../shared/brand_kit.dart';
import '../shared/celebration.dart';
import '../shared/onboarding_store.dart';

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
  // Custom Tabs, NO intent público: el magic link es canjeable por una sesión
  // completa. Ver `core/secure_web_launch.dart`.
  final ok = await launchAuthenticatedUrl(target);
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
  // Espejo del progreso REAL del hold (0→1): lo escribe el propio
  // AnimationController del botón y lo escucha la capa de la mascota que se
  // infla (pedido PO 2026-07-22) — un solo origen de verdad, cero timers
  // duplicados. A propósito SIN dispose: un dispose en el whenComplete del
  // sheet puede pisar un último tick del botón durante la salida (throw en
  // debug); sin listeners ni recursos, lo recoge el GC igual.
  // Carga perezosa del tutorial coach-mark (idempotente).
  unawaited(onboardingStore.ensureLoaded());
  final holdProgress = ValueNotifier<double>(0);
  showModalBottomSheet(
    sheetAnimationStyle: JayaloMotion.sheetRise,
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
            // La mascota vive EN LA COLUMNA, en el sitio exacto que ocupaba el
            // círculo del candado (ícono eliminado, PO 2026-07-30: el candado
            // sigue abajo en el botón, tenerlo dos veces era redundante).
            //
            // Antes se posicionaba sobre la hoja entera con un `Alignment`
            // proporcional, y eso la desalineaba según el alto del teléfono: la
            // columna mide siempre lo mismo en px, pero la hoja crece con la
            // pantalla. Acá queda clavada al hueco en cualquier device.
            //
            // 👉 EL TRUCO es el `OverflowBox`: la columna solo RESERVA 56px,
            // pero la mascota puede dibujarse mucho más grande sin que eso
            // cuente para el layout. Sin él, inflarse hasta 1.8× empujaría el
            // título, el costo y el botón hacia abajo — el botón se movería
            // bajo el dedo a media pulsación, que es justo lo que no puede
            // pasar en un hold. Con él, crece por encima del contenido igual
            // que antes.
            SizedBox(
              height: 56,
              child: needsRecharge
                  ? null
                  : Center(
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: double.infinity,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        // Caja de dibujo de la mascota + la onda del ¡PUM!
                        // (`_PumPainter` pinta 300×300 centrado).
                        child: SizedBox(
                          width: 300,
                          height: 300,
                          child: HoldMascotLayer(
                            progress: holdProgress,
                            // Centrada en SU caja: ya no hay que adivinar una
                            // proporción sobre la hoja.
                            alignment: Alignment.center,
                          ),
                        ),
                      ),
                    ),
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
              HoldCoachMark(
                gesture: 'unlock',
                message: 'Mantén presionado para desbloquear',
                tone: HoldToConfirmTone.paid,
                progress: holdProgress,
                child: HoldToConfirmButton(
                  // Copy + costo en el propio botón (pedido PO 2026-07-22).
                  label:
                      'Mantener para desbloquear · $cost crédito${cost == 1 ? '' : 's'}',
                  progress: holdProgress,
                  onConfirmed: () async {
                    // El cobro arranca YA (en paralelo) mientras la mascota hace
                    // su "¡PUM!" en la hoja — la animación no retrasa el acceso
                    // al contacto. `.then/.catchError` inmediatos para que un
                    // fallo del RPC durante la espera nunca quede sin oyente.
                    final unlocking = unlockOffer(offer['id'] as String, cost)
                        .then((r) => r.ok)
                        .catchError((_) => false);
                    if (!JayaloMotion.reduced(ctx)) {
                      await Future<void>.delayed(JayaloMotion.mascotPum);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    final ok = await unlocking;
                    if (!context.mounted) return;
                    if (ok) {
                      await onChanged?.call();
                      if (!context.mounted) return;
                      // UNA sola pantalla (pedido PO 2026-07-23): el botón
                      // grande de "¡Iniciar conversación!" vive DENTRO de la
                      // celebración violeta — sin hoja de contacto intermedia
                      // ni "marcar completada" (recién desbloqueó, no hay
                      // venta que marcar). La hoja de contacto sigue viva
                      // para los toques desde la lista de ofertas ya
                      // desbloqueadas.
                      await showUnlockCelebration(
                        context,
                        footer: (dismiss) => StartChatButton(
                          conversationKind: 'offer',
                          sourceId: offer['id'] as String,
                          dismiss: dismiss,
                          onOpen: (convId) {
                            if (context.mounted) {
                              context.push('/messages/$convId');
                            }
                          },
                        ),
                      );
                    } else {
                      _snack(context, 'No se pudo desbloquear. Intenta de nuevo.');
                    }
                  },
                ),
              ),
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
  // El chat SIEMPRE es la vía (pedido PO 2026-07-22: "todos los contactos
  // desbloqueados aparecen en el chat"); WhatsApp es el extra opcional.
  //
  // ⚠️ BUG arreglado 2026-07-23: se llamaba `get_unlocked_offer_contact`
  // (RPC de REVELAR WhatsApp: exige que el cliente tenga WhatsApp verificado y
  // MARCA `whatsapp_revealed_at`) para traer el contacto básico, y esa RPC
  // hace `RAISE EXCEPTION 'El cliente no tiene WhatsApp disponible…'` cuando el
  // cliente no tiene WhatsApp → el catch mostraba "No pudimos cargar el
  // contacto" AUNQUE hubiera internet. La web nunca cae en eso: gatea con
  // `can_reveal_offer_whatsapp` (bool) y solo llama la RPC de revelado al tocar
  // "ver WhatsApp". Aquí se hace igual: gatear PRIMERO, y solo entonces (si hay
  // WhatsApp) pedir el contacto — así jamás revienta y la hoja siempre abre.
  var canWhatsapp = false;
  try {
    canWhatsapp = await canRevealOffer(offer['id'] as String);
  } catch (_) {}
  ({String? firstName, String? phone}) contact = (firstName: null, phone: null);
  if (canWhatsapp) {
    try {
      contact = await unlockedContact(offer['id'] as String);
    } catch (_) {
      // Inesperado (el gate dijo que sí): cae a chat-only sin romper nada.
      canWhatsapp = false;
    }
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    sheetAnimationStyle: JayaloMotion.sheetRise,
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
            // "¿Se concretó la venta? Marcar completada" RETIRADO (pedido PO
            // 2026-07-23): el proveedor no marca la venta desde esta hoja.
          ]),
    ),
  );
}

/// El pill grande de la celebración de desbloqueo (pedido PO 2026-07-23):
/// "¡Iniciar conversación!" — blanco sobre el violeta, abre (o crea) la
/// conversación y navega directo al chat. Muestra spinner mientras el RPC
/// corre; si falla avisa y deja reintentar sin cerrar la celebración.
/// Público y parametrizado por [conversationKind] para reusarse tanto en el
/// desbloqueo de OFERTAS (`'offer'`) como en el de INTERESES de la tienda
/// (`'product_interest'`).
class StartChatButton extends StatefulWidget {
  const StartChatButton({
    super.key,
    required this.conversationKind,
    required this.sourceId,
    required this.dismiss,
    required this.onOpen,
  });

  /// Tipo de conversación para `getOrCreateConversation`.
  final String conversationKind;
  final String sourceId;

  /// Cierra la celebración (el `dismiss` del footer del overlay).
  final VoidCallback dismiss;

  /// Navega al chat — corre con el context de la PANTALLA (no el del overlay,
  /// que ya estará muerto tras [dismiss]).
  final void Function(String convId) onOpen;

  @override
  State<StartChatButton> createState() => _StartChatButtonState();
}

class _StartChatButtonState extends State<StartChatButton> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? convId;
    try {
      convId = await getOrCreateConversation(
          kind: widget.conversationKind, sourceId: widget.sourceId);
    } catch (_) {}
    if (!mounted) return;
    if (convId == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir el chat. Intenta de nuevo.')));
      return;
    }
    widget.dismiss();
    widget.onOpen(convId);
  }

  @override
  Widget build(BuildContext context) {
    final violet = Theme.of(context).colorScheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280),
      child: FilledButton.icon(
        onPressed: _busy ? null : _start,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: violet,
          disabledBackgroundColor: Colors.white.withValues(alpha: .85),
          minimumSize: const Size(280, 58),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        icon: _busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: violet),
              )
            : const Icon(Icons.forum_rounded),
        label: const Text('¡Iniciar conversación!'),
      ),
    );
  }
}

/// Hoja alta que sube casi al centro (pedido PO 2026-07-22): reserva una
/// fracción de la pantalla y centra su contenido, en vez de una franja pegada
/// al borde inferior. Suma el inset del sistema para no quedar tras el navbar.
///
/// Tenía un `overlay` para pintar la mascota del hold ENCIMA de todo el
/// contenido; se retiró el 2026-07-30 cuando la mascota se mudó a su sitio
/// dentro de la columna (ver `openUnlockSheet`), que la deja clavada al hueco
/// del candado en cualquier tamaño de pantalla.
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
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    // `Clip.none` (el default es `hardEdge`): la mascota vive
                    // DENTRO de esta columna, en el hueco del candado, y se
                    // dibuja mucho más grande que el hueco que reserva (ver el
                    // `OverflowBox` de `openUnlockSheet`). Con el recorte por
                    // defecto, inflarse le cortaba la cabeza contra el borde
                    // del área scrolleable, y la onda del ¡PUM! salía partida.
                    clipBehavior: Clip.none,
                    child: child,
                  ),
                ),
              ],
            ),
          ],
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
