import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';

ChatMessage msg(String id, String? sender, String kind, String createdAt) =>
    ChatMessage.fromRow({'id': id, 'sender_id': sender, 'kind': kind, 'body': 'x', 'created_at': createdAt});

void main() {
  group('parseQuick / answer', () {
    const body = '{"question":"¿Es nuevo o usado?","options":["Nuevo","Usado"],"selected":null,"answered_by":null}';
    test('parsea', () {
      final p = parseQuick(body)!;
      expect(p.question, '¿Es nuevo o usado?');
      expect(p.options, ['Nuevo', 'Usado']);
      expect(p.selected, isNull);
    });
    test('corrupto → null', () => expect(parseQuick('nope'), isNull));
    test('answerQuickBody marca selected y answered_by', () {
      final next = parseQuick(answerQuickBody(parseQuick(body)!, 'Nuevo', 'u1'))!;
      expect(next.selected, 'Nuevo');
      expect(next.answeredBy, 'u1');
    });
    test('confirmación mapeada (cliente pregunta, proveedor responde)', () =>
        expect(quickConfirmation('¿Es nuevo o usado?', 'Nuevo'), 'Es nuevo'));
    test('confirmación de providerReplies', () =>
        expect(quickConfirmation('¿Lo quiere nuevo o usado?', 'Usado'), 'Lo quiero usado'));
    test('sin mapeo → la opción tal cual', () =>
        expect(quickConfirmation('pregunta inventada', 'Foo'), 'Foo'));
  });
  group('sanitizeChatText', () {
    test('trim y control chars', () => expect(sanitizeChatText('  hola  '), 'hola'));
    test('cap a maxMessageLen (300 desde 2026-07-28)', () {
      expect(maxMessageLen, 300,
          reason: 'debe ir en paridad con MAX_MESSAGE_LEN de la web');
      expect(
          sanitizeChatText('a' * (maxMessageLen + 500)).length, maxMessageLen);
    });
  });
  group('sendFailureMessage', () {
    test('anti-flood: repite el texto del servidor, no el genérico', () {
      expect(
          sendFailureMessage(
              code: chatRateLimitCode,
              serverMessage:
                  'Vas muy rápido. Espera unos segundos antes de enviar otro mensaje.'),
          'Vas muy rápido. Espera unos segundos antes de enviar otro mensaje.');
    });
    test('tope de longitud: también se repite', () {
      expect(
          sendFailureMessage(
              code: chatCheckViolationCode,
              serverMessage: 'El mensaje supera los 300 caracteres.'),
          'El mensaje supera los 300 caracteres.');
    });
    test('otro error (RLS, red) → genérico, sin filtrar detalles internos', () {
      expect(sendFailureMessage(code: '42501', serverMessage: 'permission denied for table'),
          'No se pudo enviar. Intenta de nuevo.');
      expect(sendFailureMessage(), 'No se pudo enviar. Intenta de nuevo.');
    });
    test('nuestro código pero sin mensaje → genérico', () {
      expect(sendFailureMessage(code: chatRateLimitCode, serverMessage: '  '),
          'No se pudo enviar. Intenta de nuevo.');
    });

    /// Bug del PO (2026-07-31): el cron de inactividad cerró la conversación a
    /// las 72 h, el composer seguía pintado (no hay realtime sobre
    /// `conversations`), y el envío rebotaba contra la RLS con "intenta de
    /// nuevo" — mandando al usuario a golpear una puerta cerrada.
    test('chat cerrado: lo dice, en vez de invitar a reintentar', () {
      expect(
          sendFailureMessage(
              code: chatPermissionDeniedCode,
              serverMessage: 'new row violates row-level security policy',
              conversationClosed: true),
          'Esta conversación está cerrada: ya no se pueden enviar mensajes.');
    });
    test('rechazo por RLS pero la conversación SIGUE abierta → genérico', () {
      // La pantalla releé la conversación antes de decidir el texto. Si volvió
      // abierta, la causa fue otra y no podemos afirmar que está cerrada.
      expect(
          sendFailureMessage(
              code: chatPermissionDeniedCode, conversationClosed: false),
          'No se pudo enviar. Intenta de nuevo.');
    });
    test('el texto del servidor gana al aviso de cerrado', () {
      // Si una de NUESTRAS guardas explicó el rechazo, ese texto es más
      // específico que "está cerrada".
      expect(
          sendFailureMessage(
              code: chatRateLimitCode,
              serverMessage: 'Vas muy rápido.',
              conversationClosed: true),
          'Vas muy rápido.');
    });
  });
  group('isRenderableImageSrc', () {
    test('https ok', () => expect(isRenderableImageSrc('https://x.co/a.jpg'), isTrue));
    test('data ok', () => expect(isRenderableImageSrc('data:image/jpeg;base64,AAAA'), isTrue));
    test('javascript no', () => expect(isRenderableImageSrc('javascript:alert(1)'), isFalse));
  });
  test('buildGreeting reemplaza placeholders', () {
    final g = buildGreeting(
        '¡Hola, {first_name}! Gracias por elegir {business}. Confirmo que el acuerdo es: {product}{price}. Estoy listo para concretar la entrega.',
        firstName: 'Ana', business: 'El Corito', product: 'Nevera', priceTxt: ' por RD\$5,000');
    expect(g, '¡Hola, Ana! Gracias por elegir El Corito. Confirmo que el acuerdo es: Nevera por RD\$5,000. Estoy listo para concretar la entrega.');
  });
  group('needsAudit', () {
    final created = DateTime(2026, 7, 10);
    test('>72h abierto sin audit → true', () => expect(
        needsAudit(status: 'abierto', createdAt: created, hasAudit: false, now: DateTime(2026, 7, 17)), isTrue));
    test('<72h → false', () => expect(
        needsAudit(status: 'abierto', createdAt: created, hasAudit: false, now: DateTime(2026, 7, 11)), isFalse));
    test('ya tiene audit → false', () => expect(
        needsAudit(status: 'abierto', createdAt: created, hasAudit: true, now: DateTime(2026, 7, 17)), isFalse));
    test('cerrado → false', () => expect(
        needsAudit(status: 'cerrado', createdAt: created, hasAudit: false, now: DateTime(2026, 7, 17)), isFalse));
  });
  group('convIdFromMessageLink (gotcha #14, ambos formatos)', () {
    test('formato actual', () => expect(convIdFromMessageLink('/messages?c=abc-123'), 'abc-123'));
    test('formato legado', () => expect(convIdFromMessageLink('/messages/abc-123'), 'abc-123'));
    test('otro link → null', () => expect(convIdFromMessageLink('/requests/9'), isNull));
    test('null → null', () => expect(convIdFromMessageLink(null), isNull));
  });
  group('agrupación', () {
    final ms = [
      msg('1', 'a', 'text', '2026-07-16T10:00:00Z'),
      msg('2', 'a', 'text', '2026-07-17T10:00:00Z'),
      msg('3', 'a', 'text', '2026-07-17T10:01:00Z'),
      msg('4', 'b', 'text', '2026-07-17T10:02:00Z'),
      msg('5', null, 'system', '2026-07-17T10:03:00Z'),
    ];
    test('day sep en 0 y al cambiar de día', () {
      expect(needsDaySep(ms, 0), isTrue);
      expect(needsDaySep(ms, 1), isTrue);
      expect(needsDaySep(ms, 2), isFalse);
    });
    test('group end: cambio de sender, system y último', () {
      expect(isGroupEnd(ms, 2), isTrue); // 3 seguido de 4 (otro sender) → 2 ES fin de grupo
      // ojo: fin de grupo = el SIGUIENTE es de otro sender/día/system
      expect(isGroupEnd(ms, 1), isFalse);
      expect(isGroupEnd(ms, 3), isTrue); // siguiente es system
      expect(isGroupEnd(ms, 4), isTrue); // último
    });
  });
  test('quickReplies y providerReplies completos', () {
    expect(quickReplies.length, 8);
    expect(providerReplies.length, 6);
    expect(chatEmojis.length, 40);
  });
}
