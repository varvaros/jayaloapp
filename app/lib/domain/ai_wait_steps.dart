/// Hilo de pasos mientras la IA responde (spec 2026-09-05-hilo-espera-creador).
///
/// El endpoint `/api/ai/chat-stream` devuelve UN JSON por turno, sin etapas:
/// todo lo que se enseña lo decide el cliente por CONTEXTO (qué turno es) y
/// por TIEMPO transcurrido. Esta función es pura para que la batería de casos
/// sea la misma en Dart y en TS (`src/lib/aiWaitSteps.ts` en la web).
///
/// Los umbrales de los avisos NO son decorativos: a los 12 s el servidor
/// cambia de modelo de verdad (`chat-stream.ts`, `aiChatWithFallback`) y como
/// tarde a los 42 s se rinde — decirlo a los 12 y a los 30 es sincero.
library;

/// Qué turno es. Se decide al MANDAR (ver `_ask` en la pantalla).
enum AiWaitContext { primerEnvio, respondiendo, armando }

enum AiWaitStepState { pendiente, activo, hecho }

class AiWaitStep {
  const AiWaitStep(this.texto, this.estado);
  final String texto;
  final AiWaitStepState estado;
}

class AiWaitState {
  const AiWaitState({
    required this.pasos,
    required this.aviso,
    required this.reportar,
  });

  final List<AiWaitStep> pasos;

  /// 0 = sin aviso · 1 = «Esto ya debió estar listo» (12 s) · 2 = «Ya esto es
  /// demasiado» (30 s). El 2 SUSTITUYE al 1, no se apilan.
  final int aviso;

  /// true SOLO en el primer instante ≥ 30 s en que el llamador aún no reportó.
  final bool reportar;
}

/// Instantes en que se marcan el 1º y el 2º paso. El último nunca se marca:
/// queda activo hasta que llega la respuesta.
const kAiWaitPasoMs = [1500, 3000];
const kAiWaitAvisoMs = 12000;
const kAiWaitReporteMs = 30000;

/// Cada cuánto el reloj de la pantalla repinta el hilo.
const kAiWaitTickMs = 250;

/// El texto que manda la app cuando el primer envío es SOLO foto
/// (`_startSend`) — y el que manda la web en el mismo caso.
const kAiWaitFotoSola = 'Esto es lo que busco.';

const kAiWaitAviso1Titulo = 'Esto ya debió estar listo.';
const kAiWaitAviso1Texto = 'Veré qué pasa.';
const kAiWaitAviso2Titulo = 'Ya esto es demasiado.';
const kAiWaitAviso2Texto = 'Reportando la tardanza.';

const _kRecorte = 30;

/// Lo que escribió el cliente, recortado a 30 caracteres sin partir palabra.
String aiWaitRecorte(String s) {
  final t = s.trim();
  if (t.length <= _kRecorte) return t;
  var corte = t.substring(0, _kRecorte);
  final ultimoEspacio = corte.lastIndexOf(' ');
  if (ultimoEspacio > 0) corte = corte.substring(0, ultimoEspacio);
  return '${corte.trimRight()}…';
}

List<String> _textos(AiWaitContext c, String primerMensaje) {
  switch (c) {
    case AiWaitContext.primerEnvio:
      final soloFoto = primerMensaje.trim() == kAiWaitFotoSola;
      return [
        'Ok… déjame ver esto…',
        soloFoto
            ? 'Ya veo, déjame ver más cerca esa foto'
            : 'Ya veo, déjame ver más cerca «${aiWaitRecorte(primerMensaje)}»',
        'Ya casi…',
      ];
    case AiWaitContext.respondiendo:
      return [
        'Anotando eso en mi libreta de detective',
        'Buscando qué más preguntarte sin caer pesado',
      ];
    case AiWaitContext.armando:
      return [
        'Pasando tu solicitud en limpio',
        'Olfateando el rubro correcto',
        'Reclutando a los proveedores que sí saben de esto',
      ];
  }
}

AiWaitState aiWaitState({
  required AiWaitContext contexto,
  required String primerMensaje,
  required int elapsedMs,
  required bool yaReportado,
}) {
  final textos = _textos(contexto, primerMensaje);
  final n = textos.length;
  final pasos = <AiWaitStep>[];
  for (var k = 0; k < n; k++) {
    final AiWaitStepState estado;
    if (k == n - 1) {
      // El último no se marca nunca: se activa cuando el anterior se marcó.
      final desde = n == 1 ? 0 : kAiWaitPasoMs[n - 2];
      estado = elapsedMs >= desde ? AiWaitStepState.activo : AiWaitStepState.pendiente;
    } else if (elapsedMs >= kAiWaitPasoMs[k]) {
      estado = AiWaitStepState.hecho;
    } else if (k == 0 || elapsedMs >= kAiWaitPasoMs[k - 1]) {
      estado = AiWaitStepState.activo;
    } else {
      estado = AiWaitStepState.pendiente;
    }
    pasos.add(AiWaitStep(textos[k], estado));
  }
  final aviso = elapsedMs >= kAiWaitReporteMs
      ? 2
      : elapsedMs >= kAiWaitAvisoMs
          ? 1
          : 0;
  return AiWaitState(
    pasos: pasos,
    aviso: aviso,
    reportar: elapsedMs >= kAiWaitReporteMs && !yaReportado,
  );
}

/// Lo que se reporta a los 30 s por `reportError` (core/error_reporter.dart):
/// el reporter usa `runtimeType` como `error_type` y `toString()` como
/// `message`, y deduplica por la pareja durante 60 s — el `turno` en el
/// texto hace que dos turnos lentos seguidos NO se coman entre sí.
class AiTurnSlow implements Exception {
  const AiTurnSlow({
    required this.contexto,
    required this.turno,
    required this.conFoto,
    required this.elapsedMs,
  });

  final AiWaitContext contexto;
  final int turno;
  final bool conFoto;
  final int elapsedMs;

  @override
  String toString() =>
      'AiTurnSlow contexto=${contexto.name} turno=$turno conFoto=$conFoto elapsedMs=$elapsedMs';
}
