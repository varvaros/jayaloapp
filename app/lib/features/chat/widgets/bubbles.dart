import 'package:flutter/material.dart';
import '../../../domain/chat.dart';
import '../../../domain/chat_time.dart';

Widget buildBubble(BuildContext context, ChatMessage m,
    {required bool own,
    required bool groupEnd,
    required String? peerAvatarUrl,
    required void Function(String src) onImageTap,
    required void Function(ChatMessage, String) onQuickAnswer,
    required bool canAnswerQuick}) {
  final cs = Theme.of(context).colorScheme;
  final timeStr = m.sendStatus == SendStatus.sending ? 'enviando…' : formatTimeHM(m.createdAt);

  if (isSystemKind(m.kind)) {
    return Center(
        child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Text(m.body, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ));
  }

  Widget inner;
  if (m.kind == 'image') {
    if (!isRenderableImageSrc(m.body)) return const SizedBox.shrink();
    inner = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        onTap: () => onImageTap(m.body),
        child: Image.network(m.body,
            width: 220, height: 220, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
                width: 220, height: 120,
                color: cs.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined))),
      ),
    );
  } else if (m.kind == 'quick') {
    final p = parseQuick(m.body);
    if (p == null) return const SizedBox.shrink();
    inner = Container(
      padding: const EdgeInsets.all(10),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      decoration: BoxDecoration(
          color: own ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(p.question,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: own ? cs.onPrimary : cs.onSurface)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final opt in p.options)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: p.selected == opt
                      ? (own ? cs.onPrimary : cs.primary)
                      : Colors.transparent,
                  foregroundColor: p.selected == opt
                      ? (own ? cs.primary : cs.onPrimary)
                      : (own ? cs.onPrimary : cs.primary)),
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
                      color: own ? cs.onPrimary.withValues(alpha: 0.8) : cs.onSurfaceVariant))),
        Text(timeStr,
            style: TextStyle(
                fontSize: 10,
                color: own ? cs.onPrimary.withValues(alpha: 0.7) : cs.onSurfaceVariant)),
      ]),
    );
  } else {
    // text / address
    inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      decoration: BoxDecoration(
        color: own ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: m.kind == 'address'
            ? Border.all(color: cs.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m.kind == 'address')
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.place_outlined, size: 14, color: own ? cs.onPrimary : cs.primary),
            const SizedBox(width: 4),
            Text('Dirección',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: own ? cs.onPrimary : cs.onSurface)),
          ]),
        Text(m.body, style: TextStyle(fontSize: 14, color: own ? cs.onPrimary : cs.onSurface)),
        Text(timeStr,
            style: TextStyle(
                fontSize: 10,
                color: own ? cs.onPrimary.withValues(alpha: 0.7) : cs.onSurfaceVariant)),
      ]),
    );
  }

  final avatar = groupEnd && !own
      ? CircleAvatar(
          radius: 16,
          backgroundImage: peerAvatarUrl != null ? NetworkImage(peerAvatarUrl) : null,
          child: peerAvatarUrl == null ? const Icon(Icons.person_outline, size: 16) : null)
      : const SizedBox(width: 32);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: own ? [inner] : [avatar, const SizedBox(width: 6), Flexible(child: inner)],
    ),
  );
}
