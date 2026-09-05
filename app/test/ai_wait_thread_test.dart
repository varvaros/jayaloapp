import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_wait_steps.dart';
import 'package:jayalo_app/features/client/widgets/ai_wait_thread.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('pinta los pasos del contexto y ningún aviso al principio', (t) async {
    final st = aiWaitState(
        contexto: AiWaitContext.primerEnvio,
        primerMensaje: 'nevera samsung',
        elapsedMs: 0,
        yaReportado: false);
    await t.pumpWidget(_app(AiWaitThread(state: st, reduced: true)));
    expect(find.text('Ok… déjame ver esto…'), findsOneWidget);
    expect(find.text('Ya veo, déjame ver más cerca «nevera samsung»'), findsOneWidget);
    expect(find.text('Ya casi…'), findsOneWidget);
    expect(find.text(kAiWaitAviso1Titulo), findsNothing);
    expect(find.text(kAiWaitAviso2Titulo), findsNothing);
  });

  testWidgets('el paso hecho lleva check y el activo lleva el punto', (t) async {
    final st = aiWaitState(
        contexto: AiWaitContext.respondiendo,
        primerMensaje: '',
        elapsedMs: 1500,
        yaReportado: false);
    await t.pumpWidget(_app(AiWaitThread(state: st, reduced: true)));
    expect(find.byKey(const ValueKey('ai-wait-hecho-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-wait-activo-1')), findsOneWidget);
  });

  testWidgets('a los 12 s aparece el aviso 1; a los 30 s lo sustituye el 2', (t) async {
    AiWaitState a(int ms) => aiWaitState(
        contexto: AiWaitContext.armando,
        primerMensaje: '',
        elapsedMs: ms,
        yaReportado: false);
    await t.pumpWidget(_app(AiWaitThread(state: a(12000), reduced: true)));
    expect(find.textContaining(kAiWaitAviso1Titulo), findsOneWidget);
    await t.pumpWidget(_app(AiWaitThread(state: a(30000), reduced: true)));
    expect(find.textContaining(kAiWaitAviso1Titulo), findsNothing);
    expect(find.textContaining(kAiWaitAviso2Titulo), findsOneWidget);
    expect(find.textContaining(kAiWaitAviso2Texto), findsOneWidget);
  });

  testWidgets('con reduced=false el pulso anima sin colgar el test', (t) async {
    final st = aiWaitState(
        contexto: AiWaitContext.respondiendo,
        primerMensaje: '',
        elapsedMs: 0,
        yaReportado: false);
    await t.pumpWidget(_app(AiWaitThread(state: st, reduced: false)));
    await t.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('ai-wait-activo-0')), findsOneWidget);
  });
}
