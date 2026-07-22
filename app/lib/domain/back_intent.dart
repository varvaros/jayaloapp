/// Qué hace el ATRÁS del sistema dentro del shell (spec del PO 2026-07-17):
/// fuera del home lleva al home; en el home sube al tope; en el tope
/// pregunta antes de cerrar. Nunca minimiza en silencio.
/// Excepción (pedido PO 2026-07-21): DENTRO de una conversación el atrás va a
/// la LISTA de conversaciones, no a "Solicitudes" — es donde el usuario
/// espera volver.
enum BackAction { goHome, goMessages, scrollTop, confirmExit }

String homePathFor({required bool provider}) =>
    provider ? '/provider' : '/client';

BackAction backActionFor({
  required String location,
  required String homePath,
  required bool atTop,
}) {
  if (location.startsWith('/messages/')) return BackAction.goMessages;
  if (location != homePath) return BackAction.goHome;
  return atTop ? BackAction.confirmExit : BackAction.scrollTop;
}
