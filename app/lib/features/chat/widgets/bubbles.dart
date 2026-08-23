import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/network_image.dart';
import '../../../domain/appointment.dart';
import '../../../domain/chat.dart';
import '../../../domain/chat_time.dart';
import '../../../domain/geo.dart';

/// Paleta del chat sobre el panel lila (doctrina mockups: el chat se reconoce
/// por su fondo lila pleno, con burbujas chicas sin sombra e ink oscuro). En
/// oscuro (pasada pendiente del PO) cae a un lila apagado legible.
({Color panel, Color own, Color peer, Color ink, Color sys, Color stamp})
chatPalette(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Fondo del chat ~50% más claro (pedido PO 2026-07-22: el lila pleno se
  // sentía oscuro/incómodo). Las burbujas se ajustan para conservar contraste.
  return dark
      ? (
          panel: const Color(0xFF3B3457),
          own: const Color(0xFF4A4270),
          peer: const Color(0xFF565080),
          ink: const Color(0xFFEDEAFB),
          sys: Colors.white.withValues(alpha: .12),
          stamp: const Color(0xFFCFC7EC),
        )
      : (
          panel: const Color(0xFFE4DBFB), // era 0xFFBFA9F5
          own: const Color(0xFFD3C4F7), // lavanda un poco más marcada
          peer: Colors.white, // burbuja del cliente = blanca, contrasta
          ink: const Color(0xFF4A4458),
          sys: Colors.white.withValues(alpha: .65),
          stamp: const Color(0xFFF6F1FF),
        );
}

Widget buildBubble(
  BuildContext context,
  ChatMessage m, {
  required bool own,
  required bool groupEnd,
  required String? peerAvatarUrl,
  required void Function(String src) onImageTap,
  required void Function(ChatMessage, String) onQuickAnswer,
  required bool canAnswerQuick,

  /// Acción tocada en una tarjeta de fecha pautada. `action` ∈ 'confirm' |
  /// 'cancel' | 'propose_again' | 'calendar'; las dos primeras van a la RPC
  /// `respond_scheduled_date`, las otras dos son LOCALES de la app (abrir la
  /// hoja de proponer / abrir Google Calendar).
  required void Function(AppointmentPayload, String) onAppointmentAction,

  /// ¿Quien mira es el PROVEEDOR de esta conversación? La tarjeta de
  /// seguimiento («¿se realizó?») la escribe el servidor con `sender_id` NULL,
  /// así que `own` es false para las DOS partes y es el único dato que
  /// distingue quién responde. Se pide ya (Task 5) para no cambiar la firma —
  /// y con ella todos los llamadores— otra vez en la Task 12.
  required bool isProvider,

  /// Conversación abierta: con ella cerrada no se pinta ninguna acción que
  /// escriba (el servidor las rechazaría con «Esta conversación está cerrada»).
  bool conversationOpen = true,

  /// URLs firmadas de las fotos guardadas en el bucket privado, indexadas por su
  /// marcador `chat-media:`. Vacío mientras la firma está en vuelo.
  Map<String, String> signedChatImages = const {},
}) {
  final cs = Theme.of(context).colorScheme;
  final pal = chatPalette(context);
  final timeStr = m.sendStatus == SendStatus.sending
      ? 'enviando…'
      : formatTimeHM(m.createdAt);

  if (isSystemKind(m.kind)) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: pal.sys,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          m.body,
          style: TextStyle(fontSize: 12, color: pal.ink.withValues(alpha: .9)),
        ),
      ),
    );
  }

  // La burbuja PROPIA (la del que habla) va en violeta pleno con letra BLANCA
  // (pedido PO 2026-07-22: antes era lavanda clara y se veía apagada); la del
  // peer sigue blanca con tinta oscura. Mismo criterio que la burbuja quick.
  final bubbleColor = own ? cs.primary : pal.peer;
  final bubbleInk = own ? Colors.white : pal.ink;
  final stampColor = own
      ? Colors.white.withValues(alpha: .7)
      : pal.ink.withValues(alpha: .55);

  Widget inner;
  if (m.kind == 'image') {
    // Las fotos del chat viajan como marcador `chat-media:{ruta}` (bucket
    // privado) y hay que firmarlas antes de pintarlas; las del compartir-
    // artículo siguen siendo URLs públicas y se usan tal cual.
    final marker = isChatMediaMarker(m.body);
    final src = marker ? signedChatImages[m.body] : m.body;
    if (marker && src == null) {
      // Mientras se firma se deja un hueco con su spinner. Antes esta rama
      // devolvía SizedBox.shrink() y la burbuja de toda foto enviada desde la
      // web DESAPARECÍA, aunque la lista de chats dijera "📷 Foto".
      inner = Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (src == null || !isRenderableImageSrc(src)) {
      return const SizedBox.shrink();
    } else {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
          onTap: () => onImageTap(src),
          child: JayaloNetworkImage(
            src,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 200,
              height: 120,
              color: cs.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    }
  } else if (m.kind == 'appointment') {
    // El body es JSON que escribe SOLO el servidor (RPCs de
    // `20260823071753_fecha_pautada_nucleo`): aquí se lee y se pinta, nunca se
    // escribe a mano. Una acción llama a la RPC y el propio servidor reescribe
    // el body; el repintado llega por el UPDATE de realtime.
    final a = parseAppointment(m.body);
    if (a == null) return const SizedBox.shrink();
    final apBg = own ? cs.primary : pal.peer;
    final apInk = own ? Colors.white : pal.ink;
    // Estados terminales: la tarjeta sigue ahí (es historia del trato) pero
    // baja de peso, como en la web.
    final spent = a.status == 'superseded' ||
        a.status == 'cancelled' ||
        a.status == 'expired';
    inner = Opacity(
      opacity: spent ? .7 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: apBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (own ? Colors.white : cs.primary).withValues(alpha: .35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.status == 'followup')
              // Task 12 enciende los botones «Sí / No» (y ahí entra
              // `isProvider`, que dice cuál de las dos partes contesta). Por
              // ahora solo la pregunta: un botón que no hace nada es peor que
              // su ausencia.
              Text(
                '¿Se realizó «${a.subject}»?',
                style: TextStyle(fontWeight: FontWeight.w600, color: apInk),
              )
            else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 15, color: apInk),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Fecha pautada para ${a.subject}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: apInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // SIEMPRE por el formateador: aplica el huso fijo de RD (UTC-4)
              // por dentro. Nunca corregir la zona aquí.
              Text(
                formatAppointmentDate(a.startsAtUtc),
                style: TextStyle(fontSize: 14.5, color: apInk),
              ),
              const SizedBox(height: 8),
              ..._appointmentActions(
                a,
                cs: cs,
                own: own,
                ink: apInk,
                open: conversationOpen,
                // El proponente solo se puede COTEJAR con quien mira a través
                // de `own`, que sale de `sender_id`. Si la tarjeta no tiene
                // remitente, el proponente es DESCONOCIDO: dar por hecho «no
                // es mía» le enseñaría «Confirmar» a las DOS partes y una se
                // comería el «La otra parte es quien confirma la fecha» del
                // servidor. Misma reja que `canRespond` en
                // `AppointmentBubble.tsx`.
                proposerKnown: m.senderId != null,
                onAction: onAppointmentAction,
              ),
            ],
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: own ? Colors.white.withValues(alpha: .7) : stampColor,
              ),
            ),
          ],
        ),
      ),
    );
  } else if (m.kind == 'quick') {
    final p = parseQuick(m.body);
    if (p == null) return const SizedBox.shrink();
    // Quick del PROVEEDOR (own): burbuja violeta + letras BLANCAS (pedido PO
    // 2026-07-22: sobre la lavanda clara la pregunta prediseñada se perdía).
    // El del cliente conserva la burbuja clara con tinta oscura.
    final quickBg = own ? cs.primary : bubbleColor;
    final quickInk = own ? Colors.white : pal.ink;
    inner = Container(
      padding: const EdgeInsets.all(10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: quickBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.question,
            style: TextStyle(fontWeight: FontWeight.w600, color: quickInk),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in p.options)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: quickInk.withValues(alpha: own ? .6 : .5),
                    ),
                    backgroundColor: p.selected == opt
                        ? (own ? Colors.white : cs.primary)
                        : Colors.transparent,
                    foregroundColor: p.selected == opt
                        ? (own ? cs.primary : Colors.white)
                        : quickInk,
                    // Al responder, el botón queda deshabilitado; sin estos
                    // colores de estado-disabled Material desvanece el texto al
                    // gris por defecto (onSurface .38) e IGNORA el foreground,
                    // así la opción elegida sobre el violeta se volvía
                    // ilegible (pedido PO 2026-07-22: letras BLANCAS en los
                    // selectores violeta). Mantenemos fondo+letra de la opción
                    // elegida; las no elegidas quedan tenues.
                    disabledBackgroundColor: p.selected == opt
                        ? (own ? Colors.white : cs.primary)
                        : Colors.transparent,
                    disabledForegroundColor: p.selected == opt
                        ? (own ? cs.primary : Colors.white)
                        : quickInk.withValues(alpha: .55),
                  ),
                  onPressed: (!own && canAnswerQuick && p.selected == null)
                      ? () => onQuickAnswer(m, opt)
                      : null,
                  child: Text(
                    '${p.selected == opt ? '✓ ' : ''}$opt',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (p.selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Respondido: ${p.selected}',
                style: TextStyle(
                  fontSize: 11,
                  color: quickInk.withValues(alpha: .7),
                ),
              ),
            ),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10,
              color: own ? Colors.white.withValues(alpha: .7) : stampColor,
            ),
          ),
        ],
      ),
    );
  } else {
    // text / address
    // Solo 'address' separa el enlace del mapa; el resto de los kinds sigue
    // pintando el cuerpo tal cual, sin tocar esa rama comun.
    final addressSplit = m.kind == 'address' ? splitMapLink(m.body) : null;
    inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
        border: m.kind == 'address'
            ? Border.all(
                color: (own ? Colors.white : cs.primary).withValues(alpha: 0.4),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.kind == 'address')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place_outlined, size: 14, color: bubbleInk),
                const SizedBox(width: 4),
                Text(
                  addressSplit?.mapUrl != null ? 'Ubicación' : 'Dirección',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: bubbleInk,
                  ),
                ),
              ],
            ),
          // +1pt (pedido PO 2026-07-22: mensajes del chat más grandes).
          Text(
            addressSplit?.text ?? m.body,
            style: TextStyle(fontSize: 14.5, color: bubbleInk),
          ),
          if (addressSplit?.mapUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => _openMapLink(context, addressSplit!.mapUrl!),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 15, color: bubbleInk),
                    const SizedBox(width: 4),
                    Text(
                      'Abrir en el mapa',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: bubbleInk,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(timeStr, style: TextStyle(fontSize: 10, color: stampColor)),
        ],
      ),
    );
  }

  final avatar = groupEnd && !own
      ? CircleAvatar(
          radius: 16,
          backgroundImage: peerAvatarUrl != null
              ? jayaloAvatarImage(peerAvatarUrl, 32, context)
              : null,
          child: peerAvatarUrl == null
              ? const Icon(Icons.person_outline, size: 16)
              : null,
        )
      : const SizedBox(width: 32);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: own
          ? [inner]
          : [avatar, const SizedBox(width: 6), Flexible(child: inner)],
    ),
  );
}

/// Botón de una tarjeta de fecha pautada, con los MISMOS colores de estado que
/// la rama `quick`: sin `disabledForegroundColor`/`disabledBackgroundColor`
/// explícitos, Material desvanece el texto a su gris por defecto (onSurface
/// .38) e IGNORA el foreground — sobre la burbuja violeta eso deja la acción
/// ilegible. Ya mordió antes en este proyecto, así que se fijan siempre aunque
/// hoy ningún botón de la tarjeta nazca deshabilitado.
Widget _apButton(
  String label, {
  required bool primary,
  required bool own,
  required Color ink,
  required ColorScheme cs,
  required VoidCallback onPressed,
  IconData? icon,
}) {
  final bg = primary
      ? (own ? Colors.white : cs.primary)
      : Colors.transparent;
  final fg = primary ? (own ? cs.primary : Colors.white) : ink;
  final style = OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    side: BorderSide(color: ink.withValues(alpha: own ? .6 : .5)),
    backgroundColor: bg,
    foregroundColor: fg,
    disabledBackgroundColor: bg,
    disabledForegroundColor: fg.withValues(alpha: .55),
  );
  final text = Text(label, style: const TextStyle(fontSize: 12));
  return icon == null
      ? OutlinedButton(style: style, onPressed: onPressed, child: text)
      : OutlinedButton.icon(
          style: style,
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: text,
        );
}

/// Los hijos de la tarjeta que dependen del estado. Lista (no un widget) para
/// que la columna de la burbuja siga controlando el espaciado.
List<Widget> _appointmentActions(
  AppointmentPayload a, {
  required ColorScheme cs,
  required bool own,
  required Color ink,
  required bool open,
  required bool proposerKnown,
  required void Function(AppointmentPayload, String) onAction,
}) {
  final noteStyle = TextStyle(fontSize: 11.5, color: ink.withValues(alpha: .7));
  Widget cancelLink(String label) => TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: ink.withValues(alpha: .85),
          disabledForegroundColor: ink.withValues(alpha: .55),
        ),
        onPressed: () => onAction(a, 'cancel'),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  switch (a.status) {
    case 'proposed':
      // `own` es lo que discrimina: quien propuso ESPERA, la otra parte
      // RESPONDE. (Cotejar `proposedBy` contra `senderId`, como pedía el
      // borrador de la tarea, siempre da true — el proponente ES el remitente.)
      if (own) {
        return [
          Text('Esperando respuesta…', style: noteStyle),
          if (open) cancelLink('Cancelar'),
        ];
      }
      if (!proposerKnown || !open) return const [];
      return [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _apButton('Confirmar',
                primary: true,
                own: own,
                ink: ink,
                cs: cs,
                onPressed: () => onAction(a, 'confirm')),
            _apButton('Proponer otra',
                primary: false,
                own: own,
                ink: ink,
                cs: cs,
                onPressed: () => onAction(a, 'propose_again')),
          ],
        ),
      ];
    case 'confirmed':
      return [
        Text('✅ Confirmada',
            style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
        const SizedBox(height: 6),
        _apButton('Añadir a Google Calendar',
            icon: Icons.calendar_month_outlined,
            primary: false,
            own: own,
            ink: ink,
            cs: cs,
            onPressed: () => onAction(a, 'calendar')),
        // Cancelar una fecha YA confirmada lo puede hacer cualquiera de las dos
        // partes (la RPC no mira quién propuso para 'cancel'), así que aquí no
        // aplica la reja del proponente desconocido.
        if (open) cancelLink('Cancelar la fecha'),
      ];
    case 'superseded':
      return [Text('Superada por una nueva propuesta', style: noteStyle)];
    case 'cancelled':
      return [Text('Cancelada', style: noteStyle)];
    case 'expired':
      return [Text('Expiró sin respuesta', style: noteStyle)];
    default:
      return const [];
  }
}

/// Abre el enlace del mapa en la app externa (o el navegador si no hay
/// ninguna instalada). `launchUrl` puede lanzar si nada sabe manejar el
/// enlace; lo capturamos para no dejar una excepcion sin atrapar en un
/// `onTap`, y avisamos con el mismo mecanismo (SnackBar) que usa el resto
/// del chat para sus errores.
Future<void> _openMapLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('No se pudo abrir el mapa')),
  );
}
