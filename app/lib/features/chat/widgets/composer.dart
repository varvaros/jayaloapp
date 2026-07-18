import 'package:flutter/material.dart';
import '../../../domain/chat.dart';
import '../../shared/jayalo_loader.dart';

enum PlusAction { sendAddress, improveOffer, sendContact, sendLocation, sendPhoto }

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.isProvider,
    required this.sending,
    required this.onSendText,
    required this.onPlusAction,
    required this.onQuickItem,
  });
  final bool isProvider;
  final bool sending;
  final Future<bool> Function(String text) onSendText;
  final void Function(PlusAction) onPlusAction;
  final void Function(QuickItem) onQuickItem;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _ctrl = TextEditingController();

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
            (PlusAction.sendAddress, Icons.place_outlined, 'Enviar dirección del local'),
            (PlusAction.improveOffer, Icons.bolt_outlined, 'Mejorar oferta (bajar precio)'),
          ]
        : const [
            (PlusAction.sendContact, Icons.badge_outlined, 'Enviar mis datos de contacto'),
            (PlusAction.sendLocation, Icons.place_outlined, 'Enviar mi ubicación'),
            (PlusAction.sendPhoto, Icons.add_photo_alternate_outlined, 'Enviar foto'),
          ];
    showModalBottomSheet<void>(
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
    final list = widget.isProvider ? providerReplies : quickReplies;
    showModalBottomSheet<void>(
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
    return SafeArea(
        child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(onPressed: _openPlusMenu, icon: const Icon(Icons.add)),
        IconButton(onPressed: _openEmojis, icon: const Icon(Icons.emoji_emotions_outlined)),
        IconButton(onPressed: _openQuickList, icon: const Icon(Icons.auto_awesome_outlined)),
        Expanded(
          child: TextField(
            controller: _ctrl,
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
    ));
  }
}
