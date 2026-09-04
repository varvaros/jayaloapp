/// Orden de la bandeja del proveedor. El PO lo dictó en dos vueltas el
/// 2026-09-04, y esta es la segunda, que manda:
///
///   **Aceptadas · sin ofertar · actualizadas · ofertadas · rechazadas.**
///
/// «Aceptadas» son dos grupos, no uno: primero la que está PENDIENTE DE
/// DESBLOQUEO —te aceptaron y aún no pagaste el contacto, la tarjeta que
/// enseña «Conversar · N crédito(s)» (ver `inbox_offer_action.dart`)— y
/// detrás la ya desbloqueada o completada. Es la acción que más urge y va
/// arriba del todo, sin importar la fecha.
///
/// Lo que cambió respecto de la primera vuelta: **«no has ofertado» sube por
/// delante de «ya ofertaste»** (antes iba detrás, copiando a la web), y **«la
/// actualizaron» pasa de desempate a GRUPO**, partiendo en dos las que ya
/// ofertaste: si el cliente tocó algo después de que la abrieras, sube. La
/// web (`ProviderInboxSection.tsx`, `priority()`) se queda con el orden
/// viejo hasta que se porte; a partir de aquí los dos criterios ya no son el
/// mismo. La web además desempata por `match_level` (tu especialidad); la app
/// no tiene esa columna en la fila de la bandeja, así que ese paso se omite.
///
/// Decisión pura, sin BuildContext ni red, para poder probarla sin widgets
/// (mismo espíritu que `inbox_load.dart`/`inbox_offer_action.dart`): la
/// pantalla ordena en `build()` con el estado que YA tiene, para que el
/// orden se actualice solo en cuanto llega el mapa de estados (asíncrono,
/// oleada B de `inbox_load.dart`) sin volver a pedir nada a la red.
library;

import 'inbox_offer_action.dart';

/// Grupo de una fila de la bandeja, EN EL ORDEN en que deben aparecer
/// (0 = primero). Reusa [inboxOfferActionFor] para decidir "aceptada y sin
/// desbloquear" vs "desbloqueada" — así `completed` cae SIEMPRE en el grupo
/// desbloqueado (nunca en el de pendiente-de-desbloqueo), la misma regla que
/// ya pinta el botón "Conversar" en la tarjeta.
///
/// [status] es el status crudo de `provider_offers` tal como llega en
/// `_offeredStatuses` de `inbox_screen.dart` — puede ser `'pending'`,
/// `'accepted'`, `'completed'`, `'rejected'`, `'cancelled'`, la marca
/// derivada `'unlocked'` (ver `myOfferedRequestStatuses` en
/// `data/repos.dart`), o `null` si este proveedor no ofertó. [unlocked] es
/// el mismo booleano que ya usa `inboxOfferActionFor` en la tarjeta
/// (`offerStatus == 'unlocked'`).
///
/// [updated] es «el cliente cambió algo DESPUÉS de que abrieras esta
/// solicitud» (`OpenedRequestsStore.hasUpdateSinceSeen`). Solo parte el grupo
/// de las que YA ofertaste, que es el único sitio donde el PO lo colocó: por
/// delante no hay nada que partir (las aceptadas y las que no has ofertado ya
/// están por encima) y por detrás no interesa (una rechazada editada sigue
/// siendo una rechazada).
int inboxPriority({
  required String? status,
  required bool unlocked,
  bool updated = false,
}) {
  final action = inboxOfferActionFor(status: status, unlocked: unlocked);
  return switch (action) {
    // Pendiente de desbloqueo: la acción que más urge, siempre primera.
    InboxOfferAction.unlock => 0,
    // Ya desbloqueado o venta 'completed' (misma regla que la tarjeta: una
    // venta cerrada NUNCA cuenta como pendiente).
    InboxOfferAction.unlocked => 1,
    // `inboxOfferActionFor` junta bajo `none` tanto "nunca ofertó" como
    // "rechazada/cancelada", y aquí quedan en los dos extremos opuestos: sin
    // oferta es lo que más se puede ganar (2), rechazada es lo último (5).
    InboxOfferAction.none => status == null ? 2 : 5,
    // Ya ofertaste: sube si te la cambiaron desde que la abriste.
    InboxOfferAction.offered => updated ? 3 : 4,
  };
}

/// Reordena [items] (ya filtrados/mezclados por la pantalla) según
/// [inboxPriority], con dos desempates, en este orden:
///
/// 1. **`unseenIds`**: dentro del mismo grupo, lo sin abrir va primero
///    (espejo de las «Nueva» de la web, que solo reordenan el grupo sin
///    oferta — aquí no hace falta filtrar por grupo a propósito: al ser el
///    SEGUNDO criterio de un sort estable, solo puede desempatar filas que
///    YA comparten grupo). Ojo: `unseenIds` incluye las que nunca abriste Y
///    las que te cambiaron; [updatedIds] es solo la segunda mitad, y ese es
///    el que forma grupo.
/// 2. **`created_at` descendente**: más reciente primero.
///
/// Y, si dos filas empatan en TODO lo anterior, conserva su orden relativo
/// de entrada (sort ESTABLE a mano — `List.sort` de Dart no lo garantiza).
///
/// [statuses] es `_offeredStatuses` de `inbox_screen.dart` (id → status
/// crudo o la marca `'unlocked'`); [unlockedIds] son los ids cuyo valor en
/// [statuses] es exactamente `'unlocked'` — se pasa aparte, en vez de
/// derivarlo aquí dentro, para espejar la misma llamada a
/// `inboxOfferActionFor(status:, unlocked:)` que ya hace la tarjeta
/// (`inbox_screen.dart`). Las filas de `source == 'store'` (intereses de
/// producto) no tienen entrada en [statuses] → `status == null` → grupo
/// «sin oferta», que es donde ya caían al no tener oferta propia.
///
/// [updatedIds] son los ids que el cliente cambió después de que los
/// abrieras (`OpenedRequestsStore.hasUpdateSinceSeen`). Forman grupo propio
/// dentro de las ya ofertadas — ver [inboxPriority].
List<Map<String, dynamic>> sortInboxItems(
  List<Map<String, dynamic>> items, {
  required Map<String, String> statuses,
  required Set<String> unlockedIds,
  required Set<String> unseenIds,
  required Set<String> updatedIds,
}) {
  String? idOf(Map<String, dynamic> r) =>
      r['id'] is String ? r['id'] as String : null;

  final decorated = <MapEntry<int, Map<String, dynamic>>>[
    for (var i = 0; i < items.length; i++) MapEntry(i, items[i]),
  ];

  decorated.sort((x, y) {
    final idA = idOf(x.value);
    final idB = idOf(y.value);

    final priorityA = inboxPriority(
      status: idA == null ? null : statuses[idA],
      unlocked: idA != null && unlockedIds.contains(idA),
      updated: idA != null && updatedIds.contains(idA),
    );
    final priorityB = inboxPriority(
      status: idB == null ? null : statuses[idB],
      unlocked: idB != null && unlockedIds.contains(idB),
      updated: idB != null && updatedIds.contains(idB),
    );
    if (priorityA != priorityB) return priorityA - priorityB;

    final unseenA = idA != null && unseenIds.contains(idA) ? 0 : 1;
    final unseenB = idB != null && unseenIds.contains(idB) ? 0 : 1;
    if (unseenA != unseenB) return unseenA - unseenB;

    final createdA = x.value['created_at'] as String? ?? '';
    final createdB = y.value['created_at'] as String? ?? '';
    final byDate = createdB.compareTo(createdA); // desc: más reciente primero
    if (byDate != 0) return byDate;

    return x.key - y.key; // empate total: conserva el orden de entrada
  });

  return [for (final e in decorated) e.value];
}
