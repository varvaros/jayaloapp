import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';
import 'package:jayalo_app/features/chat/widgets/bubbles.dart';

/// Cuerpo tal cual lo escribe `propose_scheduled_date` (el `sender_id` del
/// mensaje ES el proponente).
String _body(String status, {String subject = 'la entrega'}) =>
    '{"appointment_id":"a1","subject":"$subject",'
    '"starts_at":"2026-08-26T19:00:00Z","status":"$status",'
    '"proposed_by":"u1"}';

ChatMessage _msg(String body, {String? senderId = 'u1'}) => ChatMessage(
      id: 'm1',
      senderId: senderId,
      kind: 'appointment',
      body: body,
      createdAtRaw: '2026-08-23T12:00:00Z',
    );

/// Cuerpo de una tarjeta de SEGUIMIENTO tal cual la escribe el servidor: sin
/// `sender_id` (va en `_msg` con `senderId: null`), y con `done_customer` /
/// `done_provider` solo cuando ese lado ya contestó.
String _followupBody({bool? doneCustomer, bool? doneProvider}) {
  final extra = StringBuffer();
  if (doneCustomer != null) extra.write(',"done_customer":$doneCustomer');
  if (doneProvider != null) extra.write(',"done_provider":$doneProvider');
  return '{"appointment_id":"a1","subject":"la entrega",'
      '"starts_at":"2026-08-26T19:00:00Z","status":"followup"$extra}';
}

void main() {
  late List<(String, String)> acciones;

  /// Deja la acción EN VUELO hasta que el test la complete, que es como se
  /// comporta una RPC de verdad. Null = se resuelve al instante.
  Completer<void>? enVuelo;

  setUp(() {
    acciones = [];
    enVuelo = null;
  });

  // En `flutter test` el texto mide ~2× lo que mide en el device: con la
  // superficie por defecto (800×600) la tarjeta se desborda y el test muere en
  // el overflow en vez de en la aserción.
  Widget host(
    ChatMessage m, {
    required bool own,
    bool conversationOpen = true,
    bool isProvider = false,
  }) =>
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 2000)),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => buildBubble(
                ctx,
                m,
                own: own,
                groupEnd: true,
                peerAvatarUrl: null,
                onImageTap: (_) {},
                onQuickAnswer: (_, _) {},
                canAnswerQuick: false,
                isProvider: isProvider,
                conversationOpen: conversationOpen,
                onAppointmentAction: (a, action) async {
                  acciones.add((a.appointmentId, action));
                  if (enVuelo != null) await enVuelo!.future;
                },
              ),
            ),
          ),
        ),
      );

  // ⚠️ Anclas de LA TARJETA (falso-verde documentado en este proyecto: un test
  // midió una tarjeta distinta de la que cambiaba). El encabezado lleva el
  // asunto y los botones se buscan por su tipo + su texto.
  final tarjeta = find.text('Fecha pautada para la entrega');
  final confirmar = find.widgetWithText(OutlinedButton, 'Confirmar');
  final proponerOtra = find.widgetWithText(OutlinedButton, 'Proponer otra');
  final calendario =
      find.widgetWithText(OutlinedButton, 'Añadir a Google Calendar');

  testWidgets('propuesta ajena en chat abierto: Confirmar y Proponer otra',
      (t) async {
    await t.pumpWidget(host(_msg(_body('proposed')), own: false));
    expect(tarjeta, findsOneWidget);
    // La hora sale SIEMPRE en RD (UTC-4): 19:00Z = 3:00 p. m.
    expect(find.text('26 ago, 3:00 p. m.'), findsOneWidget);
    expect(confirmar, findsOneWidget);
    expect(proponerOtra, findsOneWidget);
    expect(find.text('Esperando respuesta…'), findsNothing);

    await t.tap(confirmar);
    await t.pump();
    expect(acciones, [('a1', 'confirm')]);

    await t.tap(proponerOtra);
    await t.pump();
    expect(acciones.last, ('a1', 'propose_again'));
  });

  testWidgets('propuesta PROPIA: esperando respuesta, sin Confirmar',
      (t) async {
    await t.pumpWidget(host(_msg(_body('proposed')), own: true));
    expect(tarjeta, findsOneWidget);
    expect(find.text('Esperando respuesta…'), findsOneWidget);
    expect(confirmar, findsNothing);
    expect(proponerOtra, findsNothing);
    // Quien propuso sí puede retirarla mientras el chat esté abierto.
    await t.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await t.pump();
    expect(acciones, [('a1', 'cancel')]);
  });

  testWidgets('confirmada: sello + añadir al calendario', (t) async {
    await t.pumpWidget(host(_msg(_body('confirmed')), own: false));
    expect(find.text('✅ Confirmada'), findsOneWidget);
    expect(calendario, findsOneWidget);
    expect(confirmar, findsNothing);

    await t.tap(calendario);
    await t.pump();
    expect(acciones, [('a1', 'calendar')]);
  });

  testWidgets('superada: solo el aviso, cero botones', (t) async {
    await t.pumpWidget(host(_msg(_body('superseded')), own: false));
    expect(tarjeta, findsOneWidget);
    expect(find.text('Superada por una nueva propuesta'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('cancelada y expirada dicen lo suyo, sin acciones', (t) async {
    await t.pumpWidget(host(_msg(_body('cancelled')), own: true));
    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);

    await t.pumpWidget(host(_msg(_body('expired')), own: true));
    expect(find.text('Expiró sin respuesta'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('chat CERRADO: la tarjeta se ve, las acciones que escriben no',
      (t) async {
    await t.pumpWidget(
        host(_msg(_body('proposed')), own: false, conversationOpen: false));
    expect(tarjeta, findsOneWidget);
    expect(confirmar, findsNothing);
    expect(proponerOtra, findsNothing);

    await t.pumpWidget(
        host(_msg(_body('proposed')), own: true, conversationOpen: false));
    expect(find.text('Esperando respuesta…'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancelar'), findsNothing);

    await t.pumpWidget(
        host(_msg(_body('confirmed')), own: false, conversationOpen: false));
    // El calendario NO escribe nada en el servidor: sigue disponible.
    expect(calendario, findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancelar la fecha'), findsNothing);
  });

  testWidgets('proponente DESCONOCIDO (sin remitente): ningún botón de decidir',
      (t) async {
    // Sin `sender_id` no hay forma de cotejar quién propuso: pintar «Confirmar»
    // se lo enseñaría a las DOS partes y una se comería el rechazo del
    // servidor.
    await t.pumpWidget(
        host(_msg(_body('proposed'), senderId: null), own: false));
    expect(tarjeta, findsOneWidget);
    expect(confirmar, findsNothing);
    expect(proponerOtra, findsNothing);
  });

  group('seguimiento («¿Se realizó?»)', () {
    // La tarjeta la escribe el servidor con `sender_id` NULL: `own` es
    // SIEMPRE false para las dos partes, y `isProvider` es lo único que
    // distingue quién contesta — nunca `senderId: null` en estos helpers.
    final si = find.widgetWithText(OutlinedButton, 'Sí');
    final no = find.widgetWithText(OutlinedButton, 'No');

    testWidgets('mi lado SIN responder: botones Sí/No, sin respuesta de nadie',
        (t) async {
      await t.pumpWidget(host(
        _msg(_followupBody(), senderId: null),
        own: false,
        isProvider: true,
      ));
      expect(find.text('¿Se realizó «la entrega»?'), findsOneWidget);
      // Misma fecha que el resto de la tarjeta (RD, UTC-4): con varias
      // propuestas en la conversación el asunto solo no basta para saber a
      // cuál responde el seguimiento.
      expect(find.text('26 ago, 3:00 p. m.'), findsOneWidget);
      expect(tarjeta, findsNothing);
      expect(si, findsOneWidget);
      expect(no, findsOneWidget);
      expect(find.textContaining('Tu respuesta'), findsNothing);
      expect(find.textContaining('respondió'), findsNothing);

      await t.tap(si);
      await t.pump();
      expect(acciones, [('a1', 'done_yes')]);
    });

    testWidgets('tocar «No» dispara done_no', (t) async {
      await t.pumpWidget(host(
        _msg(_followupBody(), senderId: null),
        own: false,
        isProvider: true,
      ));
      await t.tap(no);
      await t.pump();
      expect(acciones, [('a1', 'done_no')]);
    });

    testWidgets('mi lado YA respondió Sí: texto, sin botones', (t) async {
      await t.pumpWidget(host(
        _msg(_followupBody(doneProvider: true), senderId: null),
        own: false,
        isProvider: true,
      ));
      expect(find.text('Tu respuesta: Sí'), findsOneWidget);
      expect(si, findsNothing);
      expect(no, findsNothing);
    });

    testWidgets('mi lado YA respondió No: texto, sin botones', (t) async {
      await t.pumpWidget(host(
        _msg(_followupBody(doneProvider: false), senderId: null),
        own: false,
        isProvider: true,
      ));
      expect(find.text('Tu respuesta: No'), findsOneWidget);
      expect(si, findsNothing);
      expect(no, findsNothing);
    });

    testWidgets(
        'la respuesta de la OTRA parte solo se ve una vez que la dio',
        (t) async {
      // El proveedor mira: el cliente YA respondió Sí, el proveedor no.
      await t.pumpWidget(host(
        _msg(_followupBody(doneCustomer: true), senderId: null),
        own: false,
        isProvider: true,
      ));
      expect(si, findsOneWidget, reason: 'mi lado (proveedor) sigue en botones');
      expect(no, findsOneWidget);
      expect(find.text('La otra parte: Sí'), findsOneWidget);
    });

    testWidgets(
        'isProvider determina "mi lado" — NO own (que es false para las dos '
        'partes): la MISMA tarjeta se pinta distinto para cada rol',
        (t) async {
      // Mismo payload que arriba (cliente respondió Sí, proveedor no), pero
      // ahora quien mira es el CLIENTE (isProvider:false): su propio lado ya
      // respondió → texto, no botones; y el proveedor (la OTRA parte para él)
      // aún no ha contestado → nada que mostrar de "la otra parte".
      // Si las ramas own/other estuvieran cambiadas de sitio, este caso
      // pintaría botones (leyendo done_provider como "mi lado") en vez del
      // texto correcto, y este test lo detecta.
      await t.pumpWidget(host(
        _msg(_followupBody(doneCustomer: true), senderId: null),
        own: false,
        isProvider: false,
      ));
      expect(find.text('Tu respuesta: Sí'), findsOneWidget);
      expect(si, findsNothing);
      expect(no, findsNothing);
      // El proveedor (la otra parte para el cliente) NO ha respondido: nada
      // que mostrar de él.
      expect(find.textContaining('La otra parte'), findsNothing);
    });

    testWidgets(
        'chat CERRADO: los botones de responder SIGUEN — asimetría a '
        'propósito con confirmar/cancelar (la RPC no exige conversación '
        'abierta)', (t) async {
      await t.pumpWidget(host(
        _msg(_followupBody(), senderId: null),
        own: false,
        isProvider: true,
        conversationOpen: false,
      ));
      expect(si, findsOneWidget);
      expect(no, findsOneWidget);
    });

    testWidgets('doble toque: «Sí» no se dispara dos veces (mismo candado)',
        (t) async {
      final gate = Completer<void>();
      enVuelo = gate;
      await t.pumpWidget(host(
        _msg(_followupBody(), senderId: null),
        own: false,
        isProvider: true,
      ));

      await t.tap(si);
      await t.pump();
      expect(acciones, [('a1', 'done_yes')]);
      expect(t.widget<OutlinedButton>(si).onPressed, isNull);
      expect(t.widget<OutlinedButton>(no).onPressed, isNull);

      await t.tap(si, warnIfMissed: false);
      await t.pump();
      expect(acciones, [('a1', 'done_yes')]);

      gate.complete();
      await t.pumpAndSettle();
      expect(t.widget<OutlinedButton>(si).onPressed, isNotNull);
    });
  });

  testWidgets('doble toque: la acción NO se dispara dos veces', (t) async {
    // Sin candado, el segundo toque vuelve a llamar a `respond_scheduled_date`
    // y el usuario ve «Esta propuesta ya no está activa» DESPUÉS de una acción
    // que sí funcionó. La web ya tenía este `busy`.
    final gate = Completer<void>();
    enVuelo = gate;
    await t.pumpWidget(host(_msg(_body('proposed')), own: false));

    await t.tap(confirmar);
    await t.pump();
    expect(acciones, [('a1', 'confirm')]);
    // Mientras la RPC está en vuelo, los dos botones quedan apagados.
    expect(t.widget<OutlinedButton>(confirmar).onPressed, isNull);
    expect(t.widget<OutlinedButton>(proponerOtra).onPressed, isNull);

    await t.tap(confirmar, warnIfMissed: false);
    await t.pump();
    expect(acciones, [('a1', 'confirm')]);

    gate.complete();
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(confirmar).onPressed, isNotNull);
  });

  testWidgets('el candado también apaga «Cancelar la fecha» en vuelo',
      (t) async {
    final gate = Completer<void>();
    enVuelo = gate;
    await t.pumpWidget(host(_msg(_body('confirmed')), own: false));
    final cancelar = find.widgetWithText(TextButton, 'Cancelar la fecha');

    await t.tap(cancelar);
    await t.pump();
    expect(acciones, [('a1', 'cancel')]);
    expect(t.widget<TextButton>(cancelar).onPressed, isNull);
    expect(t.widget<OutlinedButton>(calendario).onPressed, isNull);

    await t.tap(cancelar, warnIfMissed: false);
    await t.pump();
    expect(acciones, [('a1', 'cancel')]);

    gate.complete();
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(cancelar).onPressed, isNotNull);
  });

  testWidgets('body roto: no se pinta nada', (t) async {
    await t.pumpWidget(host(_msg('{no soy json'), own: false));
    expect(tarjeta, findsNothing);
    expect(find.byType(Container), findsNothing);
    expect(acciones, isEmpty);
  });
}
