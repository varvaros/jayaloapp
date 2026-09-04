/// Orden de la bandeja del proveedor. El PO lo dictó en tres vueltas el
/// 2026-09-04, y esta es la tercera, que manda:
///
///   0. te aceptaron y **falta desbloquear** — dinero esperando, acción tuya
///   1. **no has ofertado y NADIE ha ofertado** (el chip «¡Haz la primera
///      oferta!», ver `first_offer_chip.dart`)
///   2. no has ofertado, pero ya hay ofertas de otros
///   3. ya ofertaste y **te la cambiaron** desde que la abriste
///   4. ya ofertaste
///   5. **desbloqueada o completada**
///   6. rechazada / cancelada
///
/// Lo que movió la tercera vuelta, y por qué: las desbloqueadas estaban en el
/// puesto 1 y **bajan al 5**. Se midió la bandeja real del PO contra prod: sus
/// tres primeras filas eran ventas de agosto ya aceptadas, ya pagadas y ya en
/// el chat, y tapaban lo único fresco que tenía — unos audífonos del 09-02 que
/// nadie había ofertado. Una desbloqueada **no pide nada**: el dinero ya se
/// cobró y la conversación ya existe. Encabezar con trabajo terminado empuja
/// hacia abajo, cada día, la única fila donde aún se puede ganar algo.
///
/// Y «no has ofertado» se parte en dos por el mismo motivo: que NADIE haya
/// ofertado es la mejor posición que puede tener un proveedor, y hasta ahora
/// solo se pintaba (chip) sin ordenar. Quien decide es `showFirstOfferChip`,
/// la MISMA función que pinta el chip — no un segundo criterio que pueda
/// discrepar con lo que el ojo ve.
///
/// Historia de las otras dos vueltas: la 1ª subió las pendientes de desbloqueo
/// al puesto 0; la 2ª subió «no has ofertado» por delante de «ya ofertaste» y
/// convirtió «la actualizaron» de desempate en grupo. La web
/// (`providerInboxStatus.ts`) va en paralelo con la misma escala.
////// Decisión pura, sin BuildContext ni red, para poder probarla sin widgets
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
  bool firstOffer = false,
}) {
  final action = inboxOfferActionFor(status: status, unlocked: unlocked);
  return switch (action) {
    // Te aceptaron y falta pagar el contacto: la acción que más urge.
    InboxOfferAction.unlock => 0,
    // `inboxOfferActionFor` junta bajo `none` tanto "nunca ofertó" como
    // "rechazada/cancelada", y aquí acaban en los dos extremos. Sin oferta
    // mía se parte en dos: si además NADIE ha ofertado, va lo primero que
    // se puede ganar (1); si ya hay ofertas de otros, detrás (2).
    InboxOfferAction.none =>
      status == null ? (firstOffer ? 1 : 2) : 6,
    // Ya ofertaste: sube si te la cambiaron desde que la abriste.
    InboxOfferAction.offered => updated ? 3 : 4,
    // Desbloqueada o venta 'completed': trabajo TERMINADO. Ya pagaste el
    // contacto y ya tienes el chat, así que no pide nada — por eso deja de
    // encabezar la lista (3ª vuelta del PO) y se va al fondo, solo por
    // delante de lo rechazado.
    InboxOfferAction.unlocked => 5,
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
///
/// [firstOfferIds] son los ids que llevan el chip «¡Haz la primera oferta!».
/// La pantalla los calcula con la MISMA llamada a `showFirstOfferChip` que
/// pinta el chip, para que el orden y lo que se ve no puedan discrepar.
List<Map<String, dynamic>> sortInboxItems(
  List<Map<String, dynamic>> items, {
  required Map<String, String> statuses,
  required Set<String> unlockedIds,
  required Set<String> unseenIds,
  required Set<String> updatedIds,
  required Set<String> firstOfferIds,
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
      firstOffer: idA != null && firstOfferIds.contains(idA),
    );
    final priorityB = inboxPriority(
      status: idB == null ? null : statuses[idB],
      unlocked: idB != null && unlockedIds.contains(idB),
      updated: idB != null && updatedIds.contains(idB),
      firstOffer: idB != null && firstOfferIds.contains(idB),
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
