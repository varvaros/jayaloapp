# Diseño — El ＋ de la barra se vuelve un menú en arco mientras se crea una oferta

Fecha: 2026-08-05
Origen: petición del PO (2026-08-05), con referencia visual propia (arco de satélites unidos por
una "gota", el círculo central girando a ✕).
Alcance: **solo la app**. Nada de web, nada de BD, ninguna migración.

## Problema

El botón central de la barra flotante es, para los dos roles, `/client/create` — "Crear solicitud"
(`nav_destinations.dart:75`). La pantalla donde el proveedor redacta su oferta,
`/provider/request/:id`, vive **dentro** del shell, así que ese ＋ se ve entero mientras se llena el
formulario.

Matiz sobre el enunciado del PO ("no tiene funcionalidad"): ahí el ＋ **sí hace algo** — apila la
ventana de crear solicitud encima de la oferta a medio llenar. No está muerto, está fuera de lugar,
que en la práctica es peor: es una salida accidental en el punto de la app donde más trabajo tiene
el usuario acumulado sin guardar.

## Qué se pone en su lugar

Un **atajo fijo a las cuatro fuentes que la oferta ya tiene**, desplegado en arco. No hay concepto
nuevo: los cuatro destinos existen hoy como botones dentro del formulario
(`request_detail_screen.dart:1811-1856`) y su único defecto es que se van con el scroll.

| Satélite | Qué hace hoy | Método existente |
|---|---|---|
| Cámara | una foto | `_pickPhoto(ImageSource.camera)` |
| Galería | varias fotos | `_pickPhoto(ImageSource.gallery)` |
| Mi tienda | trae fotos **y autocompleta** precio, color, envío, instalación, estado | `_pickFromStore` |
| Trabajos | trae fotos del portafolio | `_pickFromPortfolio` |

**No se escribe lógica de negocio nueva.** El menú es un segundo camino a métodos que ya están
escritos y probados en device.

### Decisiones cerradas con el PO

1. Los cuatro botones del formulario **se quedan intactos**. El arco es un atajo adicional, no un
   reemplazo: quien ya conoce el formulario no pierde nada.
2. El ＋ **cambia de ícono** mientras el formulario está abierto, igual que ya se vuelve cámara
   dentro de crear-solicitud.
3. Cada satélite lleva **etiqueta** bajo el círculo. "Mi tienda" y "Trabajos" no se adivinan como
   ícono pelado, y son justo las dos que más tiempo le ahorran al proveedor.
4. Solo aplica **con el formulario abierto** (oferta nueva o edición en sitio de una pendiente). Con
   la oferta ya enviada y la tarjeta de resumen a la vista, el ＋ vuelve a ser "Crear solicitud": no
   hay nada que cargar y un menú muerto confunde más que ayudar.

### Lo que NO entra

- **"Paquete" no existe** y no se inventa aquí. En la BD solo hay `'producto' | 'servicio'`
  (`repos.dart:512`), y el tipo de la oferta no lo elige el proveedor: lo fija la solicitud
  (`_req['kind']`). `_pickFromStore` ya prioriza los ítems del mismo tipo por su cuenta.
- El menú lo toma **una sola pantalla**. En Mis ofertas, Mi negocio, catálogo o bandeja el ＋ sigue
  siendo "Crear solicitud".
- No se toca la web ni ninguna tabla.

## El nudo

`core/center_action.dart` ya resuelve "la pantalla al frente se apropia del ＋", y su comentario de
cabecera documenta el contrato. Pero está construido para **un** caso concreto y se le nota en dos
sitios:

1. **La compuerta está cableada a una constante.** El shell solo respeta el override si
   `loc == kCreateRequestRoute` (`home_shell.dart:224` y `:228`), y la etiqueta `'Añadir foto'` está
   a fuego ahí mismo (`:229`). Ninguna otra pantalla puede tomar el botón hoy.
2. **El store solo sabe de un `VoidCallback`.** Un menú necesita varios destinos con ícono, texto y
   estado de habilitado.

Y hay un tercer punto que **no** es de arquitectura sino de ciclo de vida, y es el que puede morder:

3. **Crear-solicitud toma el botón en `initState` y lo suelta en `dispose`, y le basta porque su
   estado no cambia.** Aquí sí cambia: el formulario aparece y desaparece **dentro de la misma
   pantalla** — al enviar la oferta, al entrar en edición en sitio (`_editInPlace`), al cancelarla
   (`_cancelInPlaceEdit`), al borrar. Copiar el patrón de `initState`/`dispose` dejaría el menú vivo
   sobre la tarjeta de resumen.

## Los cambios

### 1. `core/center_action.dart` — generalizar el store

Se añade el tipo del ítem:

```dart
class CenterMenuItem {
  const CenterMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
}
```

Y notifiers nuevos junto a los dos que ya hay:

- `centerActionRoute` (`String?`) — la ruta que tomó el botón. **Sustituye a la constante cableada**
  del shell.
- `centerActionLabel` (`String?`) — hoy vive a fuego en `home_shell.dart:229`.
- `centerActionMenu` (`List<CenterMenuItem>?`) — si es no-nulo, el centro **despliega**; si es nulo
  y hay `centerAction`, actúa directo.
- `centerActionOwner` (`Object?`) — ver abajo.

**El dueño se vuelve explícito.** Hoy la identidad del que tomó el botón *es* el `VoidCallback`:
`releaseCenterAction` compara `identical(centerAction.value, action)` para que el `dispose` de una
pantalla que ya perdió el botón no le borre la acción a la que lo tiene ahora — un `initState` corre
antes que el `dispose` del saliente, y esa guarda es lo único que lo sostiene. Con un menú **no hay
un callback único** que sirva de identidad: hay cuatro. Registrar un no-op de mentira solo para
tener token sería mentir sobre para qué existe el campo.

Se separan los dos papeles:

```dart
void takeCenterAction({
  required Object owner,        // identidad, y nada más
  required IconData icon,
  String? label,
  String? route,
  VoidCallback? action,         // camino directo (la cámara)
  List<CenterMenuItem>? menu,   // camino desplegable (el arco)
});

void releaseCenterAction(Object owner);  // compara contra centerActionOwner
```

Crear-solicitud pasa a `takeCenterAction(owner: _centerCamera, action: _centerCamera, icon: ...)` —
su tear-off ya guardado (`create_request_screen.dart:178`) sigue siendo su identidad, así que su
comportamiento no cambia ni un frame. La guarda de identidad se mantiene intacta, solo que ahora
mira `centerActionOwner`.

`assert(action != null || menu != null)` en `takeCenterAction`: un botón tomado que no hace nada es
justo el estado que esta feature viene a eliminar.

Se mantiene el orden de asignación documentado (todo lo que el shell lee antes que el notifier que
dispara el repintado) y ambos caminos siguen pasando por `_applySafely` — el aplazamiento a fin de
frame que evita el bug de la notificación tragada durante el build (PO 2026-07-30) es exactamente lo
que hace segura la sincronía del punto 4.

**Ruta sin `context`:** el screen la compone de lo que ya sabe —
`'/provider/request/${widget.requestId}'`— sin leer inherited widgets. El shell compara contra
`GoRouterState.of(context).uri.path`, que es **path sin query** (`home_shell.dart:74`), así que
entrar en modo edición con `?edit=<id>` no rompe la igualdad.

### 2. `features/shell/center_arc_menu.dart` — nuevo

El arco, el velo y `ArcBlobPainter`. Fuera de `floating_nav_bar.dart`, que ya lleva 467 líneas y
tiene un solo trabajo: dibujar la píldora.

**Geometría.** Cuatro satélites de 44 dp, radio 84 desde el centro del círculo, repartidos de 160° a
20°. El más lejano queda a ~101 px del eje (79 de coseno + 22 de radio), holgado incluso en 360 dp.

**La gota.** Un `CustomPainter` que une los cinco círculos con puentes cóncavos. Es la **misma
familia de curva** que `buildPillNotchPath` (`floating_nav_bar.dart:189`), que ya usa
`CircularNotchedRectangle` para tallar la unión entre la píldora y el círculo central. Se descarta el
truco clásico de blur + umbral de color (`ImageFiltered` + `ColorFiltered`): es caro y ensucia los
bordes en Android de gama baja, y esta base ya resuelve la forma con path.

El puente se estira con el progreso: en `t = 0` los satélites están dentro del centro y la silueta es
un círculo solo.

**Movimiento.** Entrada escalonada 30 ms por satélite con `JayaloMotion.enter` sobre
`JayaloMotion.base`; salida con `exit`. Tic háptico al abrir (`JayaloHaptics.tabChange`). Con
**`JayaloMotion.reduced(context)`** aparece sin escalonar ni escalar — la doctrina de movimiento no
es opcional.

**Color.** Satélites con los mismos tokens que el centro (`cs.primary` sobre `cs.onPrimary`); velo
sobre `cs.scrim`. Deshabilitado = el mismo círculo atenuado, no un color distinto.

**Cierre.** ✕, velo, o atrás del sistema. Para el atrás se usa `BackButtonListener` **dentro del
portal** — los hijos de `OverlayPortal` siguen en el árbol lógico, así que lo alcanzan. No se toca
`BackGuard` ni se añade ningún `PopScope`: con predictive back ahí hay un gotcha conocido y este
arco no es una ruta.

**Semántica.** Cada satélite es un `Semantics(button: true, label: ...)`; el velo declara "Cerrar
menú".

### 3. `features/shell/floating_nav_bar.dart` — el centro se puede abrir

`_CenterButton` deja de ser `StatelessWidget`: gana estado abierto/cerrado, la rotación del ícono a
✕ y un `OverlayPortal` anclado a sí mismo, para que el arco pinte **por encima** de la píldora y del
cuerpo. `FloatingNavBar` recibe `centerMenuItems` y lo pasa hacia abajo.

La barra **sigue sin saber qué hacen los ítems**, igual que hoy no sabe qué significan los badges.
Esa es la línea que el archivo ya defiende en su cabecera y no se cruza.

⚠️ `PillNotchPainter` asume que el botón central está centrado en el ancho de la barra
(`floating_nav_bar.dart:232-238`, con el aviso ya escrito de que un desfase sería silencioso). El
arco **hereda esa misma suposición**: se centra sobre el mismo eje. Si algún día el layout deja de
ser simétrico, los dos se rompen juntos, no por separado.

### 4. `features/provider/request_detail_screen.dart` — registrar y soltar

**Primero, una compuerta única.** Hoy la decisión "formulario o tarjeta" está repartida en una
cadena `if / else if / else if / else` (`:1728-1750`): sin negocio → CTA a la web; `!_offerChecked` →
spinner; oferta existente que no sea edición de una pendiente → tarjeta; si no → formulario. Se
extrae a un getter, que es la **única** fuente de verdad:

```dart
bool get _offerFormVisible =>
    !(!_editing && _businessId == null) &&
    _offerChecked &&
    !(_existingOffer != null &&
        (!_editing || _existingOffer!['status'] != 'pending'));
```

Es la negación **exacta** de las tres ramas previas (comprobado rama por rama), así que la última
pasa de `else` a `else if (_offerFormVisible)`. Si algún día divergieran, el fallo sería "no se pinta
el formulario" — ruidoso e inmediato —, nunca un menú fantasma sobre una tarjeta.

MANTENIMIENTO: `domain/offer_edit.dart` (`canEditOfferInPlace`) ya reproduce **parte** de esta
compuerta y su comentario apunta a números de línea viejos (`:1559-1560`). Al tocar esto hay que
actualizar esa referencia; la regla en sí no cambia.

**Segundo, la sincronía.** El registro se hace desde `build`, con un tear-off guardado una sola vez
(identidad estable → los `ValueNotifier` no notifican de más, exactamente como `_centerCamera` en
`create_request_screen.dart:178`):

```dart
// Identidad estable de esta pantalla ante el store (ver §1).
final Object _centerOwner = Object();
String get _centerRoute => '/provider/request/${widget.requestId}';

// En build, tras calcular _offerFormVisible:
if (_offerFormVisible) {
  takeCenterAction(
    owner: _centerOwner,
    icon: Icons.library_add_outlined,
    label: 'Cargar',
    route: _centerRoute,
    menu: _buildCenterMenu(),   // recalcula enabled según _busy y _photoCount
  );
} else {
  releaseCenterAction(_centerOwner);
}
```

Los `CenterMenuItem` se reconstruyen en cada `build` porque su `enabled` depende de `_busy` y
`_photoCount`. Por eso **`CenterMenuItem` lleva igualdad por valor** (`==`/`hashCode` a mano;
`equatable` no está en el proyecto) y `centerActionMenu` se compara elemento a elemento antes de
asignar. Los `onTap` son tear-offs guardados una sola vez, igual que `_centerCamera`, para no romper
esa igualdad.

No es un riesgo de bucle: el `ListenableBuilder` del shell envuelve **solo** la barra
(`home_shell.dart:194-210`), no el `child` del Navigator anidado, así que notificar no vuelve a
disparar el `build` de la pantalla. Lo que se evita es más modesto y aun así real: un repintado
espurio de la barra en **cada** `build` del formulario — y ese formulario se reconstruye con cada
tecla que se escribe en un campo de precio.

**Por qué desde `build` y no en `initState`:** es la única forma que no se puede desincronizar el día
que alguien añada un camino nuevo para mostrar u ocultar el formulario. Registrar en los cuatro
sitios que hoy lo cambian (`_submit`, `_editInPlace`, `_cancelInPlaceEdit`, `_deleteOffer`) funciona
hoy y se rompe en silencio a la primera adición. Escribir notifiers desde `build` es seguro
**precisamente porque** `_applySafely` aplaza a fin de frame: ese es el caso para el que se escribió.
Se documenta en el sitio, porque a primera vista parece un anti-patrón.

`dispose` sigue soltando (guarda de identidad incluida): salir de la pantalla no siempre pasa por un
`build` con el formulario ya cerrado.

**Tercero, los estados de los ítems.**

- `_busy` (enviando la oferta): los cuatro deshabilitados.
- `_photoCount >= _maxOfferPhotos` (5, `:35`): **Cámara, Galería y Trabajos** deshabilitados; al
  tocarlos, el aviso "Ya tienes 5 fotos". **"Mi tienda" sigue habilitado**, porque además de fotos
  autocompleta precio, color, envío, instalación y estado (`_applyStoreProduct`) — y eso sigue
  valiendo con el álbum lleno.
  **Divergencia consciente:** en el formulario los cuatro botones simplemente *desaparecen* al llegar
  al tope (`:1810` y `:1837`). En el arco se atenúan en vez de desaparecer, porque un arco que cambia
  de cuatro satélites a uno se lee como un fallo.
- `_businessId == null`: no llega a darse — sin negocio no hay formulario, lo cubre
  `_offerFormVisible`.

**Ícono y etiqueta en reposo:** `Icons.library_add_outlined` + "Cargar". Es un token de un solo sitio;
cambiarlo tras verlo en device no cuesta nada.

### 5. `features/shell/home_shell.dart` — quitar el cableado

Las tres lecturas de `kCreateRequestRoute` de la zona del centro (`:224`, `:228`, `:256`) pasan a
comparar contra `centerActionRoute`; `'Añadir foto'` sale del shell y entra en el store. El
`ListenableBuilder` suma los notifiers nuevos a su `Listenable.merge` — **la regla que el propio
archivo dejó escrita tras el bug del 2026-07-30 es "si el builder LEE un notifier, lo escucha"**, y
saltársela reproduce ese bug exacto: el ícono se queda en el valor viejo para siempre.

El guard de ruta que evita el parpadeo entre el `dispose` de la pantalla saliente y el rebuild del
shell se conserva tal cual; solo cambia contra qué compara.

## Pruebas

**Se amplían las que ya existen:**

- `center_action_test.dart` — ruta, etiqueta y menú se registran y se sueltan; la comprobación de
  identidad sigue protegiendo al que llegó después.
- `center_action_shell_test.dart` — el shell pinta lo que dice el store en vez de la constante; y
  **crear-solicitud sigue teniendo su cámara**. Esa es la no-regresión que importa de verdad.
- `floating_nav_bar_test.dart` — el centro sin menú se comporta igual que hoy (un toque = un
  `onSelected`, sin overlay).

**Nuevas:**

- `center_arc_menu_test.dart` — abre con cuatro satélites; cierra por velo, por ✕ y por atrás;
  elegir dispara el callback **y** cierra; con `reduced` no escalona; un ítem deshabilitado no
  dispara.
- En el screen — se registra con el formulario visible; **no** se registra con la oferta ya enviada;
  se suelta al enviar; con 5 fotos los tres de foto quedan deshabilitados y "Mi tienda" no.

**Lo que los tests NO pueden firmar:** que las cuatro etiquetas quepan sin solaparse. En
`flutter test` el texto mide ~2× lo real — nos costó dos agentes y un ticket falso en la tanda A del
2026-08-02. **Eso se verifica en device o no se verifica.**

## Smoke en device (el único gate real)

1. Proveedor entra a una solicitud sin ofertar → el ＋ muestra "Cargar", no "Crear solicitud".
2. Tocarlo → arco de cuatro con la gota; el centro es ✕.
3. Cerrar por velo, por ✕ y por atrás del sistema.
4. Cada satélite hace lo mismo que su botón gemelo del formulario.
5. "Mi tienda" autocompleta y el formulario queda editable.
6. Llegar a 5 fotos → los tres de foto atenuados, "Mi tienda" vivo.
7. Enviar la oferta → aparece la tarjeta y el ＋ vuelve a "Crear solicitud" **en el mismo frame**.
8. Volver a entrar y editar en sitio → el menú vuelve.
9. **No regresión:** dentro de crear-solicitud el ＋ sigue siendo la cámara.
10. Con "reducir animaciones" del sistema activo, el arco aparece sin escalonar.
11. Las cuatro etiquetas caben en la pantalla más estrecha disponible.
