# Detalle de solicitud del cliente: foto plegable y orden de secciones — diseño

Fecha: 2026-08-02
Estado: aprobado por el PO (2026-08-02)

Portar T3 (foto plegable) y T4 (orden de secciones) del spec del 2026-08-01 a la
pantalla del **cliente**, que quedó fuera de aquella tanda.

## Cómo salió esto

El PO instaló el APK de release del 2026-08-02 y reportó que "no sube la ventana,
ni tiene la organización de la tarjeta con los datos del cliente, ni detalles del
proveedor". Se verificó el binario: los marcadores `CollapsingPhotoPanel`,
`Datos del cliente` y `DETALLES DEL PROVEEDOR` **están presentes** en el
`libapp.so` del APK instalado, y ausentes en el build anterior (`JayaloBETA.apk`,
31 jul). El APK era correcto.

Lo que pasaba es que T3 y T4 se implementaron solo sobre
`lib/features/provider/request_detail_screen.dart`. La pantalla que el PO estaba
mirando es otra: `lib/features/client/request_status_screen.dart` (1128 líneas),
el detalle de la solicitud **desde el lado del cliente**. Nunca estuvo en alcance
— el spec de T3 habla del *"formulario de oferta: precio, disponibilidad,
detalles de producto, hasta 4 fotos, aviso de costo"*, que solo existe del lado
del proveedor.

No es un fallo de build ni de instalación. Es una brecha de alcance.

## Lo que hay hoy en la pantalla del cliente

```dart
Column(
  children: [
    _AmberPanel(...),                    // height: 300 + topInset — FIJO
    Expanded(child: _DetailSheet(...)),  // Container + Column(Expanded(ListView), CTA)
  ],
)
```

Es exactamente la estructura que T3 describía como el problema del otro lado: un
`Container` de alto fijo con la lista debajo, y la foto que no se mueve nunca.

`_AmberPanel` (líneas 556-648) hace cuatro cosas:

1. Foto a `cover` que llena el panel; tocarla abre `showPhotoViewer`.
2. Sin foto (o si falla), ícono de fase grande (120) sobre lila claro.
3. Miniatura de la 2ª foto pegada al borde derecho (76×76), abre el visor en índice 1.
4. Botón atrás flotante (`_CornerFab`) arriba a la izquierda.

Orden de contenido actual del `_DetailSheet`:

título → chip "Al por mayor" → "Desde: RD$X" → `'Detalles'` + chips → bullets →
"Publicada …" + copy de fase → cupos restantes → paneles de calificar → CTA.

El único rótulo de sección es un `'Detalles'` suelto (línea 753). No hay
`_sectionHeading`, que es lo que T4 introdujo del lado del proveedor.

## El título cortado — HIPÓTESIS, no verificado

En la captura del dispositivo, la primera línea del título aparece recortada
contra el borde inferior del panel. La explicación que encaja es que la lista
scrollea y su contenido se recorta contra el panel fijo — es decir, el mismo
síntoma que T3 vino a eliminar, no un bug aparte.

**No está comprobado.** El intento de verificarlo en el dispositivo falló: los
gestos enviados por `adb` sacaron la app de la pantalla. Por eso la primera tarea
del plan es un test de widget que lo reproduzca **contra el código actual**. Si
ese test no falla, la hipótesis es falsa y hay que investigar de nuevo antes de
seguir.

## Alcance

### Estructura

Espejar al proveedor (`request_detail_screen.dart:1359`):

```dart
body: CustomScrollView(slivers: [
  CollapsingPhotoPanel(
    images: images,
    fallbackIcon: phaseChip(phase, 0).$1,
    leading: _CornerFab(icon: Icons.arrow_back_ios_new, tooltip: 'Atrás', onTap: _goBack),
    onOpenViewer: (i) => showPhotoViewer(context, images, initialIndex: i),
  ),
  SliverFillRemaining(child: _DetailSheet(...)),
])
```

`_AmberPanel` **se elimina entero**. El widget compartido
(`features/shared/collapsing_photo_panel.dart`) ya cubre sus cuatro
responsabilidades, incluida la miniatura de la 2ª foto, y usa los mismos colores
— su propio comentario dice "mismo criterio que el detalle del cliente".

Diferencia con el proveedor: el `fallbackIcon` aquí es el **ícono de fase**
(`phaseChip`), no `handyman`/`inventory_2`. El widget lo recibe por parámetro, así
que no hay que tocarlo.

Dentro de `SliverFillRemaining`, `_DetailSheet` conserva su
`Column(Expanded(ListView), CTA)`: **el CTA "Ver N ofertas" sigue fijo abajo**,
como hoy.

Descartadas: bajar el CTA a un sliver al final (quedaría fuera de pantalla justo
cuando hace falta) y montarlo en un `Stack` flotante (gana control, se separa del
patrón del proveedor sin necesidad).

> **ENMIENDA 2026-08-02 — los dos párrafos de arriba se midieron y NO funcionan.**
>
> El texto original se deja intacto a propósito: hay que poder leer la secuencia
> completa —qué se creyó, qué se midió, qué se decidió—, no una historia
> reescrita. Este spec estaba aprobado y describía una arquitectura que la
> medición tumbó.
>
> - **Lo que se creía.** Que bastaba meter `_DetailSheet` tal cual dentro de
>   `SliverFillRemaining`, que la hoja conservaría su
>   `Column(Expanded(ListView), CTA)`, y que sacar el CTA del scroll era una de
>   las opciones **descartadas**.
> - **Lo que se midió** (Task 4, primera vuelta → `BLOCKED`). Con esa
>   composición el panel **no se plegó**: 300.0 → 300.0, mientras el título
>   scrolleaba solo por dentro, de 322 a 251. La hoja tenía su propio `ListView`
>   y los dos scrolls quedaban **aislados**. Los consumidores que sí funcionan
>   (detalle del proveedor, interés de producto) usan
>   `SliverFillRemaining(hasScrollBody: false)` sobre contenido **sin scroll
>   propio**; este spec dio por transferible el patrón sin comprobar esa
>   diferencia.
> - **Lo que se decidió** (PO, 2026-08-02). La hoja **pierde su scroll** (el
>   `ListView` pasa a ser un `Column`) y el CTA **sale del `CustomScrollView`**
>   a un widget propio, `RequestDetailCta`, anclado abajo por el `Column` de la
>   pantalla. Es decir: se adoptó una variante de justo lo que el párrafo
>   "Descartadas" daba por descartado. El sliver queda
>   `SliverFillRemaining(hasScrollBody: false)`.
>
> El plan se replanteó en el commit `0d5aa66`; esto es lo mismo aplicado al
> spec. Lo que hay implementado en `request_status_screen.dart` y
> `request_detail_sheet.dart` es la versión de esta enmienda, no la de arriba.

### Secciones

**Decisión del PO (2026-08-02): estado → información → acción.** El cliente ya
sabe lo que pidió; lo que no sabe es cómo va. Por eso lo vivo va primero — es el
mismo criterio que T4 aplicó del otro lado, adaptado: aquí no existe "datos del
cliente", porque el cliente está mirando su propia solicitud.

Bloque de identidad, **sin rótulo**, pegado al panel:

- título
- chip "Al por mayor" (solo productos mayoristas)
- "Desde: RD$X"

**Decisión del PO (2026-08-02): el precio va pegado al título, como titular.**
Conceptualmente es estado (sale de las ofertas recibidas, no de lo que el cliente
escribió), pero es el dato que busca de un vistazo al abrir; enterrarlo en una
sección lo esconde.

Luego, con `_sectionHeading` (mismo helper y versalita que el proveedor):

| Rótulo | Contenido |
|---|---|
| **ESTADO** | "Publicada …", copy de fase, cupos restantes, paneles de calificar |
| **INFORMACIÓN** | `'Detalles'` (chips) y bullets |
| *(sin rótulo)* | CTA "Ver N ofertas", fijo abajo |

Los paneles de calificar van en ESTADO, no en acción: aparecen solo en fase
completada, puede haber varios (uno por negocio completado) y el hueco de acción
lo ocupa el CTA único.

El `'Detalles'` suelto de la línea 753 pasa a ser un rótulo más, para que los
tres se vean iguales.

**El helper hay que extraerlo.** `_sectionHeading` es un método privado del
fichero del proveedor (`request_detail_screen.dart:1063`), así que el cliente no
puede llamarlo. Sube a `features/shared/section_heading.dart` como
`sectionHeading(BuildContext, String)`, y el proveedor pasa a usar el compartido
en sus dos llamadas (líneas 1419 y 1432). Es el mismo criterio que se aplicó con
`CollapsingPhotoPanel`: el segundo consumidor es el que justifica la extracción.

Descartado duplicar las cinco líneas en el fichero del cliente: dos versiones del
mismo rótulo derivan en cuanto alguien ajuste el espaciado o la versalita en una
sola, y ese es justo el tipo de deriva visual que esta tarea viene a corregir.

### Qué NO se toca

- La hoja de ofertas (`_OffersSheet`) y todo el flujo de aceptar/rechazar.
- `_showOffers` y sus tres consultas best-effort.
- El panel de calificar por negocio: cambia de sitio, no de comportamiento.
- `features/provider/request_detail_screen.dart`: ya tiene T3 y T4. Lo único que
  cambia ahí son las dos llamadas a `_sectionHeading`, que pasan al helper
  compartido — sin cambio visual.
- El widget compartido `CollapsingPhotoPanel`: se usa tal cual, no se extiende.

## Pruebas

Siguiendo el patrón de T3, que escribió sus 5 tests antes que el widget.

**Primero, el test de la hipótesis** (contra el código actual, debe FALLAR):

1. Con la lista scrolleada, el título queda recortado por el panel fijo.

Si no falla, parar y reportar: el diagnóstico era erróneo.

**Después, los del port:**

2. En reposo, el panel ocupa el alto expandido.
3. Al bajar, el panel se encoge de verdad (no solo se desplaza).
4. El botón atrás sigue tocable con el panel plegado.
5. El orden de secciones es identidad → ESTADO → INFORMACIÓN.
6. El CTA "Ver N ofertas" permanece visible tras scrollear la lista.
7. Sin fotos, sale el ícono de fase y no la miniatura.
8. Con 2 fotos, la miniatura abre el visor en el índice 1.

## Riesgo conocido

`SliverFillRemaining` con `hasScrollBody: true` (el default) da al hijo el alto
del viewport y le permite scrollear por dentro. Hay que verificar que el scroll
de la `ListView` interna **arrastra el plegado del panel externo** y no queda
aislado. El proveedor usa este mismo patrón y sus tests de T3 pasan, así que hay
precedente — pero es lo primero que puede salir mal y merece su propio test (el
número 3).

> **ENMIENDA 2026-08-02 — el riesgo se materializó.** No hubo que "verificar"
> nada: quedó aislado, 300.0 → 300.0. Y el precedente del proveedor era falso —
> ese lado usa `hasScrollBody: **false**` sobre contenido sin scroll propio, no
> el default. La salida no fue un test, fue rediseñar: ver la enmienda de
> "Estructura".
