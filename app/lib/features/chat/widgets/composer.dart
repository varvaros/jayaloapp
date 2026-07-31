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
  sendPhoto,
  sendStoreItem,
}

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

  void _openPlusMenu() {
    final items = widget.isProvider
        ? const [
            // Foto del dispositivo + artículos de la tienda (pedido PO
            // 2026-07-21): el proveedor muestra su mercancía en el chat.
            (PlusAction.sendPhoto, Icons.add_photo_alternate_outlined, 'Enviar foto'),
            (PlusAction.sendStoreItem, Icons.storefront_outlined, 'De mi tienda'),
            (PlusAction.sendAddress, Icons.place_outlined, 'Enviar dirección del local'),
            (PlusAction.improveOffer, Icons.bolt_outlined, 'Mejorar oferta (bajar precio)'),
          ]
        : const [
            (PlusAction.sendContact, Icons.badge_outlined, 'Enviar mis datos de contacto'),
            (PlusAction.sendLocation, Icons.place_outlined, 'Enviar mi ubicación'),
            (PlusAction.sendPhoto, Icons.add_photo_alternate_outlined, 'Enviar foto'),
          ];
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

  @override
  Widget build(BuildContext context) {
    // El chat vive en un Scaffold ANIDADO dentro del shell, que conserva una
    // bottomNavigationBar animada aunque esté oculta en la conversación: en esa
    // combinación el `padding.bottom` del MediaQuery del cuerpo puede quedar
    // recortado, así que un `SafeArea` normal no repone el inset y el composer
    // quedaba "muy debajo", pegado a la barra de gestos (pedido PO 2026-07-21:
    // subirlo). Se usa el `viewPadding` CRUDO (que el Scaffold no recorta) más
    // un respiro fijo; con el teclado abierto ese inset físico ya no aplica
    // (el teclado ocupa esa zona) → se colapsa para que el campo quede justo
    // encima del teclado sin hueco muerto.
    final mq = MediaQuery.of(context);
    final keyboardUp = mq.viewInsets.bottom > 0;
    final bottomGap = 8.0 + (keyboardUp ? 0.0 : mq.viewPadding.bottom);
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 8, bottomGap),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(onPressed: _openPlusMenu, icon: const Icon(Icons.add)),
        IconButton(onPressed: _openEmojis, icon: const Icon(Icons.emoji_emotions_outlined)),
        OnboardingGuide(
          guideKey: 'chat.quick_replies.v1',
          steps: onboardingCopy['chat.quick_replies.v1']!,
          order: 2,
          child: IconButton(
              onPressed: _openQuickList,
              icon: const Icon(Icons.auto_awesome_outlined)),
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            // Borrar también cuenta como "estoy escribiendo": el usuario sigue
            // trabajando en el mensaje. Por eso el aviso va en `onChanged` y no
            // condicionado a que el texto crezca.
            onChanged: (_) => widget.onTyping?.call(),
            maxLines: 4,
            minLines: 1,
            maxLength: maxMessageLen,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                currentLength >= maxMessageLen * 0.8
                    ? Text('$currentLength/$maxLength', style: const TextStyle(fontSize: 10))
                    : null,
            decoration: const InputDecoration(
                hintText: 'Escribe un mensaje…',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)))),
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
