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
  group('appointmentFailureMessage', () {
    const generico = 'No se pudo proponer la fecha. Intenta de nuevo.';

    test('P0001 de nuestras RPCs: se repite tal cual (ya viene en español)',
        () {
      expect(
          appointmentFailureMessage(
              code: chatRaiseExceptionCode,
              serverMessage: 'La fecha debe ser futura',
              fallback: generico),
          'La fecha debe ser futura');
    });

    test('JY429: la tarjeta consume el anti-flood y su aviso también sirve',
        () {
      expect(
          appointmentFailureMessage(
              code: chatRateLimitCode,
              serverMessage: 'Vas muy rápido. Espera unos segundos antes de '
                  'enviar otro mensaje.',
              fallback: generico),
          'Vas muy rápido. Espera unos segundos antes de enviar otro mensaje.');
    });

    test('PGRST202 (APK antes que la migración) NO enseña sus tripas', () {
      // El caso realista: la función todavía no existe en el esquema. El texto
      // del servidor es inglés y lleva nombres internos dentro.
      expect(
          appointmentFailureMessage(
              code: 'PGRST202',
              serverMessage:
                  'Could not find the function public.propose_scheduled_date'
                  '(_conversation_id, _starts_at, _subject) in the schema cache',
              fallback: generico),
          generico);
    });

    test('42501, sin código o con mensaje vacío → genérico', () {
      expect(
          appointmentFailureMessage(
              code: '42501',
              serverMessage: 'permission denied for table',
              fallback: generico),
          generico);
      expect(appointmentFailureMessage(fallback: generico), generico);
      expect(
          appointmentFailureMessage(
              code: chatRaiseExceptionCode,
              serverMessage: '   ',
              fallback: generico),
          generico);
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
    /// Minor #7 de la revisión final: nada fijaba el DISPARADOR de la
    /// relectura. El camino completo (`_send` → 42501 → `_reload` → `!_isOpen`
    /// → aviso) vive en `ChatScreen`, que no se puede montar en un
    /// widget-test porque su `initState` toca Supabase; lo que sí se puede
    /// fijar es la decisión, que es donde estaría el error.
    test('solo un rechazo de la RLS dispara releer la conversación', () {
      expect(shouldRecheckConversation(chatPermissionDeniedCode), isTrue);
      // El anti-flood y el tope de longitud NO deben provocar una relectura:
      // la conversación sigue abierta y el servidor ya explicó el rechazo.
      expect(shouldRecheckConversation(chatRateLimitCode), isFalse);
      expect(shouldRecheckConversation(chatCheckViolationCode), isFalse);
      // Un fallo de red no trae código: tampoco.
      expect(shouldRecheckConversation(null), isFalse);
      expect(shouldRecheckConversation('23505'), isFalse);
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
    test('el marcador del bucket privado NO es pintable directo: se firma antes',
        () => expect(isRenderableImageSrc('chat-media:abc/1-2-chat.jpg'), isFalse));
  });
  group('sanitizeChatText corta por runas', () {
    test('no parte el emoji que cae en el límite', () {
      final out = sanitizeChatText('${'a' * 299}👍');
      expect(out.runes.length, 300);
      expect(out.endsWith('👍'), isTrue);
    });
    test('conserva emojis y quita caracteres de control', () {
      expect(sanitizeChatText('hola 👋'), 'hola 👋');
      expect(sanitizeChatText('mal\x00\x07texto'), 'maltexto');
    });
  });
  group('marcador chat-media', () {
    test('reconoce el marcador que escribe la web', () {
      expect(isChatMediaMarker('chat-media:abc/1-2-chat.jpg'), isTrue);
    });
    test('una URL pública NO es marcador (compartir-artículo sigue directo)', () {
      expect(isChatMediaMarker('https://x.co/a.jpg'), isFalse);
      expect(isChatMediaMarker('data:image/jpeg;base64,AAAA'), isFalse);
    });
    test('extrae la ruta, que empieza por el id de conversación (lo exige la RLS)', () {
      expect(chatMediaPath('chat-media:abc/1-2-chat.jpg'), 'abc/1-2-chat.jpg');
    });
    test('sobre algo que no es marcador devuelve el valor tal cual', () {
      expect(chatMediaPath('https://x.co/a.jpg'), 'https://x.co/a.jpg');
    });
  });
  test('buildGreeting reemplaza placeholders', () {
    final g = buildGreeting(
        '¡Hola, {first_name}! Gracias por elegir {business}. Confirmo que el acuerdo es: {product}{price}. Estoy listo para concretar la entrega.',
        firstName: 'Ana', business: 'El Corito', product: 'Nevera', priceTxt: ' por RD\$5,000');
    expect(g, '¡Hola, Ana! Gracias por elegir El Corito. Confirmo que el acuerdo es: Nevera por RD\$5,000. Estoy listo para concretar la entrega.');
  });
  // Los 4 tests de `needsAudit` se fueron con la función el 2026-08-28. Estaban
  // en verde mientras la funcionalidad llevaba un mes rota: probaban la
  // aritmética de las 72 h, no que el insert que disparaban llegara a la BD.
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
