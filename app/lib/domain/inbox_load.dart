/// Orquestación de la carga de la bandeja del proveedor, separada del widget
/// para poder probar QUE VA EN PARALELO (auditoría de rendimiento 2026-07-28).
///
/// Antes la pantalla hacía sus 4 viajes a la red EN SERIE, así que el proveedor
/// pagaba la suma de las 4 latencias. Solo existe UNA dependencia real de datos
/// —las dos últimas llamadas necesitan los ids que producen las dos primeras—,
/// así que son dos OLEADAS concurrentes:
///
///   oleada A: fetchItems ‖ fetchOfferedOpen ‖ fetchUnseen
///   oleada B: fetchStatuses(ids) ‖ fetchCounts(ids)
///
/// [fetchUnseen] entra en la oleada A y no en la B aunque su resultado se cruce
/// con los items: no necesita los ids (lee las notificaciones sin leer del
/// usuario, no de una lista), así que hacerlo esperar sería añadir latencia a
/// cambio de nada.
///
/// Vive aquí y no en la pantalla porque las tres funciones de `repos.dart` que
/// usa no son inyectables: dentro del widget la concurrencia no se puede probar
/// sin red, y un fix de rendimiento sin test se revierte en el siguiente cambio.
library;

typedef InboxData = ({
  List<Map<String, dynamic>> items,
  Map<String, String> statuses,
  Map<String, int> counts,
  Set<String> unseen,
  int badgeCount,
});

/// [fetchOfferedOpen] en `null` = pestaña "Todas" (ahí no se hace el merge de
/// las solicitudes de otro rubro a las que ya ofertó).
///
/// [fetchUnseen] en `null` (o si falla) = nada consta como sin ver: la bandeja
/// sale sin chips "Nueva" y sin badge. Es la degradación correcta — de las dos
/// mentiras posibles, "no tienes nada nuevo" se corrige sola en la siguiente
/// carga; marcar de nuevo lo ya visto obligaría a abrir solicitudes para
/// apagar un badge que nadie encendió.
///
/// Best-effort: si fallan las ofertas de otro rubro, las no-vistas, los estados
/// o los conteos, la bandeja se pinta igual con lo que sí llegó. Lo ÚNICO que
/// propaga es el fallo de [fetchItems] — sin la lista principal no hay pantalla
/// que pintar, y el `FutureBuilder` debe poder mostrar su estado de error.
Future<InboxData> loadInboxData({
  required Future<List<Map<String, dynamic>>> Function() fetchItems,
  required Future<List<Map<String, dynamic>>> Function()? fetchOfferedOpen,
  required Future<Map<String, String>> Function(List<String>) fetchStatuses,
  required Future<Map<String, int>> Function(List<String>) fetchCounts,
  Future<Set<String>> Function()? fetchUnseen,
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

  final unseenFuture = fetchUnseen?.call().then<Set<String>>(
    (v) => v,
    onError: (Object _, StackTrace _) => <String>{},
  );

  var items = await fetchItems();
  final unseen = await (unseenFuture ?? Future.value(<String>{}));

  // El badge se calcula ANTES del merge a propósito: dar seguimiento a una
  // oferta propia en otro rubro no es una alerta pendiente y no debe inflar el
  // contador de la pestaña "Solicitudes".
  //
  // Y cuenta SIN VER, no abiertas (cambio 2026-08-16): el badge viejo era el
  // tamaño de la bandeja, así que no bajaba nunca por mirar nada — un número
  // permanente que el proveedor aprendía a ignorar. Ahora solo cuenta lo que
  // tiene su `request_new_in_category` sin leer, y abrir la solicitud lo apaga.
  //
  // `unseen` se RECORTA aquí a lo que de verdad sale en la bandeja, y el badge
  // es su tamaño. Se devuelve ya recortado (no el conjunto crudo de la consulta)
  // para que la pantalla pinte el chip "Nueva" EXACTAMENTE sobre lo que el badge
  // cuenta: si fueran dos conjuntos distintos volvería el problema que este
  // cambio arregla —un número que no corresponde a nada que puedas tocar—, solo
  // que al revés. Quedan fuera dos cosas: los avisos de solicitudes que ya se
  // cerraron o dejaron de cruzar su rubro (siguen sin leer, pero ya no están en
  // la lista) y los items de después del merge, que son seguimiento de ofertas
  // propias en otro rubro y nunca fueron una alerta pendiente.
  final unseenHere = {
    for (final r in items)
      if (r['source'] != 'store' && unseen.contains(r['id'])) r['id'] as String,
  };
  final badgeCount = unseenHere.length;

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

  return (
    items: items,
    statuses: await statusesFuture,
    counts: await countsFuture,
    unseen: unseenHere,
    badgeCount: badgeCount,
  );
}
