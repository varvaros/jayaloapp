import 'package:flutter/material.dart';
import '../../../domain/chat.dart';
import '../../../domain/chat_time.dart';

/// Paleta del chat sobre el panel lila (doctrina mockups: el chat se reconoce
/// por su fondo lila pleno, con burbujas chicas sin sombra e ink oscuro). En
/// oscuro (pasada pendiente del PO) cae a un lila apagado legible.
({
  Color panel,
  Color own,
  Color peer,
  Color ink,
  Color sys,
  Color stamp,
}) chatPalette(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (
          panel: const Color(0xFF2A2440),
          own: const Color(0xFF3E3660),
          peer: const Color(0xFF4A4370),
          ink: const Color(0xFFEDEAFB),
          sys: Colors.white.withValues(alpha: .10),
          stamp: const Color(0xFFCFC7EC),
        )
      : (
          panel: const Color(0xFFBFA9F5),
          own: const Color(0xFFDCD0FA),
          peer: const Color(0xFFF2EDFE),
          ink: const Color(0xFF4A4458),
          sys: Colors.white.withValues(alpha: .55),
          stamp: const Color(0xFFF0E9FF),
        );
}

Widget buildBubble(BuildContext context, ChatMessage m,
    {required bool own,
    required bool groupEnd,
    required String? peerAvatarUrl,
    required void Function(String src) onImageTap,
    required void Function(ChatMessage, String) onQuickAnswer,
    required bool canAnswerQuick}) {
  final cs = Theme.of(context).colorScheme;
  final pal = chatPalette(context);
  final timeStr =
      m.sendStatus == SendStatus.sending ? 'enviando…' : formatTimeHM(m.createdAt);

  if (isSystemKind(m.kind)) {
    return Center(
        child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: pal.sys, borderRadius: BorderRadius.circular(999)),
      child: Text(m.body,
          style: TextStyle(
              fontSize: 12, color: pal.ink.withValues(alpha: .9))),
    ));
  }

  final bubbleColor = own ? pal.own : pal.peer;
  final stampColor = pal.ink.withValues(alpha: .55);

  Widget inner;
  if (m.kind == 'image') {
    if (!isRenderableImageSrc(m.body)) return const SizedBox.shrink();
    inner = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        onTap: () => onImageTap(m.body),
        child: Image.network(m.body,
            width: 200, height: 200, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
                width: 200, height: 120,
                color: cs.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined))),
      ),
    );
  } else if (m.kind == 'quick') {
    final p = parseQuick(m.body);
    if (p == null) return const SizedBox.shrink();
    inner = Container(
      padding: const EdgeInsets.all(10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      decoration: BoxDecoration(
          color: bubbleColor, borderRadius: BorderRadius.circular(14)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.question,
                style: TextStyle(fontWeight: FontWeight.w600, color: pal.ink)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final opt in p.options)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cs.primary.withValues(alpha: .5)),
                      backgroundColor: p.selected == opt
                          ? cs.primary
                          : Colors.transparent,
                      foregroundColor:
                          p.selected == opt ? cs.onPrimary : cs.primary),
                  onPressed: (!own && canAnswerQuick && p.selected == null)
                      ? () => onQuickAnswer(m, opt)
                      : null,
                  child: Text('${p.selected == opt ? '✓ ' : ''}$opt',
                      style: const TextStyle(fontSize: 12)),
                ),
            ]),
            if (p.selected != null)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Respondido: ${p.selected}',
                      style: TextStyle(
                          fontSize: 11,
                          color: pal.ink.withValues(alpha: .7)))),
            Text(timeStr, style: TextStyle(fontSize: 10, color: stampColor)),
          ]),
    );
  } else {
    // text / address
    inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
        border: m.kind == 'address'
            ? Border.all(color: cs.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.kind == 'address')
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.place_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text('Dirección',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pal.ink)),
              ]),
            Text(m.body, style: TextStyle(fontSize: 13.5, color: pal.ink)),
            Text(timeStr, style: TextStyle(fontSize: 10, color: stampColor)),
          ]),
    );
  }

  final avatar = groupEnd && !own
      ? CircleAvatar(
          radius: 16,
          backgroundImage:
              peerAvatarUrl != null ? NetworkImage(peerAvatarUrl) : null,
          child: peerAvatarUrl == null
              ? const Icon(Icons.person_outline, size: 16)
              : null)
      : const SizedBox(width: 32);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children:
          own ? [inner] : [avatar, const SizedBox(width: 6), Flexible(child: inner)],
    ),
  );
}
