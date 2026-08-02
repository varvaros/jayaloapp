# Requisitos de la solicitud visibles en la app (paridad A)

Fecha: 2026-08-02
Estado: aprobado por el PO, listo para plan de implementación

## El problema

El cliente marca en la app que necesita comprobante fiscal, un suplidor del Estado, envío,
instalación o evaluación previa. Los cinco flags **se guardan bien**: `create_request_screen.dart`
los recoge y `submitRequest` los escribe en `customer_requests`.

Nadie los vuelve a leer. `requestById`, `allOpenRequests`, `_fetchMyRequests` y el `select` del
detalle del cliente no incluyen esas columnas, y la RPC `get_provider_inbox_unified` devuelve una
forma fija de trece columnas que tampoco las trae. El resultado es que el proveedor oferta sin
saber que le están pidiendo un NCF, y el cliente no tiene forma de confirmar que lo que marcó
quedó registrado.

Es el mismo fallo que la web tuvo hasta el 2026-08-01 y que se cerró allí (rama
`feat/requisitos-solicitud`, mergeada en `b96b363`). Este documento porta esa mitad —**mostrar los
requisitos**— a la app Flutter.

## Alcance

Dentro:

- Un módulo puro de dominio con los requisitos y sus etiquetas.
- Un widget de badges con dos variantes (símbolos para listados, chips para detalles).
- Un tono teal nuevo en la paleta.
- Las seis superficies que muestran una solicitud.
- Las lecturas de datos que hoy no traen los flags.

Fuera, **a propósito**:

- Declarar capacidades del proveedor, cotejarlas contra los requisitos y avisar antes de enviar
  la oferta. Eso es la tanda B y se construye encima de este módulo.
- Cualquier cambio de base de datos. Ni migraciones, ni tocar la RPC del inbox.
- `unmetRequirements` y `OfferCapabilities` en el módulo puro. Los necesita B; escribirlos ahora
  sería código muerto.

## Decisiones del PO

1. **Todas las superficies**, no solo las del proveedor. El cliente también ve sus requisitos en
   su propia solicitud y en el listado.
2. **Teal propio**, derivado del token `--requisito` de la web. Ni gris (se pierde justo donde
   queremos que el proveedor mire) ni ámbar (en esta app el ámbar ya significa dinero o espera:
   "Ya ofertaste", el costo del desbloqueo, la wallet).
3. **La pestaña "Para ti" se alimenta con una query extra en la oleada B**, no extendiendo la RPC.
   Ver "Por qué no se toca la RPC".

## Piezas nuevas

### `app/lib/domain/request_requirements.dart`

Módulo puro, espejo de `src/lib/requestRequirements.ts` de la web. Sin Flutter y sin Supabase, para
que la lógica se pueda probar sin montar ninguna pantalla.

- `enum Requirement { shipping, installation, evaluation, fiscal, state }` — la declaración fija el
  orden canónico, que respetan chips y símbolos.
- `RequestRequirements`, inmutable, con los cinco booleanos.
- `requirementsFromRow(Map<String, dynamic> row)` — mapea una fila de `customer_requests`. Tolera
  la clave ausente y el `null`; ambos son "no lo pide".
- `activeRequirements(RequestRequirements req, {Iterable<Requirement> keys})` — los activos en
  orden canónico, acotables a un subconjunto.
- `requirementLabel(Requirement)` — devuelve `(chip, short, hint)`. Los textos se copian
  **literalmente** de `REQUIREMENT_LABEL` de la web, para que el mismo requisito se lea igual en
  los dos frentes.

Los textos, tal como quedan:

| clave | chip | short | hint |
|---|---|---|---|
| `shipping` | Requiere envío | envío | El cliente necesita que le lleven el producto. |
| `installation` | Requiere instalación | instalación | El cliente necesita que se lo instalen. |
| `evaluation` | Requiere evaluación previa | evaluación previa | El cliente pide una visita para cotizar antes. |
| `fiscal` | Requiere comprobante fiscal | comprobante fiscal | El proveedor debe poder emitir comprobante fiscal (NCF). |
| `state` | Requiere suplidor del Estado | suplidor del Estado | El proveedor debe estar registrado como suplidor del Estado. |

`short` no se usa en A. Se incluye porque es el texto que arma el aviso de B
("envío, comprobante fiscal y suplidor del Estado") y separarlo de sus hermanos invitaría a que
B lo redacte distinto.

### `app/lib/features/shared/request_requirement_badges.dart`

Un widget, dos variantes, elegidas por un enum `RequirementBadgeVariant`:

- `symbols` — círculo teal de 20 px con el ícono a 12 px (las mismas proporciones que la web:
  `h-5 w-5` con `h-3 w-3`). Para las tarjetas de listado. Se insertan en el `Wrap` que ya existe
  junto a la hora, al lado de "1 oferta" y "Ya ofertaste".
- `chips` — píldora teal con ícono y texto completo (`chip`), con la geometría de `StatusChip`
  (radio 99, padding 10/4, texto 12 w600). Para los detalles.

Sin requisitos activos no dibuja nada: devuelve `SizedBox.shrink()`, para que quien lo use no
tenga que envolverlo en un condicional ni le quede un `SizedBox(height: 8)` colgando.

Íconos, equivalentes Material de los que usa la web:

| clave | web (lucide) | app (Material) |
|---|---|---|
| `shipping` | `Truck` | `Icons.local_shipping_outlined` |
| `installation` | `Wrench` | `Icons.handyman_outlined` |
| `evaluation` | `ClipboardCheck` | `Icons.fact_check_outlined` |
| `fiscal` | `ReceiptText` | `Icons.receipt_long_outlined` |
| `state` | `Landmark` | `Icons.account_balance_outlined` |

### `JayaloStatus.requisitoLight` / `requisitoDark`

En `app/lib/core/brand.dart`, junto a los demás tonos de estado. Portan los cuatro valores del
token `--requisito` de `src/styles.css` (`oklch(0.94 0.06 200)` y su tinta; en oscuro
`oklch(0.3 0.07 200)`).

| | fondo | tinta |
|---|---|---|
| claro | `0xFFBCF8FB` | `0xFF005961` |
| oscuro | `0xFF00383C` | `0xFF6FEAF1` |

Los hex no son aproximaciones: salen de convertir oklch a sRGB con la misma fórmula, calibrada
contra un token que la app ya tiene. `--status-pending` (`oklch(0.96 0.02 80)` /
`oklch(0.45 0.05 80)`) da `#F9F1E3` / `#645235`, que es exactamente el `pendingLight` que ya
está en `brand.dart`.

## Superficies y de dónde sale el dato

| Pantalla | Archivo | Variante | Fuente |
|---|---|---|---|
| Bandeja del proveedor, "Para ti" y "Todas" | `features/provider/inbox_screen.dart` (`_InboxCard`) | símbolos | oleada B de `loadInboxData` |
| Detalle del proveedor | `features/provider/request_detail_screen.dart` | chips | `requestById` |
| Detalle de solicitud de otro | `features/client/other_request_screen.dart` | chips | `requestById` |
| Detalle de mi solicitud | `features/client/request_detail_sheet.dart` (`RequestDetailSheet`) | chips | `select` de `request_status_screen.dart` |
| "Mis solicitudes", listado | `features/client/my_requests_screen.dart` (`_RequestCard`) | símbolos | `_fetchMyRequests` |
| "De otros", listado | `features/client/my_requests_screen.dart` (`_OtherRequestCard`) | símbolos | `allOpenRequests` |

En los tres detalles los chips van bajo el título y bajo el chip "Al por mayor" cuando lo haya:
son identidad de la solicitud, no "información" (mismo criterio que el PO fijó el 2026-08-01 al
reordenar el detalle del proveedor). Las tres pantallas ya tienen ahí exactamente esa estructura
—título, luego un `StatusChip` opcional—, así que el bloque entra en el mismo sitio en las tres.

## Cambios en las lecturas

En `app/lib/data/repos.dart`, una constante agrupa las cinco columnas para que no se separen nunca:

```dart
const requestRequirementCols =
    'with_shipping,with_installation,requires_evaluation,'
    'requires_fiscal_receipt,requires_state_supplier';
```

La usan cuatro lecturas:

- `requestById` — sirve al detalle del proveedor y a `OtherRequestScreen`.
- `allOpenRequests` — sirve a la pestaña "De otros" del listado del cliente.
- `_fetchMyRequests` — sirve al listado "Mis solicitudes".
- el `select` de `request_status_screen.dart` — sirve a `RequestDetailSheet`.

Y una función nueva para la oleada B:

```dart
Future<Map<String, RequestRequirements>> requirementsForRequests(List<String> ids)
```

Devuelve mapa vacío con lista vacía, sin viajar a la red.

`myOfferedOpenRequests` **no** cambia. Sus filas se mezclan en "Para ti" y la oleada B las cubre.

### Grants

Las cinco columnas ya tienen `GRANT SELECT`: la web las lee en producción y se verificó en vivo sin
sesión el 2026-08-02. Aun así el plan incluye una consulta a `information_schema.role_column_grants`
antes de tocar código, porque dar un grant por bueno desde un comentario ya costó una migración de
corrección en la web y dos revisiones no lo vieron.

## La bandeja: una oleada B con tres llamadas

`domain/inbox_load.dart` ya orquesta la carga en dos oleadas concurrentes: la A trae las filas, la
B pide estados y conteos por ids. La tercera llamada entra en la B.

- `loadInboxData` gana un parámetro `fetchRequirements`.
- `InboxData` gana un campo `requirements`.
- Solo se piden los ids de filas `source != 'store'`: un interés de producto no tiene requisitos.
- Best-effort, igual que estados y conteos: si falla, mapa vacío y la bandeja se pinta igual. Lo
  único que propaga es el fallo de `fetchItems`.

La oleada B pide para **todas** las filas marketplace, incluidas las de "Todas" que ya llegan con
las columnas por `allOpenRequests`. Es una query redundante en esa pestaña, y se acepta: corre en
paralelo con las otras dos, así que no cuesta latencia, y evita partir la bandeja en dos caminos.

La tarjeta resuelve los requisitos como `requirements[id] ?? requirementsFromRow(fila)`: la oleada
B manda, y si no hay entrada cae a la propia fila. Las dos fuentes leen las mismas cinco columnas,
así que no pueden discrepar. Esto no es solo cinturón y tirantes: **sin el respaldo de la fila la
tarjeta no se podría probar**. `requirementsForRequests` toca `supa` y revienta sin Supabase
inicializado, y `loadInboxData` se traga ese fallo por diseño (best-effort), así que en un test de
widget la oleada B siempre devuelve vacío. Con el respaldo, un test inyecta una fila con
`with_shipping: true` por `fetch` y la tarjeta pinta su símbolo sin red de por medio.

### Por qué no se toca la RPC

`get_provider_inbox_unified` tiene una forma fija de trece columnas. Añadirle cinco obliga a
`DROP FUNCTION` y `CREATE`, y el `DROP` borra los grants, así que habría que re-otorgarlos en la
misma migración. Además **esa RPC la comparte la web** (`ProviderInboxSection.tsx`): un error ahí
tumba el inbox del proveedor en los dos frentes a la vez.

La opción A se eligió por lanzarse sola, sin tocar la base de datos. Extender la RPC la convertiría
justo en lo que se quería evitar.

## Divergencia deliberada con la web: evaluación

La web excluye `evaluation` de los chips del detalle y solo la muestra en los símbolos del listado.
La razón está escrita en `requestRequirements.ts`: en el detalle de la web ese requisito ya tiene
su propio chip ámbar, así que repetirlo sobraría.

**La app no tiene ese chip.** Hoy `requestById` ni siquiera selecciona `requires_evaluation`, y
`_requiresEvaluation` en `request_detail_screen.dart` es un campo de la oferta del proveedor, no del
requisito del cliente. Si se copia la exclusión, "requiere evaluación previa" queda invisible en los
tres detalles.

Por eso en la app **los chips del detalle llevan los cinco**. La razón queda escrita en el módulo
puro: la exclusión de la web es una consecuencia de su layout, no una regla del dominio. Los
símbolos del listado llevan los cinco en ambos frentes, sin diferencia.

## Errores

Presentación best-effort de punta a punta.

- `requirementsFromRow` no lanza nunca: todos los campos son opcionales y se leen con `== true`.
  Columna ausente, `null` o tipo inesperado son todos "no lo pide".
- Si `requirementsForRequests` falla, la bandeja se pinta sin símbolos.
- Si un `select` de detalle falla, ya falla hoy por otras columnas; el comportamiento no cambia.

Ninguna decisión de dinero depende de estos flags en A. El cotejo contra las capacidades del
proveedor —lo único que puede bloquear o avisar antes de enviar una oferta— es B.

## Pruebas

Nuevas:

- `test/domain/request_requirements_test.dart` — clave ausente, `null` y `false` dan lo mismo;
  orden canónico con todos activos y con un subconjunto salteado; `activeRequirements` acotado a un
  subconjunto no devuelve nada fuera de él; las cinco etiquetas tienen los tres textos.
- `test/request_requirement_badges_test.dart` — cero requisitos no dibuja nada; cinco activos dan
  cinco íconos en orden canónico; `chips` muestra el texto de `chip` y `symbols` no muestra texto;
  el tono cambia entre claro y oscuro.

Extendidas:

- `test/inbox_load_test.dart` — la nueva llamada corre en la oleada B junto a estados y conteos, no
  después; solo recibe ids marketplace; si falla, `loadInboxData` completa igual con `requirements`
  vacío.
- `test/inbox_screen_test.dart` — la tarjeta pinta los símbolos de una fila con requisitos.
- `test/client_request_detail_sheet_test.dart` — chips en el detalle propio.
- `test/other_request_screen_test.dart` — chips en el detalle de otro (ya inyecta `fetch`).
- `test/my_requests_others_test.dart` — símbolos en las tarjetas del listado.

## El hueco que se deja a propósito

`request_detail_screen.dart` son 1654 líneas sin costura de tests: la pantalla carga con
`requestById` directo en `initState`, sin fuente inyectable. Se prueba el widget de badges de forma
aislada; su cableado dentro de esa pantalla se verifica en device, como todo lo demás de ese
archivo. Abrir la refactorización de ese archivo dentro de esta tarea cambiaría el riesgo del
trabajo sin cambiar lo que el usuario ve.

## Verificación en device

Un APK de debug no se instala encima de un release, así que el smoke va sobre una instalación
limpia. Lo que hay que ver:

1. Crear una solicitud marcando comprobante fiscal y suplidor del Estado, y confirmar los chips en
   el detalle propio.
2. Con sesión de proveedor, esa solicitud en "Para ti" con sus dos símbolos, y sus chips al entrar
   al detalle.
3. Una solicitud de producto con envío, instalación y evaluación: los tres símbolos en el listado y
   los tres chips en el detalle (esta es la que verifica la divergencia con la web).
4. Una solicitud sin ningún requisito: ni símbolos ni chips ni hueco vertical de más.
5. Modo oscuro en las seis superficies.

## Relación con B y C

`request_requirements.dart` es la base de B: declarar capacidades del proveedor, cotejarlas contra
los requisitos de la solicitud y avisar antes de enviar la oferta. B añadirá a ese mismo módulo
`OfferCapabilities`, `unmetRequirements` y el armado del mensaje con `short`, y ahí sí habrá
columnas nuevas en `provider_businesses` y `provider_offers`. A no adelanta nada de eso.
