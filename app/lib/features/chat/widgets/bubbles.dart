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

/// Identidad ESTABLE de un ítem de la lista de mensajes.
///
/// Sin esto, Flutter empareja el estado de los elementos por POSICIÓN y tipo. La
/// lista del chat va invertida y cada mensaje nuevo entra por el índice 0, así
/// que TODOS los índices se corren uno: si en ese momento una tarjeta de fecha
/// pautada tiene su RPC en vuelo, su `_busy` puede aterrizar en OTRA tarjeta del
/// mismo tipo (y una conversación acumula varias: cada propuesta superada deja
/// la suya). El síntoma sería una tarjeta que no acepta toques, en un mensaje
/// que el usuario ni tocó. La rama con separador de día envuelve la burbuja en
/// un `Column`, lo que además vuelve irregular la secuencia de tipos — otra
/// forma de que el emparejamiento caiga mal.
///
/// Va sobre el ítem COMPLETO (con separador o sin él) para que las dos formas
/// lleven la misma identidad, y la clave es el ID DEL MENSAJE: el índice es
/// justo lo que se mueve.
///
/// Función compartida a propósito: la usan `ChatScreen` y
/// `test/chat_list_keys_test.dart`, que reproduce la lista invertida con sus
/// índices corriéndose.
Widget keyedChatItem(ChatMessage m, Widget item) =>
    KeyedSubtree(key: ValueKey(m.id), child: item);

/// Clave del indicador de «está escribiendo» (entra y sale por el índice 0).
const Key chatTypingKey = Key('chat.typing');

/// Clave del spinner de «cargando más viejos» (aparece al final de la lista).
const Key chatLoadingOlderKey = Key('chat.loadingOlder');

/// Índice ACTUAL del ítem que lleva [key] — el `findChildIndexCallback` de la
/// lista de mensajes.
///
/// ⚠️ La clave SOLA no basta, y esto se midió: en una lista perezosa el sliver
/// guarda sus hijos POR ÍNDICE. Cuando los índices se corren, reconstruye el
/// hijo de ese índice y, como la clave ya no coincide con la del elemento que
/// estaba ahí, lo TIRA y crea uno nuevo: el estado (`_busy` de la tarjeta de
/// fecha pautada) se pierde igual que sin clave. `findChildIndexCallback` es lo
/// que le dice al sliver DÓNDE está ahora el elemento que ya tenía, y solo
/// entonces la identidad de [keyedChatItem] sirve de algo.
///
/// La lista va INVERTIDA: j = 0 es el mensaje más nuevo. Y el indicador de
/// escritura ocupa el 0 cuando está, corriendo todo lo demás uno.
int? chatItemIndexForKey(
  Key key,
  List<ChatMessage> ms, {
  required bool peerTyping,
  required bool loadingOlder,
}) {
  final offset = peerTyping ? 1 : 0;
  if (key == chatTypingKey) return peerTyping ? 0 : null;
  if (key == chatLoadingOlderKey) {
    return loadingOlder ? ms.length + offset : null;
  }
  if (key is! ValueKey<String>) return null;
  final i = ms.indexWhere((m) => m.id == key.value);
  // Un mensaje que ya no está (se recargó la página) devuelve null: el sliver
  // lo da por ido y construye uno nuevo, que es exactamente lo correcto.
  return i < 0 ? null : (ms.length - 1 - i) + offset;
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
  ///
  /// Devuelve un `Future` a propósito: la tarjeta apaga sus botones hasta que
  /// se cumple, y así un doble toque no dispara la acción dos veces.
  required Future<void> Function(AppointmentPayload, String)
      onAppointmentAction,

  /// ¿Quien mira es el PROVEEDOR de esta conversación? La tarjeta de
  /// seguimiento («¿se realizó?») la escribe el servidor con `sender_id` NULL,
  /// así que `own` es false para las DOS partes y es el único dato que
  /// distingue quién responde: `isProvider` decide cuál de `doneCustomer` /
  /// `doneProvider` es «mi lado» y cuál es «la otra parte» — nunca `own`.
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
    inner = _AppointmentCard(
      appointment: a,
      own: own,
      open: conversationOpen,
      // El proponente solo se puede COTEJAR con quien mira a través de `own`,
      // que sale de `sender_id`. Si la tarjeta no tiene remitente, el
      // proponente es DESCONOCIDO: dar por hecho «no es mía» le enseñaría
      // «Confirmar» a las DOS partes y una se comería el «La otra parte es
      // quien confirma la fecha» del servidor. Misma reja que `canRespond` en
      // `AppointmentBubble.tsx`.
      proposerKnown: m.senderId != null,
      isProvider: isProvider,
      onAction: onAppointmentAction,
      timeStr: timeStr,
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

/// Tarjeta de «fecha pautada» (mensaje `kind='appointment'`).
///
/// Es la ÚNICA burbuja con estado propio, y por una razón: mientras la RPC está
/// en vuelo hay que apagar sus botones. Sin eso, un segundo toque en «Confirmar»
/// dispara `respond_scheduled_date` otra vez y el usuario acaba viendo «Esta
/// propuesta ya no está activa» DESPUÉS de una acción que sí funcionó. La web
/// tiene ese candado (`busy` en `AppointmentBubble.tsx`) y sin él las dos
/// plataformas se comportan distinto.
///
/// Se resolvió con un `StatefulWidget` local y no con un conjunto de ids «en
/// vuelo» en `ChatScreen`: la pantalla ya es enorme, cada `setState` suyo
/// repinta la lista entera de mensajes, y el candado no le importa a nadie más
/// que a esta tarjeta.
class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.own,
    required this.open,
    required this.proposerKnown,
    required this.isProvider,
    required this.onAction,
    required this.timeStr,
  });

  final AppointmentPayload appointment;
  final bool own;
  final bool open;
  final bool proposerKnown;

  /// Cuál de las dos partes contesta el seguimiento («¿se realizó?», esa
  /// tarjeta llega con `sender_id` NULL así que `own` no sirve para esto).
  final bool isProvider;
  final Future<void> Function(AppointmentPayload, String) onAction;
  final String timeStr;

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _busy = false;

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAction(widget.appointment, action);
    } finally {
      // Al confirmar/cancelar, el servidor reescribe el body y el UPDATE de
      // realtime repinta ESTA misma tarjeta (mismo State), así que soltar el
      // candado aquí es lo correcto: ni se queda pegado ni se pierde el
      // repintado.
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Botón de la tarjeta, con los MISMOS colores de estado que la rama `quick`:
  /// sin `disabledForegroundColor`/`disabledBackgroundColor` explícitos,
  /// Material desvanece el texto a su gris por defecto (onSurface .38) e IGNORA
  /// el foreground — sobre la burbuja violeta eso dejaría la acción ilegible
  /// justo mientras está en vuelo. Ya mordió antes en este proyecto.
  Widget _apButton(
    String label, {
    required bool primary,
    required Color ink,
    required ColorScheme cs,
    required String action,
    IconData? icon,
  }) {
    final own = widget.own;
    final bg = primary ? (own ? Colors.white : cs.primary) : Colors.transparent;
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
    final onPressed = _busy ? null : () => _run(action);
    return icon == null
        ? OutlinedButton(style: style, onPressed: onPressed, child: text)
        : OutlinedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 15),
            label: text,
          );
  }

  /// Los hijos que dependen del estado de la fecha. Lista (no un widget) para
  /// que la columna de la tarjeta siga controlando el espaciado.
  List<Widget> _actions(ColorScheme cs, Color ink) {
    final a = widget.appointment;
    final open = widget.open;
    final noteStyle =
        TextStyle(fontSize: 11.5, color: ink.withValues(alpha: .7));
    Widget cancelLink(String label) => TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: ink.withValues(alpha: .85),
            disabledForegroundColor: ink.withValues(alpha: .55),
          ),
          onPressed: _busy ? null : () => _run('cancel'),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        );

    switch (a.status) {
      case 'proposed':
        // `own` es lo que discrimina: quien propuso ESPERA, la otra parte
        // RESPONDE. (Cotejar `proposedBy` contra `senderId`, como pedía el
        // borrador de la tarea, siempre da true — el proponente ES el
        // remitente.)
        if (widget.own) {
          return [
            Text('Esperando respuesta…', style: noteStyle),
            if (open) cancelLink('Cancelar'),
          ];
        }
        if (!widget.proposerKnown || !open) return const [];
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _apButton('Confirmar',
                  primary: true, ink: ink, cs: cs, action: 'confirm'),
              _apButton('Proponer otra',
                  primary: false, ink: ink, cs: cs, action: 'propose_again'),
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
              ink: ink,
              cs: cs,
              action: 'calendar'),
          // Cancelar una fecha YA confirmada lo puede hacer cualquiera de las
          // dos partes (la RPC no mira quién propuso para 'cancel'), así que
          // aquí no aplica la reja del proponente desconocido.
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

  /// Hijos de la tarjeta de SEGUIMIENTO («¿Se realizó?»). A diferencia de
  /// [_actions] arriba, NUNCA mira `widget.open`: la RPC
  /// `answer_scheduled_followup` deliberadamente no exige la conversación
  /// abierta (la señal de si el trato se cumplió no debe perderse solo porque
  /// nadie volvió a escribir tras concluirlo), así que imponer esa reja aquí
  /// reintroduciría justo la restricción que el servidor quitó a propósito —
  /// asimetría deliberada con confirmar/cancelar.
  ///
  /// `isProvider` decide «mi lado» (`doneProvider` si soy proveedor,
  /// `doneCustomer` si soy cliente) y «la otra parte» (al revés) — NUNCA
  /// `own`, que aquí es siempre `false` para las dos partes. Un «no» se
  /// REGISTRA, no se escala: sin disputa, sin cambio de estado, sin aviso a
  /// la otra parte — el texto no debe sugerir lo contrario.
  ///
  /// Mismo copy que el espejo web (`AppointmentBubble.tsx` +
  /// `followupView` en `src/lib/appointmentFollowup.ts`): «Tu respuesta:
  /// Sí/No» y «La otra parte: Sí/No» — genérico a propósito, no nombra
  /// «cliente»/«proveedor» para no sonar a acusación.
  List<Widget> _followupActions(ColorScheme cs, Color ink) {
    final a = widget.appointment;
    final myAnswer = widget.isProvider ? a.doneProvider : a.doneCustomer;
    final otherAnswer = widget.isProvider ? a.doneCustomer : a.doneProvider;
    final noteStyle =
        TextStyle(fontSize: 11.5, color: ink.withValues(alpha: .7));
    return [
      if (myAnswer == null)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _apButton('Sí',
                primary: true, ink: ink, cs: cs, action: 'done_yes'),
            _apButton('No',
                primary: false, ink: ink, cs: cs, action: 'done_no'),
          ],
        )
      else
        Text('Tu respuesta: ${myAnswer ? 'Sí' : 'No'}', style: noteStyle),
      if (otherAnswer != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'La otra parte: ${otherAnswer ? 'Sí' : 'No'}',
            style: noteStyle,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pal = chatPalette(context);
    final a = widget.appointment;
    final own = widget.own;
    final ink = own ? Colors.white : pal.ink;
    // Estados terminales: la tarjeta sigue ahí (es historia del trato) pero
    // baja de peso, como en la web.
    final spent = a.status == 'superseded' ||
        a.status == 'cancelled' ||
        a.status == 'expired';
    return Opacity(
      opacity: spent ? .7 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: own ? cs.primary : pal.peer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (own ? Colors.white : cs.primary).withValues(alpha: .35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.status == 'followup') ...[
              Text(
                '¿Se realizó «${a.subject}»?',
                style: TextStyle(fontWeight: FontWeight.w600, color: ink),
              ),
              const SizedBox(height: 4),
              // Misma fecha que el resto de la tarjeta (espejo web): con
              // varias propuestas en la misma conversación, el asunto solo
              // no basta para saber a CUÁL de ellas responde el seguimiento.
              Text(
                formatAppointmentDate(a.startsAtUtc),
                style: TextStyle(fontSize: 14.5, color: ink),
              ),
              const SizedBox(height: 8),
              ..._followupActions(cs, ink),
            ] else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 15, color: ink),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Fecha pautada para ${a.subject}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // SIEMPRE por el formateador: aplica el huso fijo de RD (UTC-4)
              // por dentro. Nunca corregir la zona aquí.
              Text(
                formatAppointmentDate(a.startsAtUtc),
                style: TextStyle(fontSize: 14.5, color: ink),
              ),
              const SizedBox(height: 8),
              ..._actions(cs, ink),
            ],
            Text(
              widget.timeStr,
              style: TextStyle(
                fontSize: 10,
                color: own
                    ? Colors.white.withValues(alpha: .7)
                    : pal.ink.withValues(alpha: .55),
              ),
            ),
          ],
        ),
      ),
    );
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
