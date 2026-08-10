/// Qué hace el ATRÁS del sistema dentro del shell (spec del PO 2026-07-17):
/// fuera del home lleva al home; en el home sube al tope; en el tope
/// pregunta antes de cerrar. Nunca minimiza en silencio.
/// Excepción (pedido PO 2026-07-21): DENTRO de una conversación el atrás va a
/// la LISTA de conversaciones, no a "Solicitudes" — es donde el usuario
/// espera volver. Lo mismo DENTRO de un producto del catálogo (pedido PO
/// 2026-08-03): se vuelve al catálogo, no al home.
enum BackAction { goHome, goMessages, goCatalog, popCurrent, scrollTop, confirmExit }

String homePathFor({required bool provider}) =>
    provider ? '/provider' : '/client';

BackAction backActionFor({
  required String location,
  required String homePath,
  required bool atTop,
  // Solo importa para `/product/:id` (ver más abajo) — el resto de las
  // reglas es puramente por ubicación, así que el valor por defecto no las
  // afecta.
  bool canPop = false,
}) {
  if (location.startsWith('/messages/')) return BackAction.goMessages;
  if (location.startsWith('/catalog/')) return BackAction.goCatalog;
  // Detalle de producto/servicio abierto DESDE LA TIENDA de un proveedor
  // (`/product/:id`, ruta top-level — ver `product_list_card.dart`): a
  // diferencia de `/catalog/:id`, aquí NO hay un único destino fijo al que
  // volver (la tienda del proveedor se abre desde varios lugares: una
  // oferta, la propia fila "Ofrecido por" del detalle...). Pedido PO
  // 2026-08-09: el atrás debe caer en la MISMA tienda de la que se vino, así
  // que se hace un pop real de verdad en vez de forzar un destino fijo —
  // funciona porque esta ruta SIEMPRE se empuja encima de `/store/:bid`
  // (nunca es la raíz de su propio stack; `canPop` lo confirma). Si por
  // algún motivo no hubiera nada debajo, cae a la regla general (goHome) en
  // vez de quedarse atrapada.
  if (location.startsWith('/product/') && canPop) return BackAction.popCurrent;
  if (location != homePath) return BackAction.goHome;
  return atTop ? BackAction.confirmExit : BackAction.scrollTop;
}
