# Diseño — "Ver mi oferta": el botón lleva a ESA oferta, sin salir de la solicitud

Fecha: 2026-08-03
Origen: `docs/qa/2026-08-03-hallazgo-ver-mi-oferta.md` (petición del PO)
Alcance: **solo la app**. En la web ese literal solo existe como CTA de correos
(`src/lib/email/notification-templates.ts:73,75`), donde llevar a la lista sí tiene sentido porque el
lector no viene de ninguna solicitud concreta.

## Problema

El proveedor entra a una solicitud en la que ya ofertó. La tarjeta dice "Ya enviaste tu oferta · Tu
oferta: RD$X" y el botón **"Ver mis ofertas"** lo saca a la lista completa, donde tiene que volver a
buscar la oferta de la solicitud en la que ya estaba. Debe decir **"Ver mi oferta"**, en singular, y
llevar directamente a esa.

## El nudo, y cómo se resuelve

La pantalla desde la que se pulsa el botón es la misma a la que habría que navegar: "ver mi oferta"
ya significa "abrir el detalle de la solicitud en modo edición"
(`my_offers_screen.dart:455-462`), no hay pantalla de oferta suelta.

**Decisión: el botón no navega.** La pantalla entra en modo edición sobre sí misma con un `setState`.

Tres hechos lo hacen barato, y los tres se comprobaron en el código antes de decidir:

1. La compuerta que elige tarjeta-vs-formulario **ya** lee `_editing`
   (`request_detail_screen.dart:1559-1561`). En cuanto `_editing` pase a ser cierto, el mismo `build`
   cambia la tarjeta por el formulario. No hay que tocarla.
2. `_existingOffer` en la ruta normal se carga con `myOfferForRequest`, que selecciona `offerCols`
   (`repos.dart:272-289`). Se cotejó columna por columna: cubre **todo** lo que `_prefillFromOffer`
   lee. Entrar en edición no necesita ninguna consulta nueva.
3. Lo único que ata la edición al widget es `bool get _editing => widget.editOfferId != null`
   (`request_detail_screen.dart:132`). Ese es el nudo entero.

Se descartó apilar con `context.push` (el patrón de `my_offers_screen`) porque dejaría dos
instancias de la misma pantalla en la pila. Su ventaja aparente —"el atrás devuelve a la solicitud en
lectura"— además es falsa: `BackGuard` envuelve la pantalla con `canPop: false` y `backActionFor`
manda a `/provider` desde cualquier ruta que no sea el home (`back_intent.dart:18`). Solo la flecha
flotante hace `context.pop()` (`request_detail_screen.dart:1733`).

## Los cambios

### 1. El estado deja de ser del widget

```dart
String? _editOfferId;         // nace de widget.editOfferId; también se activa en sitio
bool _editingInPlace = false; // true SOLO si la edición se activó desde la tarjeta
bool get _editing => _editOfferId != null;
```

`initState` arranca con `_editOfferId = widget.editOfferId` **antes** del `if (_editing)` actual, de
forma que la ruta `?edit=` (desde "Mis ofertas") se comporta exactamente igual que hoy.

Los dos usos restantes de `widget.editOfferId!` pasan a `_editOfferId!`: al guardar
(`request_detail_screen.dart:600`) y al borrar (`:834`). Ambos ya están dentro de guardas de
`_editing`, así que el `!` sigue siendo seguro.

### 2. El botón

El brazo `_` (comodín) del switch de `_alreadyOfferedCard` (`:942-950`) cambia el literal a
**"Ver mi oferta"** y la acción a `_editInPlace(o)`:

```dart
void _editInPlace(Map<String, dynamic> o) {
  setState(() {
    _editOfferId = o['id'] as String;
    _editingInPlace = true;
    _prefillFromOffer(o);
  });
}
```

Ese brazo es el **comodín** del switch: los casos conocidos (`rejected`, `accepted`,
desbloqueada/completada) los atrapan los brazos de arriba, pero un status inesperado cae aquí. Y hay
una asimetría real en el código: la tarjeta lee `o['status'] as String? ?? 'pending'` (`:898`),
mientras que la compuerta que decide tarjeta-vs-formulario compara **en crudo**,
`_existingOffer!['status'] != 'pending'` (`:1560`). Con `status` nulo la tarjeta dice "Ya enviaste tu
oferta" pero la compuerta se niega a mostrar el formulario: el botón quedaría muerto.

Por eso la condición vive en una regla pura, sin defaults, que reproduce la compuerta:

```dart
/// app/lib/domain/offer_edit.dart
bool canEditOfferInPlace(Map<String, dynamic> offer) =>
    offer['unlocked_at'] == null && offer['status'] == 'pending';
```

Y el brazo **conserva el CTA viejo** cuando no se puede editar, en vez de ofrecer un botón inerte:

```dart
canEditOfferInPlace(o) ? 'Ver mi oferta' : 'Ver mis ofertas',
canEditOfferInPlace(o) ? () => _editInPlace(o) : () => context.go('/provider/offers'),
```

Los otros brazos del switch no se tocan.

### 3. Guardar

En `:622-625`, el `context.go('/provider/offers')` se condiciona:

```dart
_toast('Oferta actualizada');
if (_editingInPlace) {
  await _reloadOffer();
  if (!mounted) return;
  setState(() { _editOfferId = null; _editingInPlace = false; });
  return;
}
context.go('/provider/offers');
```

`_reloadOffer` (`:883-890`) relee la fila por el id que `_existingOffer` ya tiene, así que la tarjeta
reaparece con el precio nuevo. No hace falta reponer `_busy`: el `finally` de `_submit` (`:672-674`)
lo hace, y corre también con el `return` de dentro del `try`.

Llegando desde "Mis ofertas", `_editingInPlace` es `false` y esa ruta queda **intacta**.

### 4. Cancelar

Junto a "Eliminar oferta" (`:1702-1711`), un `TextButton` "Cancelar" visible solo cuando
`_editingInPlace`. Limpia `_editOfferId`, `_editingInPlace` y, además, **`_photos` y `_condition`**.

Esos dos últimos son el detalle que no se puede olvidar. `_prefillFromOffer` reasigna los 13
controladores y vacía y rellena `_keptUrls` (`:256-259`), así que volver a entrar los deja limpios
solos. Los que **no** toca son las fotos recién elegidas (`_photos`) y `_condition`, que no es
restaurable desde la oferta por diseño (la web solo lo guarda dentro del mensaje). Sin limpiarlos,
cancelar y volver a entrar arrastraría fotos y un "Nuevo/Usado" que el proveedor creía descartados.

No se toca la flecha flotante ni el `PopScope` de `BackGuard`: el atrás del sistema sigue llevando a
la bandeja, como en toda la pantalla. Meter mano ahí es el gotcha de predictive back ya registrado.

### 5. Eliminar

Sin cambios: sigue haciendo `context.go('/provider/offers')` también en sitio. Eliminar es terminal y
poco frecuente, y la tarjeta que se estaba mirando ya no existe. Reconstruir el estado "sin oferta"
sin salir exigiría resetear a mano los 13 controladores, los toggles y las fotos — justo el estado a
medias que produce bugs en un fichero sin costura de tests.

## Verificación

`request_detail_screen.dart` no tiene costura de tests (ver el spec de la tanda B), así que **todo
esto se verifica en device**. No hay test que cubra el cableado.

Camino principal:

1. Entrar a una solicitud ya ofertada, con la oferta en `pending`.
2. La tarjeta dice "Ya enviaste tu oferta" y el botón dice **"Ver mi oferta"**, en singular.
3. Pulsarlo: aparece el formulario, en la misma pantalla, con los datos de la oferta cargados.
4. Cambiar el precio y pulsar "Guardar cambios": toast "Oferta actualizada" y **vuelve la tarjeta,
   con el precio nuevo**, sin salir de la solicitud.

Regresión, que es donde está el riesgo real:

- **Cancelar** deja la tarjeta como estaba; volver a entrar no arrastra fotos ni cambios.
- Los brazos `aceptada`, `desbloqueada`/`completada` y `rechazada` siguen con sus CTA de siempre.
- Desde **"Mis ofertas"** → editar → Guardar sigue guardando y saliendo a la lista, igual que hoy.
  Esta es la ruta que llevaba 5 días rota y se arregló el mismo día con la migración
  `20260803120000`; es la primera que hay que reprobar.
- **Eliminar oferta**, por las dos vías, sigue llevando a la lista.
