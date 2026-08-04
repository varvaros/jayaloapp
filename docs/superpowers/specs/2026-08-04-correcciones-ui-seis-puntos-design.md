# Seis correcciones de UI — oferta, mayoreo, registro y cotejo

Fecha: 2026-08-04
Estado: aprobado por el PO, sin implementar

Seis correcciones pedidas por el PO en una sola tanda. Tocan las dos
superficies (app Flutter y web) salvo donde se indique. No hay hilo conductor
entre ellas más allá de que todas son visuales o de validación de formulario:
cada punto es independiente y puede implementarse y verificarse por separado.

## Alcance y decisiones tomadas

Decisiones del PO en el brainstorming, para que nadie las vuelva a litigar:

1. El selector de país/provincia/sector se **porta a la app**. En la web ya
   existe y funciona; no se toca.
2. Los otros cinco puntos van en **las dos superficies**.
3. «Nuevo/Usado» se **recupera del mensaje** al editar, sin migración de base
   de datos.
4. La tarjeta de mayoreo es la **variante A**: el rótulo «Al por mayor» es el
   encabezado de la tarjeta, no un chip aparte.
5. El verde/gris del cotejo en la web se aplica **sobre la rama
   `feat/cotejo-visible-cliente`**, donde vive el componente.

Fuera de alcance: la vista del cliente de sus propias solicitudes (el punto 3
es explícitamente «lo que ve el proveedor»), y el smoke pendiente de
`feat/cotejo-visible-cliente`, que es deuda de aquella tanda y no de esta.

## Punto 1 — Selector de cobertura en el alta de proveedor (solo app)

### Situación

`features/onboarding/provider_onboarding_screen.dart:643`, sección «Dónde
trabajas», pide Ciudad y Sector como texto libre con chips (`_chipField`) y
fija el país a `'República Dominicana'` al guardar (`:383`). La web, en
`src/components/provider/ProviderSignupWizard.tsx:1682`, tiene una cascada
país → provincia → sector con multi-selección en cada nivel y una opción
«🗺️ Todos los sectores» que selecciona el conjunto completo.

Los datos ya están portados: `domain/locations.dart` es un port 1:1 de
`src/mocks/locations.ts`, con `kLocations`, `kCountries`, `citiesFor(country)`
y `sectorsFor(country, city)`. **Este punto no necesita datos nuevos, solo
UI.**

### Diseño

Widget nuevo `LocationCoveragePicker` en `features/shared/`, público y sin
dependencias de la pantalla que lo monta — mismo criterio de aislamiento que
`OfferRequirementCoverage`, para que un test de widget pueda montarlo sin
arrastrar el onboarding entero.

Interfaz:

- Entrada: valores actuales (`country`, `cities`, `sectors`).
- Salida: un callback por cambio con los tres valores.
- No hace red, no lee sesión, no guarda nada.

Comportamiento:

- **País**: selección única. Se dibuja aunque `kCountries` tenga un solo
  elemento, por paridad con la web y porque el catálogo puede crecer.
- **Provincia**: multi-selección sobre `citiesFor(country)`.
- **Sector**: multi-selección sobre la **unión** de `sectorsFor(country, c)`
  de todas las provincias elegidas, sin duplicados y en el orden del
  catálogo. Si no hay provincia elegida, la lista va vacía y el control se
  muestra deshabilitado.
- «🗺️ Todos los sectores» encabeza la lista de sectores cuando hay al menos
  uno disponible. Elegirla selecciona todos los sectores visibles.
- Debajo de cada nivel, chips removibles con lo seleccionado. Cuando hay más
  de un sector disponible y están **todos** seleccionados, se dibuja un solo
  chip «🗺️ Todos los sectores» en vez de la lista completa — igual que la web
  en `ProviderSignupWizard.tsx:1704`.
- Cambiar de país limpia provincias y sectores. Quitar una provincia elimina
  también los sectores que solo pertenecían a ella.

Integración en el onboarding:

- Reemplaza los dos `_chipField` de Ciudad y Sector. `_cityInput` y
  `_sectorInput` desaparecen (y salen de la lista de `dispose` en `:123`).
- El guardado **no cambia**: `_cities.join(', ')` y `_sectors.join(', ')` ya
  es lo que hace hoy `:384-386`, y coincide con la web.
- El campo libre «Dirección (opcional)» se queda como está.
- Se mantiene el nivel de obligatoriedad actual: sector sigue siendo
  opcional. La web lo marca con asterisco, pero endurecer la validación del
  alta no es lo que se pidió y arriesga bloquear altas que hoy pasan.

### El caso «Parque del Este»

«Usar mi ubicación» (`_useLocation`, `:270-308`) geocodifica y hoy vuelca los
textos crudos en los chips. Con un catálogo cerrado, un sector real que no
esté en `kLocations` — el caso conocido «Parque del Este» — se perdería en
silencio.

Regla: si el valor geocodificado coincide con el catálogo, se preselecciona.
Si no coincide, **se añade como opción extra de esa sesión y se selecciona**,
en vez de descartarlo. El proveedor no pierde el dato y el catálogo no miente
sobre lo que contiene. Estos valores extra no se persisten en el catálogo:
viajan al perfil como cualquier otro sector, dentro del `join(', ')`.

### Pruebas

Test de widget sobre `LocationCoveragePicker` aislado: unión de sectores al
elegir dos provincias, «Todos los sectores» seleccionando el conjunto, el
chip colapsado cuando están todos, la limpieza en cascada al cambiar de país,
y el sector fuera de catálogo que sobrevive.

Cuidado conocido: en `flutter test` el texto mide alrededor del doble de lo
real. No escribir aserciones que dependan de anchos o de que algo «quepa».

## Punto 2 — Borde violeta en el precio

### App

`features/provider/request_detail_screen.dart`, `_pricingFields` (`:1096`).
Se envuelve **todo el bloque** en un contenedor con borde violeta de marca,
radio 16, relleno interior y fondo apenas teñido. «Todo el bloque» incluye el
`PillSegmented` del modo, porque elegir «Rango» o «Por hora» es parte de
decir el precio.

Cubre las dos ramas sin duplicar el envoltorio:

- Producto: `Precio fijo` / `Rango`.
- Servicio: `Fijo` / `Rango` / `Por hora` / `A evaluar`, incluido el aviso de
  «a evaluar» de `_svcModeFields` (`:1146-1159`), que hoy ya tiene su propio
  contenedor gris. Ese contenedor interior se queda: es un aviso dentro del
  bloque, no un competidor del borde.

El violeta sale del `brand_kit`, no de un `Color(0x…)` suelto — el fichero
dice explícitamente que no se pinten estados con colores crudos.

### Web

Mismo tratamiento en el bloque de precio de
`src/components/provider/RequestRespondSection.tsx`, con el token de
`primary` que ya usa el resto del formulario.

## Punto 3 — «Al por mayor» y su tarjeta (variante A)

### Situación

App, `request_detail_screen.dart`:

- `:1538-1547` — chip «Al por mayor» pequeño, junto al título, como identidad
  de la solicitud.
- `:1582-1603` — cantidad, división, empaque y detalle como cuatro `Text`
  planos de 13pt, bajo el encabezado «Información».

Web, `RequestRespondSection.tsx:1227-1243` — la misma estructura: un `span`
con el rótulo y cuatro `<p>` sueltos.

### Diseño

Una tarjeta única de mayoreo, colocada donde hoy está el chip (con el título,
en el bloque de identidad), que absorbe rótulo y datos:

- Encabezado: ícono de tienda a 19pt y «Al por mayor» a 16pt en violeta —
  frente a los ~11pt del chip actual. Este es el «más grande» que se pidió.
- Cuerpo: filas etiqueta/valor para Cantidad, División y Empaque. Etiqueta
  apagada a la izquierda, valor en peso medio a la derecha. Cada fila solo se
  dibuja si su dato existe, como hoy.
- Pie: «Detalle», separado por una línea, como párrafo a ancho completo — es
  texto libre del cliente y no cabe en una fila de dos columnas.
- Fondo teñido de violeta suave, radio 12. Sin el chip suelto: el encabezado
  de la tarjeta lo sustituye.

Se extrae como widget propio (`WholesaleCard`) por la misma razón de
aislamiento que el resto: `request_detail_screen.dart` ya tiene 1856 líneas.

### Efecto secundario que hay que atar

`_hasInfo` (`:1201`) decide si se dibuja el encabezado «Información», y hoy
devuelve `true` cuando `is_wholesale` es cierto. Al sacar los datos de
mayoreo de esa sección, **`_hasInfo` debe dejar de mirar `is_wholesale`** o
una solicitud de mayoreo sin bullets y sin presupuesto dejará «INFORMACIÓN»
flotando sobre un divisor — exactamente el bug que se cazó en device el
2026-08-01 y que el propio comentario de `:1574-1579` documenta.

Test de regresión: solicitud con `is_wholesale = true`, sin bullets y sin
presupuesto, no dibuja el encabezado «Información».

### Web

La misma tarjeta en `RequestRespondSection.tsx`, con los mismos rótulos y el
mismo orden. `wholesaleSplitLabel` y `wholesalePackagingLabel` ya existen en
`@/lib/wholesale` y se siguen usando.

## Punto 4 — Aviso al salir descartando la oferta

### El obstáculo

`features/shell/back_guard.dart` envuelve **cada** pantalla del shell con
`PopScope(canPop: false)` e intercepta todo el atrás del sistema, incluido el
predictive back de Android 13+. Su comentario de cabecera explica por qué
tiene que estar dentro del navigator anidado y qué pasa si se mueve. Un
`PopScope` propio de la pantalla de oferta competiría con él.

Además hay un segundo camino de salida: la flecha flotante `_backButton`
(`:1839`), que llama a `context.pop()` directo sin pasar por `BackGuard`.

### Diseño

Un registro a nivel de módulo, `unsavedOfferGuard`, siguiendo el patrón que
el repo ya usa para estado compartido de navegación (`roleStore`,
`homeScrollController`).

El registro guarda **una función, no un booleano**: `bool Function()?`. La
suciedad se calcula en el momento de salir, no se mantiene al día con
listeners sobre cada `TextEditingController` — son once controladores y
mantenerlos sincronizados es una fuente de bugs sin ninguna ventaja, porque
el valor solo hace falta una vez, cuando alguien intenta irse.

- El formulario de oferta registra su función al montarse y la quita en
  `dispose`. También la quita tras enviar con éxito, para que la navegación
  posterior al envío no pregunte nada.
- `BackGuard._handleBack` la consulta **antes** de resolver su `BackAction`.
  Si devuelve `true`, muestra el diálogo; solo si el usuario confirma, sigue
  con la acción que tocaba.
- `_backButton` la consulta igual antes de su `context.pop()`.

El formulario de oferta vive en un único sitio (`request_detail_screen.dart`);
`product_interest_detail_screen.dart` no tiene formulario propio, así que no
hay un segundo registrante que coordinar.

«Sucio» significa: en oferta nueva, cualquier campo del formulario con
contenido; en edición, cualquier campo que difiera de lo que dejó
`_prefillFromOffer`. La comparación se hace contra una instantánea tomada
justo después del prellenado, no contra valores vacíos, o editar sin tocar
nada pediría confirmación.

Diálogo:

- Título: «¿Salir y descartar los cambios?»
- Cuerpo: «Perderás lo que escribiste en esta oferta.»
- Acciones: «Seguir editando» (por defecto) y «Salir y descartar», esta
  última en el color de error.

No se dispara si no se tocó nada, ni después de un envío correcto, ni cuando
el propio código navega tras guardar.

### Web

`useBlocker` de `@tanstack/react-router` (v1.170.17, disponible) para la
navegación interna, más un `beforeunload` para cerrar o recargar la pestaña.
Misma condición de «sucio» y mismo texto.

## Punto 5 — «Nuevo o usado» y garantía obligatorios

### App

Los dos campos son **solo de producto**: en servicio ni siquiera se envían
(`:570-572` los condicionan con `isService ? '' : …`). La obligatoriedad
aplica únicamente a la rama de producto.

- `_productDetails` (`:1289`): el encabezado deja de decir «(opcional)» y
  «Estado» y «Garantía» se marcan como requeridos.
- Validación en `_submit`, después de la validación de precio (`:517-534`) y
  antes del cotejo de requisitos, solo si no es servicio:
  - `_condition` vacío → «Elige si el producto es nuevo o usado.»
  - `_warranty.text` vacío → «Elige la garantía.»
- `_warrantyPresets` (`:51`) ya incluye `'Sin garantía'`, así que exigir el
  campo no obliga a nadie a prometer garantía. Esto es lo que hace la regla
  aceptable; si el preset no existiera, habría que crearlo.

### Recuperar «Nuevo/Usado» al editar

Hoy `_prefillFromOffer` no lo restaura y su comentario (`:240`) lo dice: la
condición no tiene columna en `provider_offers`, viaja dentro del mensaje.
Con el campo obligatorio, editar una oferta obligaría a volver a marcarlo en
cada pasada.

`composeOfferMessage` (`domain/offer_message.dart:29`) añade la condición
como una parte propia con la forma exacta `Estado: <valor>`. El inverso es
directo y estable:

- Función pura nueva `conditionFromOfferMessage(String message)` en el mismo
  módulo, junto a su compositora — es el único sitio que conoce el formato.
- Devuelve `'Nuevo'`, `'Usado'` o cadena vacía.
- `_prefillFromOffer` la usa para poblar `_condition`.
- Si no reconoce nada, devuelve vacío y el proveedor elige — es decir, el
  peor caso degrada exactamente al comportamiento de hoy, nunca a un valor
  inventado.

Prueba unitaria de ida y vuelta: componer con `'Nuevo'` y con `'Usado'`,
parsear de vuelta y comparar; más un mensaje sin condición y un mensaje que
mencione «Estado» dentro del texto libre del proveedor.

### Web

Aquí hay más trabajo del que sugiere el enunciado, porque la web parte de
otro sitio:

- **El campo «Nuevo/Usado» no existe** en el formulario de oferta. Lo que se
  ve en `RequestRespondSection.tsx:1246` es la condición que pidió el
  *cliente*, mostrada en la ficha de la solicitud — no lo que ofrece el
  proveedor. Hay que **añadir el campo**, con las mismas dos opciones que la
  app, y componerlo en el mensaje igual que allá.
- **La garantía es hoy opcional por diseño**: vive en el grupo `activeDetails`
  (`:367-372`), un conjunto de detalles que el proveedor activa a voluntad, y
  su validación actual (`:893`) es «indica la garantía **o desactiva esa
  opción**». Hay que sacarla del grupo opt-in, dibujarla siempre en ofertas
  de producto y exigirla.

Ambos cambios son solo de producto, como en la app.

### La web todavía tiene caja de texto libre

Hallazgo al escribir el plan, que afecta a cómo viaja la condición: la app
compone el `message` de la oferta **entero** desde datos estructurados, pero
la web lo toma de una caja de comentario libre —
`const finalMessage = comment.trim()` (`:964`) y su gemela en `:1074`. El
resto de detalles del producto (marca, color, garantía) sí van en columnas
propias; la condición es el único sin columna en las dos superficies.

Tres consecuencias:

1. En la web la condición se **antepone** al comentario con el formato exacto
   de la app (`Estado: Nuevo · resto`), o `conditionFromOfferMessage` no la
   reconocerá al editar esa oferta desde la app.
2. Al editar en la web hay que **separar** las dos mitades antes de devolver
   el texto a la caja, o cada edición acumula otra copia de `Estado: …`.
3. El parser de la app tiene que ser conservador, porque el texto libre de un
   proveedor de la web acaba en la misma columna. Lo es: exige el prefijo
   exacto sobre una parte completa y solo acepta `Nuevo` o `Usado`.

Aparte de esto, la caja libre es una divergencia con la decisión PO del
2026-07-20, que la quitó de la app para no invitar al proveedor a dejar su
teléfono y saltarse el desbloqueo pagado. En la web sigue ahí. El trigger
`enforce_no_contact_info` (JY422) la vigila a nivel de base de datos, así que
el agujero no está abierto — pero la paridad no está, y **eso no se decide en
esta tanda**: queda anotado para el PO.

## Punto 6 — Verde y gris en el cotejo

### App

`features/client/offer_requirement_coverage.dart` pinta hoy los dos estados
en `onSurfaceVariant`, y el comentario de `:44-46` documenta que el tono
neutro en el negativo fue una decisión del PO. **Esa decisión queda revertida
por esta tanda** y el comentario se reescribe para reflejarlo; dejarlo como
está haría que la próxima revisión lo «arreglara» de vuelta.

- Cumplido: ícono y texto en `JayaloColors.success` / `dSuccess` según el
  brillo del tema.
- No cumplido: se queda en `onSurfaceVariant`.
- El encabezado «Tus condiciones» sigue apagado.
- Los íconos ya se diferencian (`check_circle_outline` contra
  `remove_circle_outline`), así que el estado no depende solo del color.

`test/offer_requirement_coverage_test.dart` se actualiza para verificar el
color de cada estado en tema claro y oscuro.

### Web

El componente `src/components/marketplace/OfferRequirementCoverage.tsx`
**solo existe en la rama `feat/cotejo-visible-cliente`**, sin mergear. Por
decisión del PO, el verde/gris se aplica sobre esa rama, para que viaje junto
al componente. Los otros cuatro puntos de la web van en la rama de esta
tanda.

Consecuencia asumida: hasta que esa rama se integre, el verde/gris solo se ve
en la app. Y esa rama sigue debiendo su smoke, que es deuda previa.

## Ramas y estado de los repositorios

- **App** (`C:\Users\ac\Downloads\jayalo-app`): rama
  `feat/detalle-cliente-plegable`, árbol limpio. La tanda parte de ahí.
- **Web** (`C:\Users\ac\Downloads\jayalo-main\jayalo-main`): rama
  `feat/direccion-precisa`, **árbol sucio con trabajo de otra sesión** —
  `src/integrations/supabase/types.ts` modificado, una migración sin
  seguimiento y varios ficheros sueltos. Nada de eso pertenece a esta tanda y
  **no debe commitearse aquí**: los commits de esta tanda se hacen por
  fichero, nunca con `git add -A`.
- El punto 6 de la web es la única excepción de rama: va sobre
  `feat/cotejo-visible-cliente`.

## Verificación

Los tests automáticos cubren la lógica pura y los widgets aislados, pero
**ningún test cubre lo que este trabajo realmente cambia**, que es lo que se
ve en pantalla y el cableado entre pantallas. En particular, el punto 4
depende de `BackGuard`, cuyo comportamiento real en Android 13+ ya se
comprobó una vez que no se puede deducir del código.

El gate real de esta tanda es un smoke en device, con guion escrito, que
recorra: alta de proveedor con la cascada de ubicación, formulario de oferta
de producto (borde violeta, los dos campos obligatorios, el aviso al salir
por los dos caminos de salida), detalle de una solicitud de mayoreo, edición
de una oferta ya enviada (que «Nuevo/Usado» vuelva marcado) y la tarjeta de
oferta del cliente con condiciones cumplidas e incumplidas.

En la web, el equivalente por navegador sobre las mismas cinco pantallas.
