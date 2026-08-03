/// Qué hace el ATRÁS del sistema dentro del shell (spec del PO 2026-07-17):
/// fuera del home lleva al home; en el home sube al tope; en el tope
/// pregunta antes de cerrar. Nunca minimiza en silencio.
/// Excepción (pedido PO 2026-07-21): DENTRO de una conversación el atrás va a
/// la LISTA de conversaciones, no a "Solicitudes" — es donde el usuario
/// espera volver. Lo mismo DENTRO de un producto del catálogo (pedido PO
/// 2026-08-03): se vuelve al catálogo, no al home.
enum BackAction { goHome, goMessages, goCatalog, scrollTop, confirmExit }

String homePathFor({required bool provider}) =>
    provider ? '/provider' : '/client';

BackAction backActionFor({
  required String location,
  required String homePath,
  required bool atTop,
}) {
  if (location.startsWith('/messages/')) return BackAction.goMessages;
  if (location.startsWith('/catalog/')) return BackAction.goCatalog;
  if (location != homePath) return BackAction.goHome;
  return atTop ? BackAction.confirmExit : BackAction.scrollTop;
}
