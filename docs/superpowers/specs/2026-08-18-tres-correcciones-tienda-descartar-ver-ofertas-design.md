# Tres correcciones — «Tienda física», «Descartar» y «Ver ofertas»

Fecha: 2026-08-18
Estado: aprobado por el PO

Tres correcciones pedidas por el PO en una tanda. Son independientes entre sí:
cada una se puede implementar y verificar por separado. Todas viven **solo en
la app Flutter** — ninguna toca la web ni la base de datos.

## Alcance y decisiones tomadas

Decisiones del PO en el brainstorming, para que nadie las vuelva a litigar:

1. «Tienda física» va **pegada a la portada**: lo primero que se ve debajo,
   por encima de servicios y de la tarjeta de reputación.
2. Va en **las dos pantallas**: la tienda pública que ve el cliente y «Mi
   negocio».
3. «Descartar» cambia la **etiqueta del swipe y el texto del aviso**. El
   código interno (`hiddenRequestsStore`, `hide`, `unhide`) **no** se renombra.
4. El toast pegado **se reprodujo antes de arreglarse**. La hipótesis de la
   cola de snackbars resultó falsa; el hueco real era otro (ver el punto 2).
5. El segundo toque en «Ver ofertas» **cierra y ya**: no devuelve scroll ni
   foco al origen.

Fuera de alcance: renombrar internals, cualquier cambio en la web, y el resto
del orden de la tienda.

## Punto 1 — «Tienda física» bajo la portada

### Situación

En la tienda pública (`features/client/provider_store_screen.dart:443`) el
orden de slivers hoy es: portada → servicios → reputación → **Tienda física**
→ ver en el mapa → galería → detalles → catálogo.

La píldora la construye `_physicalLocationBadge` (`:301`): un `StatusChip`
teal con tono `requisito`, envuelto en un `Padding(16, 12, 16, 0)` alineado a
la izquierda. Devuelve `null` si no hay local, y el llamador la monta con un
`if (physicalBadge != null)`. El dato vive en `_hasPhysicalLocation` (`:64`),
que sale de `businessesPhysicalLocation` — consulta propia, con su propio
try/catch, deliberadamente separada del select de nombre/logo/sellos porque la
columna puede no existir todavía (ver `data/repos.dart:2805`).

En «Mi negocio» (`features/provider/my_business_screen.dart`) **el sello no se
pinta en ningún sitio**. Verificado: no está en `BusinessDetailsCard` —
`businessDetailRows` no tiene fila de local físico, el icono de tienda de
`business_details_card.dart:63` es solo el del encabezado— ni en los `seals`
de la portada, que son otra cosa. El dato tampoco se pide en esa pantalla.

### Diseño

**a. Extraer la píldora a un widget compartido.** Nuevo
`features/shared/physical_location_badge.dart` con un constructor estático
`PhysicalLocationBadge.maybe({required bool hasPhysicalLocation})` que
devuelve `Widget?` — `null` cuando no hay local. Se sigue el idioma que ya usa
el repo para esto mismo (`TeamGalleryBlock.maybe`), y así ninguno de los dos
llamadores monta un sliver vacío.

**b. Tienda pública.** Sustituir `_physicalLocationBadge` por el widget
compartido y mover su sliver a justo después de `BusinessCoverHero`. Orden
resultante: portada → **Tienda física** → servicios → reputación → mapa →
galería → detalles → catálogo.

**c. «Mi negocio».** Tres cambios:

- Campo `bool _hasPhysicalLocation = false` en el `State`.
- Pedirlo con `businessesPhysicalLocation([b.id])` en su **propia** llamada
  con try/catch, nunca mezclado en el select del negocio. Si falla o la
  columna no existe, degrada a `false` y la pantalla sigue viva.
- Montar el badge entre `BusinessCoverHero(...).cascadeIn(0)` y
  `SectionHeader('SOBRE EL NEGOCIO')`.

**Detalle de la cascada:** los hijos de esa lista llevan `cascadeIn(0..4)`. El
badge **no** lleva `cascadeIn` — es un chip pequeño y dárselo obligaría a
renumerar toda la cascada de abajo por un beneficio nulo.

### Verificación

- Proveedor con local, tienda pública: la píldora sale inmediatamente bajo la
  portada, encima de servicios.
- Proveedor sin local: no sale nada y no queda hueco ni separación extra.
- «Mi negocio» con local: igual que la pública.
- Con la columna ausente (forzar el error de la consulta): ninguna de las dos
  pantallas se cae; simplemente no hay sello.

## Punto 2 — «Descartar» y el aviso que no se va

### Situación

En `features/provider/inbox_screen.dart:391` la acción del swipe se llama
`Ocultar` y su `onTap` muestra `Solicitud ocultada.` con acción «Deshacer».

`showJayaloToast` (`features/shared/brand_kit.dart:1051`) hace
`hideCurrentSnackBar()` y después `showSnackBar(...)`. No fija `duration`, así
que usa los 4 s por defecto de Flutter. El `ScaffoldMessenger` es el de la
raíz de `MaterialApp` (`app.dart:168`), de modo que los avisos sobreviven a los
cambios de pantalla.

Reporte del PO: el toast no desaparece ni al tocarlo ni al cambiar de pantalla.

### Diagnóstico — medido, no supuesto

La hipótesis inicial era una cola de snackbars: que `hideCurrentSnackBar()`
destapaba el siguiente y varios descartes seguidos encadenaban avisos de 4 s.
**Es falsa.** Se midió con `test/jayalo_toast_queue_test.dart`:

- Un aviso solo **sí** desaparece pasada su duración.
- Cinco descartes seguidos **no** encadenan nada: `hideCurrentSnackBar()`
  retira el anterior de verdad en lugar de encolarlo, así que solo se ve el
  último.
- **Tocar el aviso no lo cierra.** Ése era el único hueco real, y coincide con
  lo que reportó el PO («no desaparece aunque lo cliquees»).

Es comportamiento estándar de Flutter: el cuerpo de un `SnackBar` no responde
al toque, solo lo hace su acción. Importa aquí más que en otras apps porque el
`ScaffoldMessenger` es el de la raíz (`app.dart:168`), así que el aviso te
sigue a la pantalla siguiente durante lo que le quede de vida — y sin salida
manual se siente clavado.

Nota de método: el primer intento de test daba falso positivo. Un solo
`pump(Duration(seconds: 5))` produce **un** frame; la animación de entrada del
SnackBar se completa en él y el temporizador de 4 s arranca justo entonces, de
modo que el aviso parecía no irse nunca. Hay que bombear la entrada aparte
antes de dejar correr el reloj.

### Diseño

Renombrado, sin condiciones:

- La etiqueta del swipe pasa a «Descartar».
- El texto del aviso pasa a «Solicitud descartada.».

El icono del swipe (`visibility_off_outlined`) se deja como está: cambiarlo no
lo pidió el PO y es una decisión estética aparte.

Arreglo del toast: envolver el contenido de `showJayaloToast` en un
`GestureDetector` opaco que llame a `hideCurrentSnackBar`. Nada más.

**Descartado:** cambiar `hideCurrentSnackBar()` por `clearSnackBars()`. Se
proponía para matar una cola que las mediciones demuestran que no existe.

### Verificación

- Descartar una solicitud: el aviso se va solo a los 4 s.
- Descartar cinco seguidas: se ve **un** aviso, no cinco encadenados.
- «Deshacer» sigue devolviendo la solicitud a la bandeja.
- Cambiar de pantalla con el aviso visible: no se queda clavado.
- La etiqueta dice «Descartar» y el aviso «Solicitud descartada.».

## Punto 3 — «Ver ofertas» que alterna

### Situación

El botón vive en `features/client/request_detail_sheet.dart:373` y dispara
`onSeeOffers`, que `request_status_screen.dart:250` cablea a `_showOffers`
(`:268`). Ese método llama a `showModalBottomSheet` (`:312`) sin ningún guard:
dos toques apilan dos hojas.

El repo ya resolvió exactamente esto en
`features/client/create_request_screen.dart:485` (`_showPickSheet`), y salió
de un pedido idéntico del PO.

### Diseño

Portar ese patrón:

- Campo `BuildContext? _offersSheetCtx` en el `State` de
  `request_status_screen`.
- Al entrar en `_showOffers`: si hay contexto guardado y sigue `mounted`,
  hacer `pop` sobre él, limpiar el campo y **salir**.
- Guardar el contexto de la hoja en su `builder`.
- Limpiar el campo cuando la hoja se cierre por cualquier vía —tras el `await`
  del `showModalBottomSheet`—, porque también se cierra con «atrás» o tocando
  fuera.

Se guarda el **contexto** y no un `bool` por la razón que ya documenta
`create_request_screen`: un `pop` con el contexto de la pantalla sacaría lo que
esté al tope del navigator, que no tiene por qué ser la hoja (por ejemplo si
encima se abrió el visor de fotos).

### Verificación

- Un toque abre, el segundo cierra, el tercero vuelve a abrir.
- Cerrar con «atrás» o tocando fuera y volver a tocar el botón: abre (no se
  queda creyendo que sigue abierta).
- Con la hoja abierta y el visor de fotos encima, tocar el botón no cierra lo
  que no debe.

## Pruebas

El grueso es smoke en device: dos de los tres puntos son comportamiento en
pantalla y no se capturan bien en test de widget.

- Test de widget: `PhysicalLocationBadge.maybe` devuelve `null` sin local.
- Test de widget: la acción del swipe rotula «Descartar».
- El resto (orden visual, toggle de la hoja, vida del toast) va al smoke del
  APK.

## Ficheros que se tocan

- `features/shared/physical_location_badge.dart` (nuevo)
- `features/client/provider_store_screen.dart`
- `features/provider/my_business_screen.dart`
- `features/provider/inbox_screen.dart`
- `features/shared/brand_kit.dart`
- `features/client/request_status_screen.dart`
