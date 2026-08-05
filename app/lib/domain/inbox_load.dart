/// Orquestación de la carga de la bandeja del proveedor, separada del widget
/// para poder probar QUE VA EN PARALELO (auditoría de rendimiento 2026-07-28).
///
/// Antes la pantalla hacía sus 4 viajes a la red EN SERIE, así que el proveedor
/// pagaba la suma de las 4 latencias. Solo existe UNA dependencia real de datos
/// —las dos últimas llamadas necesitan los ids que producen las dos primeras—,
/// así que son dos OLEADAS concurrentes:
///
///   oleada A: fetchItems ‖ fetchOfferedOpen
///   oleada B: fetchStatuses(ids) ‖ fetchCounts(ids) ‖ fetchRequirements(ids)
///
/// Vive aquí y no en la pantalla porque las tres funciones de `repos.dart` que
/// usa no son inyectables: dentro del widget la concurrencia no se puede probar
/// sin red, y un fix de rendimiento sin test se revierte en el siguiente cambio.
library;

import 'request_requirements.dart';

typedef InboxData = ({
  List<Map<String, dynamic>> items,
  Map<String, String> statuses,
  Map<String, int> counts,
  Map<String, RequestRequirements> requirements,
  int badgeCount,
});

/// [fetchOfferedOpen] en `null` = pestaña "Todas" (ahí no se hace el merge de
/// las solicitudes de otro rubro a las que ya ofertó).
///
/// Best-effort: si fallan las ofertas de otro rubro, los estados, los conteos
/// o los requisitos, la bandeja se pinta igual con lo que sí llegó. Lo ÚNICO
/// que propaga es el fallo de [fetchItems] — sin la lista principal no hay
/// pantalla que pintar, y el `FutureBuilder` debe poder mostrar su estado de
/// error.
Future<InboxData> loadInboxData({
  required Future<List<Map<String, dynamic>>> Function() fetchItems,
  required Future<List<Map<String, dynamic>>> Function()? fetchOfferedOpen,
  required Future<Map<String, String>> Function(List<String>) fetchStatuses,
  required Future<Map<String, int>> Function(List<String>) fetchCounts,
  required Future<Map<String, RequestRequirements>> Function(List<String>)
  fetchRequirements,
}) async {
  // El manejo del error va PEGADO a la creación del future, no en un `try` que
  // envuelva al `await`: al lanzarlo en paralelo el error puede ocurrir antes de
  // que nadie lo espere, y un future en vuelo sin handler se reporta como
  // excepción no atrapada (rompe `pumpAndSettle` en los tests).
  //
  // Y se usa `then(onError:)` en vez de `catchError`: `catchError` recibe un
  // `Function` sin tipar y valida EN RUNTIME que el handler devuelva el tipo del
  // future, así que lanza "The error handler of Future.catchError must return a
  // value of the future's type" en cuanto la fuente es un `Future<Never>` (lo
  // destapó el test del caso de fallo). `then<R>` con el argumento de tipo
  // explícito se comprueba en compilación y no depende del tipo de la fuente.
  final offeredFuture = fetchOfferedOpen
      ?.call()
      .then<List<Map<String, dynamic>>>(
        (v) => v,
        onError: (Object _, StackTrace _) => <Map<String, dynamic>>[],
      );

  var items = await fetchItems();

  // El badge se calcula ANTES del merge a propósito: dar seguimiento a una
  // oferta propia en otro rubro no es una alerta pendiente y no debe inflar el
  // contador de la pestaña "Solicitudes".
  final badgeCount = items.where((r) => r['source'] != 'store').length;

  if (offeredFuture != null) {
    final have = {for (final r in items) r['id']};
    final offered = await offeredFuture;
    items = [...items, ...offered.where((r) => !have.contains(r['id']))]
      ..sort(
        (a, b) => (b['created_at'] as String? ?? '').compareTo(
          a['created_at'] as String? ?? '',
        ),
      );
  }

  final ids = [
    for (final r in items)
      if (r['source'] != 'store') r['id'] as String,
  ];
  final statusesFuture = fetchStatuses(ids).then<Map<String, String>>(
    (v) => v,
    onError: (Object _, StackTrace _) => <String, String>{},
  );
  final countsFuture = fetchCounts(ids).then<Map<String, int>>(
    (v) => v,
    onError: (Object _, StackTrace _) => <String, int>{},
  );
  // Los requisitos que el cliente exige (comprobante fiscal, suplidor del
  // Estado, envío…). Se piden aparte porque `get_provider_inbox_unified` no los
  // devuelve; ver `requirementsForRequests` en repos.dart. Best-effort como sus
  // dos hermanas: sin ellos la tarjeta cae a los de su propia fila.
  final requirementsFuture = fetchRequirements(ids)
      .then<Map<String, RequestRequirements>>(
        (v) => v,
        onError: (Object _, StackTrace _) => <String, RequestRequirements>{},
      );

  return (
    items: items,
    statuses: await statusesFuture,
    counts: await countsFuture,
    requirements: await requirementsFuture,
    badgeCount: badgeCount,
  );
}
