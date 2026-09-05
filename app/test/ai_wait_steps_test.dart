import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/ai_wait_steps.dart';

void main() {
  AiWaitState st(AiWaitContext c, int ms,
          {String primer = 'nevera samsung', bool yaReportado = false}) =>
      aiWaitState(
          contexto: c, primerMensaje: primer, elapsedMs: ms, yaReportado: yaReportado);

  List<AiWaitStepState> estados(AiWaitState s) => s.pasos.map((p) => p.estado).toList();

  group('textos por contexto (copy exacto de la spec §4)', () {
    test('primer envío con texto: tres pasos y el recorte entre comillas', () {
      final s = st(AiWaitContext.primerEnvio, 0);
      expect(s.pasos.map((p) => p.texto).toList(), [
        'Ok… déjame ver esto…',
        'Ya veo, déjame ver más cerca «nevera samsung»',
        'Ya casi…',
      ]);
    });
    test('primer envío solo con foto: «esa foto»', () {
      final s = st(AiWaitContext.primerEnvio, 0, primer: 'Esto es lo que busco.');
      expect(s.pasos[1].texto, 'Ya veo, déjame ver más cerca esa foto');
    });
    test('respondiendo: dos pasos', () {
      final s = st(AiWaitContext.respondiendo, 0);
      expect(s.pasos.map((p) => p.texto).toList(), [
        'Anotando eso en mi libreta de detective',
        'Buscando qué más preguntarte sin caer pesado',
      ]);
    });
    test('armando: tres pasos', () {
      final s = st(AiWaitContext.armando, 0);
      expect(s.pasos.map((p) => p.texto).toList(), [
        'Pasando tu solicitud en limpio',
        'Olfateando el rubro correcto',
        'Reclutando a los proveedores que sí saben de esto',
      ]);
    });
  });

  group('recorte del primer mensaje', () {
    test('30 o menos caracteres, tal cual', () {
      expect(aiWaitRecorte('nevera samsung'), 'nevera samsung');
      expect(aiWaitRecorte('a' * 30), 'a' * 30);
    });
    test('más de 30: corta en el último espacio y añade …', () {
      expect(aiWaitRecorte('nevera samsung de dos puertas no frost 12 pies'),
          'nevera samsung de dos puertas…');
    });
    test('más de 30 sin espacios: corta a 30 y añade …', () {
      expect(aiWaitRecorte('a' * 40), '${'a' * 30}…');
    });
    test('recorta los espacios de los bordes antes de medir', () {
      expect(aiWaitRecorte('  nevera  '), 'nevera');
    });
  });

  group('estados por tiempo (tres pasos)', () {
    const c = AiWaitContext.primerEnvio;
    test('a 0 ms: el primero activo, el resto pendiente', () {
      expect(estados(st(c, 0)),
          [AiWaitStepState.activo, AiWaitStepState.pendiente, AiWaitStepState.pendiente]);
    });
    test('a 1499 ms sigue igual; a 1500 el primero hecho y el segundo activo', () {
      expect(estados(st(c, 1499))[0], AiWaitStepState.activo);
      expect(estados(st(c, 1500)),
          [AiWaitStepState.hecho, AiWaitStepState.activo, AiWaitStepState.pendiente]);
    });
    test('a 3000 ms: dos hechos y el último activo; sigue activo a los 40 s', () {
      expect(estados(st(c, 3000)),
          [AiWaitStepState.hecho, AiWaitStepState.hecho, AiWaitStepState.activo]);
      expect(estados(st(c, 40000)),
          [AiWaitStepState.hecho, AiWaitStepState.hecho, AiWaitStepState.activo]);
    });
  });

  group('estados por tiempo (dos pasos)', () {
    const c = AiWaitContext.respondiendo;
    test('a 0 ms: primero activo; a 1500 el primero hecho y el último activo', () {
      expect(estados(st(c, 0)), [AiWaitStepState.activo, AiWaitStepState.pendiente]);
      expect(estados(st(c, 1500)), [AiWaitStepState.hecho, AiWaitStepState.activo]);
    });
  });

  group('avisos y reporte', () {
    const c = AiWaitContext.armando;
    test('sin aviso antes de 12 s; aviso 1 desde 12 s; aviso 2 desde 30 s', () {
      expect(st(c, 11999).aviso, 0);
      expect(st(c, 12000).aviso, 1);
      expect(st(c, 29999).aviso, 1);
      expect(st(c, 30000).aviso, 2);
    });
    test('reportar solo desde 30 s y solo si no se reportó ya', () {
      expect(st(c, 29999).reportar, isFalse);
      expect(st(c, 30000).reportar, isTrue);
      expect(st(c, 30000, yaReportado: true).reportar, isFalse);
      expect(st(c, 44000, yaReportado: true).reportar, isFalse);
    });
    test('textos de los avisos', () {
      expect(kAiWaitAviso1Titulo, 'Esto ya debió estar listo.');
      expect(kAiWaitAviso1Texto, 'Veré qué pasa.');
      expect(kAiWaitAviso2Titulo, 'Ya esto es demasiado.');
      expect(kAiWaitAviso2Texto, 'Reportando la tardanza.');
    });
  });

  test('AiTurnSlow se serializa con su contexto para el reporter', () {
    const e = AiTurnSlow(
        contexto: AiWaitContext.primerEnvio, turno: 1, conFoto: true, elapsedMs: 30012);
    expect(e.toString(), 'AiTurnSlow contexto=primerEnvio turno=1 conFoto=true elapsedMs=30012');
  });
}
