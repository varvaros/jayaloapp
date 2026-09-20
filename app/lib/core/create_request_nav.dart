import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Ruta de la ventana modal de crear solicitud.
const kCreateRequestRoute = '/client/create';

/// Único punto de entrada a la ventana de crear solicitud, a prueba de doble
/// toque (bug PO 2026-07-28: "la ventana sale varias veces una arriba de la
/// otra").
///
/// Por qué no basta con el `loc` del `build`: `GoRouterState.of(context)` se
/// refresca cuando el widget se reconstruye, es decir un frame DESPUÉS del
/// `push`. Dos toques dentro de esa ventana pasan ambos el guardia.
/// `routerDelegate.currentConfiguration` se actualiza de forma síncrona dentro
/// del propio `push`, así que el segundo toque ya ve la ventana en la pila.
///
/// Tampoco se usa un `bool _pushing` con temporizador: sería un debounce por
/// tiempo, arbitrario y frágil (si la transición dura más que el timeout, el
/// bug vuelve). La pila del router es la fuente de verdad real.
void pushCreateRequestOnce(
  BuildContext context, {
  String? seedFrom,
  String? targetBusinessId,
}) {
  final router = GoRouter.of(context);
  final yaAbierta = router.routerDelegate.currentConfiguration.matches.any(
    (m) => m.matchedLocation == kCreateRequestRoute,
  );
  if (yaAbierta) return;

  // `business` = cotización DIRIGIDA a un negocio (botón «Pedir cotización» de
  // su tienda): la solicitud nace con target_business_id y solo la ve él.
  final params = <String, String>{
    if (targetBusinessId != null && targetBusinessId.isNotEmpty)
      'business': targetBusinessId,
    'seedFrom': ?seedFrom,
  };
  final destino = params.isEmpty
      ? kCreateRequestRoute
      : Uri(path: kCreateRequestRoute, queryParameters: params).toString();
  router.push(destino);
}
