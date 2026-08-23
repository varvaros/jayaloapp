import 'package:flutter/material.dart';
import '../../../domain/chat.dart';
import '../quick_replies_store.dart';
import '../../shared/jayalo_loader.dart';
import '../../shared/onboarding_guide.dart';
import '../../shared/onboarding_copy.dart';
import '../../../core/motion.dart';

enum PlusAction {
  sendAddress,
  improveOffer,
  sendContact,
  sendLocation,
  sendCurrentLocation,
  sendPhoto,
  sendStoreItem,
  proposeDate,
}

/// Acciones del menu «+», por rol. Funcion pura y de nivel superior para poder
/// testearla (mismo patron que `chatMenuValues` en chat_screen.dart).
List<(PlusAction, IconData, String)> plusMenuItems({required bool isProvider}) =>
    isProvider
        ? const [
            // Foto del dispositivo + artículos de la tienda (pedido PO
            // 2026-07-21): el proveedor muestra su mercancía en el chat.
            (PlusAction.sendPhoto, Icons.add_photo_alternate_outlined, 'Enviar foto'),
            (PlusAction.sendStoreItem, Icons.storefront_outlined, 'De mi tienda'),
            (PlusAction.sendAddress, Icons.place_outlined, 'Enviar dirección del local'),
            // Coordinar la entrega/visita es lo que sigue a la dirección.
            (PlusAction.proposeDate, Icons.event_outlined, 'Fecha pautada'),
            (PlusAction.improveOffer, Icons.bolt_outlined, 'Mejorar oferta (bajar precio)'),
          ]
        : const [
            (PlusAction.sendContact, Icons.badge_outlined, 'Enviar mis datos de contacto'),
            // La ubicación del MOMENTO va primero: es el caso que motivó la
            // tanda (el cliente que no está en su casa).
            (PlusAction.sendCurrentLocation, Icons.my_location, 'Mi ubicación actual'),
            (PlusAction.proposeDate, Icons.event_outlined, 'Fecha pautada'),
            (PlusAction.sendLocation, Icons.place_outlined, 'Mi dirección guardada'),
            (PlusAction.sendPhoto, Icons.add_photo_alternate_outlined, 'Enviar foto'),
          ];

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.isProvider,
    required this.sending,
    required this.onSendText,
    required this.onPlusAction,
    required this.onQuickItem,
    this.onTyping,
  });
  final bool isProvider;
  final bool sending;
  final Future<bool> Function(String text) onSendText;
  final void Function(PlusAction) onPlusAction;
  final void Function(QuickItem) onQuickItem;

  /// Se llama en CADA pulsación del campo de texto. El composer no sabe (ni
  /// debe) cómo viaja el aviso ni cada cuánto: el throttle vive en la pantalla,
  /// junto al canal por donde se emite.
  final VoidCallback? onTyping;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Trae las respuestas rápidas personalizadas (si las hay) para cuando el
    // usuario abra la lista; hasta entonces sirven los defaults.
    quickRepliesStore.ensureLoaded();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final raw = _ctrl.text;
    if (sanitizeChatText(raw).isEmpty) return;
    _ctrl.clear();
    final ok = await widget.onSendText(raw);
    if (!ok && mounted) _ctrl.text = raw;
  }

  /// Guia del `+`, por rol: el menu no trae lo mismo para cada uno.
  String get _attachGuideKey => widget.isProvider
      ? 'chat.attach.provider.v1'
      : 'chat.attach.client.v1';

  void _openPlusMenu() {
    final items = plusMenuItems(isProvider: widget.isProvider);
    showModalBottomSheet<void>(
        sheetAnimationStyle: JayaloMotion.sheetMenu,
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (action, icon, label) in items)
                ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      widget.onPlusAction(action);
                    }),
            ])));
  }

  void _openEmojis() {
    showModalBottomSheet<void>(
        sheetAnimationStyle: JayaloMotion.sheetMenu,
        context: context,
        builder: (ctx) => SafeArea(
                child: GridView.count(
              crossAxisCount: 8,
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              children: [
                for (final e in chatEmojis)
                  InkWell(
                      onTap: () {
                        _ctrl.text += e;
                        Navigator.of(ctx).pop();
                      },
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 22)))),
              ],
            )));
  }

  void _openQuickList() {
    // Lista EFECTIVA del usuario (personalizada o defaults) para su rol en esta
    // conversación. Se reconstruye la hoja al vuelo: ya está cargada por
    // ensureLoaded en initState.
    final list = quickRepliesStore.forProvider(widget.isProvider);
    showModalBottomSheet<void>(
        sheetAnimationStyle: JayaloMotion.sheetMenu,
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Mensajes predeterminados',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
              for (final item in list)
                Card(
                    child: ListTile(
                  title: Text(item.question, style: const TextStyle(fontSize: 14)),
                  subtitle: item.options.isEmpty
                      ? null
                      : Wrap(spacing: 4, children: [
                          for (final o in item.options)
                            Chip(label: Text(o, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact),
                          Text('(responderá con botones)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ]),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onQuickItem(item);
                  },
                )),
            ])));
  }

  /// Boton de icono compacto para el interior de la pildora: sin el area de
  /// 48 px de `IconButton`, que en la barra de WhatsApp/Telegram partiria el
  /// alto del campo. 40 px sigue siendo blanco de toque valido.
  Widget _pillIcon(IconData icon, VoidCallback onTap, Color color,
      {String? tooltip}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: color,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    // El chat vive en un Scaffold ANIDADO dentro del shell, que conserva una
    // bottomNavigationBar animada aunque este oculta en la conversacion: en esa
    // combinacion el `padding.bottom` del MediaQuery del cuerpo puede quedar
    // recortado, asi que un `SafeArea` normal no repone el inset y el composer
    // quedaba "muy debajo", pegado a la barra de gestos (pedido PO 2026-07-21:
    // subirlo). Se usa el `viewPadding` CRUDO (que el Scaffold no recorta) mas
    // un respiro fijo; con el teclado abierto ese inset fisico ya no aplica
    // (el teclado ocupa esa zona) -> se colapsa para que el campo quede justo
    // encima del teclado sin hueco muerto.
    final mq = MediaQuery.of(context);
    final keyboardUp = mq.viewInsets.bottom > 0;
    final bottomGap = 8.0 + (keyboardUp ? 0.0 : mq.viewPadding.bottom);
    // Pildora unica al estilo WhatsApp/Telegram (referencia del PO
    // 2026-08-22): los accesorios viven DENTRO de la barra de mensaje —
    // emoji a la izquierda, adjuntos a la derecha — y solo el envio queda
    // fuera, como circulo de accion. Antes los tres iconos comian el ancho
    // por la izquierda y el campo de texto quedaba estrangulado.
    // Fondo BLANCO siempre (pedido PO 2026-08-22). Antes la pildora tomaba
    // `pal.peer`, que solo es blanco en claro: en OSCURO caia a un lila
    // apagado (#565080) y el PO la quiere blanca en los dos modos, como la
    // referencia de WhatsApp.
    //
    // Al fijar el fondo hay que fijar TAMBIEN la tinta: `pal.ink` en oscuro es
    // casi blanco (#EDEAFB), asi que el texto habria quedado invisible sobre
    // el blanco. Se usa el gris violaceo de la doctrina estetica, nunca negro.
    const pillColor = Colors.white;
    const pillInk = Color(0xFF4A4458);
    final iconColor = pillInk.withValues(alpha: .60);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 6, 8, bottomGap),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            key: const Key('chat.composer.pill'),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(26),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _pillIcon(Icons.emoji_emotions_outlined, _openEmojis, iconColor,
                  tooltip: 'Emojis'),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  // Borrar tambien cuenta como "estoy escribiendo": el usuario
                  // sigue trabajando en el mensaje. Por eso el aviso va en
                  // `onChanged` y no condicionado a que el texto crezca.
                  onChanged: (_) => widget.onTyping?.call(),
                  maxLines: 4,
                  minLines: 1,
                  maxLength: maxMessageLen,
                  style: const TextStyle(fontSize: 15, color: pillInk),
                  cursorColor: Theme.of(context).colorScheme.primary,
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      currentLength >= maxMessageLen * 0.8
                          ? Text('$currentLength/$maxLength',
                              style: const TextStyle(fontSize: 10))
                          : null,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje…',
                    hintStyle: TextStyle(fontSize: 15, color: iconColor),
                    isDense: true,
                    // ESTE era el gris que veia el PO. El tema global de la app
                    // trae `filled: true` + `fillColor: surfaceContainerHighest`
                    // ("F1 · Rellenos suaves"), asi que el TextField pintaba un
                    // rectangulo gris DENTRO de la pildora blanca. Quitar el
                    // borde no basta: hay que apagar el relleno para que se vea
                    // el blanco de la pildora. Pasa en claro y en oscuro.
                    filled: false,
                    // Sin marco: el marco ahora es la pildora que envuelve
                    // campo + iconos.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                  ),
                ),
              ),
              OnboardingGuide(
                guideKey: 'chat.quick_replies.v1',
                steps: onboardingCopy['chat.quick_replies.v1']!,
                order: 2,
                // Burbuja con rayo = respuestas rapidas. NO `auto_awesome`: las
                // chispitas son el icono universal de IA y este boton abre
                // mensajes preguardados, no una IA.
                child: _pillIcon(
                    Icons.quickreply_outlined, _openQuickList, iconColor,
                    tooltip: 'Mensajes predeterminados'),
              ),
              OnboardingGuide(
                guideKey: _attachGuideKey,
                steps: onboardingCopy[_attachGuideKey]!,
                order: 4,
                child: _pillIcon(Icons.add, _openPlusMenu, iconColor,
                    tooltip: 'Adjuntar'),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filled(
            onPressed: widget.sending ? null : _send,
            icon: widget.sending
                ? const JayaloSpinner(size: 16)
                : const Icon(Icons.send)),
      ]),
    );
  }
}
