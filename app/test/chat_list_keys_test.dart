import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/appointment.dart';
import 'package:jayalo_app/domain/chat.dart';
import 'package:jayalo_app/features/chat/widgets/bubbles.dart';

/// ⚠️ Esto NO prueba `ChatScreen`: su `initState` toca Supabase y la pantalla no
/// se puede montar en un widget-test (limitación conocida del repo). Lo que
/// reproduce es el MECANISMO: una `ListView.builder` INVERTIDA con la misma
/// forma de `itemBuilder` que la pantalla —incluida la rama que envuelve la
/// burbuja en un `Column` cuando toca separador de día— y las MISMAS dos
/// funciones compartidas donde vive la identidad: `keyedChatItem` (la clave) y
/// `chatItemIndexForKey` (el `findChildIndexCallback`, sin el cual la clave no
/// conserva nada). Si alguien toca cualquiera de las dos, esta prueba cae.
///
/// Que la PANTALLA use esas dos funciones se lee en su código
/// (`chat_screen.dart`, la `ListView.builder` de los mensajes); esta prueba no
/// lo ejecuta.
class _ListaDeMensajes extends StatefulWidget {
  const _ListaDeMensajes({required this.iniciales, required this.onAction});

  final List<ChatMessage> iniciales;
  final Future<void> Function(AppointmentPayload, String) onAction;

  @override
  State<_ListaDeMensajes> createState() => _ListaDeMensajesState();
}

class _ListaDeMensajesState extends State<_ListaDeMensajes> {
  late final List<ChatMessage> _ms = [...widget.iniciales];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ElevatedButton(
        // Un mensaje NUEVO entra por abajo (índice 0 de la lista invertida) y
        // corre TODOS los índices de los que ya estaban.
        onPressed: () => setState(() => _ms.add(ChatMessage(
              id: 'm3',
              senderId: 'u1',
              kind: 'text',
              body: 'llegué',
              // Otro día a propósito: así ese ítem se pinta con la rama del
              // separador (un `Column` alrededor de la burbuja) y la secuencia
              // de tipos de la lista queda irregular, que es otra manera de que
              // el emparejamiento por posición caiga mal.
              createdAtRaw: '2026-08-24T12:00:00Z',
            ))),
        child: const Text('llega un mensaje'),
      ),
      Expanded(
        child: ListView.builder(
          reverse: true,
          itemCount: _ms.length,
          // La MISMA pareja que usa la pantalla: la clave por si sola no
          // conserva el estado en una lista perezosa (ver chatItemIndexForKey).
          findChildIndexCallback: (key) => chatItemIndexForKey(key, _ms,
              peerTyping: false, loadingOlder: false),
          itemBuilder: (context, j) {
            final i = _ms.length - 1 - j;
            final m = _ms[i];
            final bubble = buildBubble(context, m,
                own: false,
                groupEnd: isGroupEnd(_ms, i),
                peerAvatarUrl: null,
                onImageTap: (_) {},
                onQuickAnswer: (_, _) {},
                canAnswerQuick: false,
                onAppointmentAction: widget.onAction,
                isProvider: false,
                conversationOpen: true);
            if (!needsDaySep(_ms, i)) return keyedChatItem(m, bubble);
            return keyedChatItem(
                m,
                Column(children: [
                  const Center(child: Text('— día —')),
                  bubble,
                ]));
          },
        ),
      ),
    ]);
  }
}

ChatMessage _cita(String id, String apptId, String asunto) => ChatMessage(
      id: id,
      senderId: 'u1',
      kind: 'appointment',
      body: '{"appointment_id":"$apptId","subject":"$asunto",'
          '"starts_at":"2026-08-26T19:00:00Z","status":"proposed",'
          '"proposed_by":"u1"}',
      createdAtRaw: '2026-08-23T12:00:00Z',
    );

void main() {
  /// Botón «Confirmar» de la tarjeta de ESE asunto, localizado SIN usar la
  /// clave: si la identidad se pierde y el estado se muda de tarjeta, esta
  /// búsqueda lo ve (una búsqueda por clave, en cambio, solo diría que la clave
  /// no está).
  Finder confirmarDe(String asunto) => find.descendant(
        of: find
            .ancestor(
                of: find.text('Fecha pautada para $asunto'),
                matching: find.byType(Column))
            .first,
        matching: find.widgetWithText(OutlinedButton, 'Confirmar'),
      );

  testWidgets(
      'un mensaje nuevo corre los índices y el «en vuelo» se queda en SU tarjeta',
      (t) async {
    final acciones = <String>[];
    final gate = Completer<void>();
    // Dos tarjetas de fecha pautada vivas a la vez: es lo normal, cada
    // propuesta superada deja la suya en el historial.
    final ms = [
      _cita('m1', 'a1', 'la entrega'),
      _cita('m2', 'a2', 'la instalación'),
    ];

    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 2000)),
      child: MaterialApp(
        home: Scaffold(
          body: _ListaDeMensajes(
            iniciales: ms,
            onAction: (a, action) async {
              acciones.add('${a.appointmentId}/$action');
              await gate.future;
            },
          ),
        ),
      ),
    ));

    // Cada ítem lleva la identidad de SU mensaje.
    expect(find.byKey(const ValueKey('m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('m2')), findsOneWidget);

    await t.tap(confirmarDe('la entrega'));
    await t.pump();
    expect(acciones, ['a1/confirm']);
    expect(t.widget<OutlinedButton>(confirmarDe('la entrega')).onPressed,
        isNull);
    expect(t.widget<OutlinedButton>(confirmarDe('la instalación')).onPressed,
        isNotNull);

    // ── Llega un mensaje mientras la RPC sigue en vuelo ──────────────────
    await t.tap(find.text('llega un mensaje'));
    await t.pump();
    expect(find.text('llegué'), findsOneWidget);

    // El candado sigue donde estaba: en «la entrega», no en la tarjeta de al
    // lado. Sin clave estable, el estado se muda con el corrimiento de índices
    // y esta pareja de aserciones se invierte.
    expect(t.widget<OutlinedButton>(confirmarDe('la entrega')).onPressed,
        isNull);
    expect(t.widget<OutlinedButton>(confirmarDe('la instalación')).onPressed,
        isNotNull);
    expect(acciones, ['a1/confirm']);

    gate.complete();
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(confirmarDe('la entrega')).onPressed,
        isNotNull);
  });

  group('chatItemIndexForKey', () {
    final ms = [
      _cita('m1', 'a1', 'la entrega'), // el más VIEJO
      _cita('m2', 'a2', 'la instalación'),
      _cita('m3', 'a3', 'la revisión'), // el más NUEVO
    ];

    int? indice(Key k, {bool peerTyping = false, bool loadingOlder = false}) =>
        chatItemIndexForKey(k, ms,
            peerTyping: peerTyping, loadingOlder: loadingOlder);

    test('la lista va INVERTIDA: el más nuevo es el 0', () {
      expect(indice(const ValueKey('m3')), 0);
      expect(indice(const ValueKey('m2')), 1);
      expect(indice(const ValueKey('m1')), 2);
    });

    test('el indicador de escritura ocupa el 0 y corre todo lo demás uno', () {
      expect(indice(chatTypingKey, peerTyping: true), 0);
      expect(indice(const ValueKey('m3'), peerTyping: true), 1);
      expect(indice(const ValueKey('m1'), peerTyping: true), 3);
      // Si no está escribiendo, su clave ya no corresponde a ningún índice.
      expect(indice(chatTypingKey), isNull);
    });

    test('el spinner de «más viejos» va al final, detrás de los mensajes', () {
      expect(indice(chatLoadingOlderKey, loadingOlder: true), 3);
      expect(indice(chatLoadingOlderKey, loadingOlder: true, peerTyping: true),
          4);
      expect(indice(chatLoadingOlderKey), isNull);
    });

    test('un mensaje que ya no está, o una clave de otro tipo → null', () {
      // Devolver un índice inventado sería peor que null: el sliver mudaría el
      // estado a un mensaje que no es.
      expect(indice(const ValueKey('borrado')), isNull);
      expect(indice(const ValueKey(7)), isNull);
      expect(indice(const Key('otra cosa')), isNull);
    });
  });
}
