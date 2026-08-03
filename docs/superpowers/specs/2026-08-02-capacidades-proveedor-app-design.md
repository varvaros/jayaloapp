# Capacidades del proveedor y aviso de cotejo en la app (paridad B)

Fecha: 2026-08-02
Estado: aprobado por el PO, listo para plan de implementación

## El problema

La tanda A hizo que el proveedor **vea** lo que el cliente exige: comprobante fiscal, suplidor del
Estado, envío, instalación, evaluación previa. Verlo es la mitad. La otra mitad es que el proveedor
diga qué cumple, que se contraste, y que no envíe sin querer una oferta que se queda corta en algo
que el cliente marcó como condición.

Hoy la app no tiene dónde declarar nada de eso y no coteja nada. La web sí lo cerró el 2026-08-01.

## Alcance

Dentro:

- Completar el módulo puro de dominio con las capacidades de la oferta y el cotejo.
- Dos interruptores nuevos en el formulario de oferta: comprobante fiscal y suplidor del Estado.
- Prellenado desde lo que el negocio tenga declarado.
- Un aviso no bloqueante antes de enviar una oferta que no cubre lo que el cliente pidió.
- Los dos campos guardados en la oferta.

Fuera, **a propósito**:

- **Cualquier cambio de base de datos.** Las columnas y los grants ya existen (ver abajo).
- **Declarar las capacidades del NEGOCIO desde la app.** "Mi tienda" es solo lectura por diseño y
  editar el negocio va por magic link a la web (`EditorLinkClient`). Ahí es donde el proveedor
  declara sus capacidades, y ahí se queda. Construir una pantalla de edición en la app es otro
  trabajo, con su propio spec.
- **Que el CLIENTE vea lo que el proveedor declaró.** Igual que en la web, el dato se guarda y hoy
  no lo lee nadie. Es la mejora pendiente de más valor, y es la tanda siguiente, no esta.
- **Editar las dos casillas después de enviar la oferta.** Decisión ya tomada en la web y forzada
  por la base: son una foto del momento.

## Lo que ya existe y no hay que crear

Las migraciones de la web del 2026-08-01 y 2026-08-02 ya están aplicadas en producción y sirven a
los dos frentes:

| Tabla | Columnas | Permisos relevantes |
|---|---|---|
| `provider_businesses` | `has_fiscal_receipt`, `is_state_supplier` | `SELECT` para `anon` y `authenticated` (son sello público del negocio) |
| `provider_offers` | `has_fiscal_receipt`, `is_state_supplier` | `SELECT` e `INSERT` a nivel de tabla; **`UPDATE` denegado a propósito** |

**El `UPDATE` denegado es una decisión, no una carencia.** La migración lo dice: *"Estas dos se
fijan en el INSERT y NO se editan desde 'mejorar oferta', así que deliberadamente NO se agregan al
grant de UPDATE"*. Congelarlas deja constancia de qué afirmó el proveedor en el momento en que
compitió por el trabajo.

Aun así, el plan debe **verificar los grants contra `information_schema` antes de escribir código**.
Dar un grant por bueno desde el comentario de otra migración ya costó una migración de corrección en
la web, y dos revisiones no lo vieron.

## Decisiones del PO

1. **Se guardan en la oferta**, igual que la web, aunque hoy nadie lea el dato. Cuando alguien lo
   lea, estará ahí en lugar de faltar justo en las ofertas hechas desde la app.
2. **Prellenado espejo de la web, sin más**: se leen las capacidades del negocio, el proveedor puede
   ajustarlas para esa oferta. Se descartó añadir un enlace al editor web para declararlas de una
   vez — paridad exacta y cero piezas nuevas.
3. **En "mejorar oferta" se muestran apagadas, con una nota** de que quedaron fijadas al enviar. No
   se ocultan: un proveedor que se equivocó al marcar necesita ver qué declaró y por qué no lo puede
   tocar.

## Piezas

### Dominio: completar `app/lib/domain/request_requirements.dart`

El módulo de la tanda A dejó este hueco preparado a propósito. El campo `short` de las etiquetas se
escribió para esto y hoy no lo usa nadie.

- `class OfferCapabilities`, inmutable, con `offersShipping`, `offersInstallation`,
  `hasFiscalReceipt`, `isStateSupplier` (todos `bool`, default `false`).
- `const verifiableRequirements` — los cuatro cotejables, en orden canónico: envío, instalación,
  fiscal, Estado.
- `List<Requirement> unmetRequirements(RequestRequirements req, OfferCapabilities cap)` — los
  cotejables que el cliente pidió y esta oferta no cubre, en orden canónico. Nunca reporta
  evaluación ni capacidades que la oferta ofrece de más.
- `String unmetRequirementsMessage(List<Requirement> keys)` — arma la frase con los textos `short`:
  `""` con cero, `"envío"` con uno, `"envío y comprobante fiscal"` con dos,
  `"envío, comprobante fiscal y suplidor del Estado"` con tres o más.

**Por qué la evaluación queda fuera del cotejo**, escrito en el propio módulo: en la solicitud
significa "quiero que vengan a ver antes de cotizar"; en la oferta, "necesito ir a ver para poder
dar precio". Que el proveedor **no** la marque quiere decir que da precio en firme sin visita, que
favorece al cliente. Avisarlo como incumplimiento sería regañarlo por hacerlo bien.

Todo puro: sin Flutter y sin Supabase. Es la única parte de B con lógica real y la única que se
puede probar sin montar pantalla.

### Datos: `app/lib/data/repos.dart`

- **`myBusinessForOffer()`**, nueva. Devuelve el id del negocio y sus dos capacidades en una sola
  consulta. `myBusinessId()` **no se toca**: además del detalle lo llaman `session_state.dart`,
  `chat_screen.dart` y `settings_screen.dart`, que no necesitan estas columnas y no deben pagar el
  peso extra. El detalle pasa a usar la función nueva en sus dos sitios de llamada.
- **`makeOffer`** gana dos parámetros nuevos que viajan **solo en el `insert`**.

**El punto delicado de toda la tanda.** `_offerFields` es el mapa de payload que **comparten**
`makeOffer` y `updateOffer`. Si los dos campos nuevos entran ahí, el `UPDATE` los incluirá,
PostgREST tumbará **la fila entera** por falta de grant y **"mejorar oferta" dejará de funcionar del
todo** — el mismo modo de fallo que el bug de grants de la web. El diseño lo evita por construcción:
los campos se añaden en el `insert` de `makeOffer`, no en `_offerFields`, y queda un comentario
junto al mapa compartido explicando por qué no están ahí.

### Pantalla: `app/lib/features/provider/request_detail_screen.dart`

Dos interruptores nuevos: "Emito comprobante fiscal" y "Soy suplidor del Estado".

Van **fuera de `_productExtras`**. Ese bloque solo se pinta cuando la solicitud es de producto, y
estas dos capacidades son transversales, igual que los requisitos del cliente. Meterlas ahí las
haría invisibles en servicios, que es exactamente la trampa que en la web mordió dos veces con los
chips del detalle.

- **Al crear:** premarcados con lo que declare el negocio; el proveedor los ajusta para esa oferta.
- **Al editar:** apagados y no tocables, con una nota corta de que quedaron fijados al enviar la
  oferta.

### Aviso: un widget propio

El diálogo sale a su propio widget en `features/provider/`, que recibe la lista de requisitos sin
cubrir y devuelve si el proveedor quiere continuar. Así es testeable aislado, igual que se hizo con
los badges en la tanda A.

Contenido: título "El cliente pide algo que tu oferta no cubre"; una línea explicando que la
solicitud requiere `unmetRequirementsMessage(...)` y que no está marcado en la oferta; la lista de
lo que falta con la etiqueta y la explicación de cada uno; y dos salidas, **Editar** y **Enviar de
todos modos**.

El copy dice que *"quedará registrado en tu oferta que no lo cumples"*, no que el cliente lo verá:
hoy nadie lee ese dato y el texto no debe prometer lo que no ocurre.

## Flujo del envío

Al pulsar enviar, si `unmetRequirements` devuelve algo, se espera el diálogo **dentro del propio
manejador de enviar**:

- **Editar** → se cierra, la vista sube hasta los dos interruptores, no se envía nada.
- **Enviar de todos modos** → continúa el envío que ya estaba en marcha.

**Aquí el diseño se aparta de la web, a favor.** La web guarda un "ya lo acusé" en el estado del
componente y tiene que acordarse de reiniciarlo al cambiar de negocio; que ese acuse se quedara
pegado fue el único bug serio de aquella rama. Al esperar el diálogo dentro del manejador no hay
acuse que guardar, ni que reiniciar, ni que se pueda quedar pegado: la clase de bug entera
desaparece. La app además no tiene selector de negocio (`myBusinessId()` coge uno con `limit(1)`),
así que tampoco existe el disparador.

En modo edición el aviso **no salta**: las casillas están congeladas y no habría nada que corregir.

## Servicios

El formulario de oferta de la app no ofrece envío ni instalación en servicios, así que ahí esas dos
capacidades son siempre `false`. No genera falsos avisos: el formulario de **solicitud** tampoco
deja pedirlas en servicios (`submitRequest` las fuerza a `false`). Los dos lados coinciden, y en
servicios el cotejo se reduce a fiscal y Estado.

## Errores

- Si la lectura de las capacidades del negocio falla, las dos casillas arrancan apagadas.
  **Un fallo solo puede hacer que se avise de algo que el proveedor sí cumple** —lo marca y sigue—,
  **nunca que se afirme algo que no cumple.** Falla del lado seguro, que es el que protege al
  cliente.
- El resto del camino de envío no cambia. El barrido anti-elusión de contactos y la idempotencia del
  `23505` ya existen; dos booleanos no aportan modos de fallo nuevos.
- `unmetRequirements` no lanza: opera sobre dos objetos ya construidos y `requirementsFromRow` de la
  tanda A ya tolera claves ausentes y `null`.

## Pruebas

Nuevas:

- Módulo puro: sin requisitos no hay incumplimientos; con algunos, solo los que faltan; con todos,
  todos; la evaluación **nunca** se reporta aunque el cliente la pida y la oferta no la marque;
  ofrecer de más no cuenta como incumplimiento; y la frase con cero, uno, dos y tres elementos.
- Widget del aviso: pinta la etiqueta y la explicación de cada requisito sin cubrir, en orden
  canónico; **Editar** y **Enviar de todos modos** devuelven valores distintos.

## Lo que se verifica en device, no en la suite

`request_detail_screen.dart` (1654 líneas) sigue sin costura de tests: carga con `requestById`
directo en `initState`, sin fuente inyectable. B **no la abre** — refactorizarla cambiaría el riesgo
del trabajo sin cambiar lo que ve el usuario.

Queda en device: el prellenado desde el negocio, los interruptores apagados con su nota en modo
edición, que el aviso salte al enviar y que "Editar" lleve a los interruptores, y —lo más
importante— **que "mejorar oferta" siga funcionando**, que es lo que se rompería si los dos campos
se colaran en el payload compartido.

## Relación con A y con C

Consume el módulo `domain/request_requirements.dart` que creó A y lo completa. No cambia nada de lo
que A dejó funcionando.

Lo que queda para después: que el cliente vea, en la oferta que recibe, qué declaró el proveedor.
Es lo que convertiría este dato de solo escritura en información útil, y es la mejora de más valor
pendiente en los dos frentes.
