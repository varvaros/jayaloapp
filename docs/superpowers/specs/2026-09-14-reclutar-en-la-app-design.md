# Reclutar desde el teléfono: el listado de solicitudes del admin, con compartir

**Fecha:** 2026-09-14
**Estado:** aprobado por el PO (2026-09-14)
**Repos:** `jayalo-app` (la pantalla) y `jayalo-main` (una migración)

## Por qué

El 2026-09-14 se desplegó en la web el circuito de reclutamiento del admin
(`/admin/requests` con el chip «Sin proveedor», el filtro de cobertura, el botón
de compartir por WhatsApp y el alta rápida). El caso de uso real es **de pie, en
una reunión o en la calle**: ver qué solicitud no tiene a nadie que la cubra y
ofrecérsela por WhatsApp a un proveedor que todavía no está en Jayalo.

Ese caso de uso ocurre en el teléfono, y hoy en el teléfono no existe: el único
admin de la app es `/admin/quick-register`.

Medido el 2026-09-14 en producción: **27 de 41 solicitudes abiertas no tienen ni
un proveedor** al que les toque.

## Qué se construye

Una pantalla, `/admin/recruit`, que hace exactamente dos cosas: **enseñar las
solicitudes abiertas marcando cuáles están sin proveedor**, y **compartir una por
WhatsApp**.

### Decisiones del PO (2026-09-14)

| Decisión | Elegido | Qué se descartó |
|---|---|---|
| Alcance | Solo reclutar | La paridad con la web (borrar, marcar completada, reabrir, buscador, filtro por rubro) |
| Cobertura | RPC envoltorio para admin | Abrir la función viva a `authenticated`; y quedarse sin el chip |
| Compartir | WhatsApp directo (`wa.me`) | La hoja del sistema como camino principal |
| Vista inicial | Solo los huecos | Arrancar en «Todas» |

## Qué toca cada repo

**`jayalo-main` (web) — una migración y nada más.** El almacén canónico de
migraciones es el de la web (451 ficheros, más el guardia de despliegue
`scripts/verificar-migraciones-aplicadas.mjs`). Las 14 que quedan en
`jayalo-app/supabase/migrations` son históricas (la última es del 2026-08-22) y
no se tocan. La web **no cambia de código ni se vuelve a desplegar** por esta
tanda.

**`jayalo-app` — la pantalla, la ruta, el ítem de menú, el mensaje y los tests.**

## Arquitectura

### 1. La entrada (app)

Ruta `/admin/recruit` en `core/router.dart`, calcada de `/admin/quick-register`:

```dart
redirect: (_, _) async => await isAdmin() ? null : '/gate',
```

Eso es **defensa en profundidad, no el candado**. El candado real es doble y vive
en la base: la RLS de `customer_requests` (la política `Requests: select` ya trae
`has_role(auth.uid(),'admin')`, verificado en producción el 2026-09-14) y el
`has_role` del RPC nuevo. Importa porque el APK ya repartido no se puede
actualizar: si el permiso viviera en el cliente, no habría forma de cerrarlo.

En `features/shared/profile_avatar_button.dart`, `_AdminMenuItem` pasa de un ítem
a dos:

- «Registro rápido» — «Registrar un proveedor por correo» (el de hoy, intacto)
- **«Reclutar» — «Solicitudes sin proveedor»** (nuevo)

Comparte el `isAdmin()` que ese widget ya consulta al montarse (cacheado 5 min en
`AppCaches.isAdmin`): cero llamadas nuevas.

### 2. El conteo de cobertura (migración, repo web)

`request_match_counts_bulk(uuid[])` solo la ejecutan `postgres` y `service_role`
(medido con `pg_proc.proacl` el 2026-09-14), así que la app no puede llamarla.

Se añade un **envoltorio**:

```
admin_request_match_counts_bulk(_request_ids uuid[])
  RETURNS TABLE (request_id uuid, fuertes integer, amplios integer)
  SECURITY DEFINER, search_path = public
```

1. Si `has_role(auth.uid(), 'admin')` es falso → `RAISE EXCEPTION` con
   `ERRCODE = '42501'`.
2. Si no, `RETURN QUERY SELECT * FROM request_match_counts_bulk(_request_ids)`.
3. `REVOKE ALL ... FROM PUBLIC, anon` y `GRANT EXECUTE ... TO authenticated`.

**Es envoltorio a propósito, por dos razones.** La primera: el predicado de
cobertura ya tiene tres copias vivas (deuda aceptada y documentada en el plan del
2026-09-13); una cuarta sería la que se desincroniza. La segunda, y es la que
decide: `request_match_counts_bulk` la llama el trigger que reparte **todas** las
solicitudes, y ahí `auth.uid()` es NULL — meterle la guarda dentro apagaría el
reparto entero.

🔴 El `REVOKE` va `FROM PUBLIC, anon` y no solo `FROM anon`: Postgres concede
EXECUTE a `PUBLIC` al crear la función, y revocar solo por nombre de rol deja
viva esa entrada. Es el agujero de seguridad que llegó a producción el
2026-09-14 en las cuatro funciones de la tanda anterior. La convención del repo
es `FROM PUBLIC, anon, authenticated` (84 usos); aquí `authenticated` se vuelve a
conceder acto seguido porque es quien tiene que llamarla.

### 3. Los datos (app)

En `data/repos.dart`:

```dart
const kShareableRequestCols = <String>[
  'id', 'title', 'zone', 'description',
  'budget_min', 'budget_max', 'urgency', 'kind',
];

Future<List<AdminRequestRow>> adminListRequests({int limit = 100});
Future<Map<String, int>> adminRequestCoverage(List<String> ids);
```

- `adminListRequests` pide `customer_requests` con `status = 'open'`, orden
  `created_at desc`, tope `limit`, y **el `.select()` se construye con
  `kShareableRequestCols.join(',')`**, nunca con un literal suelto.
- `adminRequestCoverage` llama al RPC nuevo **una vez por página** con todos los
  ids. No una llamada por fila: el plan anterior ya cazó ese defecto (hasta 300
  RPC en serie). El RPC devuelve
  `TABLE(request_id uuid, fuertes integer, amplios integer)` (verificado contra
  producción el 2026-09-14); el mapa que sube a la pantalla es
  **`id → fuertes`** y `amplios` se descarta: el chip habla de a cuántos les
  toca de verdad, y meter el círculo amplio ahí diría que hay cobertura donde no
  la hay.
- El filtro «Sin proveedor» es `fuertes == 0` y se aplica en el cliente sobre el
  lote ya traído. Cambiar de pestaña no vuelve a la red.

### 4. La privacidad

Regla dura, heredada del spec del 2026-09-13 y de su corrección del 09-14: **el
mensaje solo puede llevar campos que `/requests/<id>` ya muestra sin sesión.** La
lista blanca no es el `GRANT SELECT` de la base, que es más permisivo y protege
la lista equivocada.

Nada de `lat`/`lng`, nada de contacto del cliente, y **nada de `city`/`sector`**:
esos dos no están en el `select` de la ruta pública y se copian del **perfil** del
cliente en la misma consulta que su GPS (`requests/new.tsx`). Es el barrio de su
casa. La ubicación que sí se puede mandar es `zone`, que es columna de la
solicitud y sí sale en la ruta pública.

En la web eso lo sujetan dos anclas de TIPOS (`satisfies` + `AssertCovers`) que
**Dart no puede replicar**: no hay tipos estructurales ni comprobación de
exhaustividad de claves. La versión Dart lo sujeta por **comportamiento**, con
dos anclas que cubren direcciones distintas:

1. **Que no se pueda traer de más**: el `.select()` sale de
   `kShareableRequestCols`, y un test afirma la lista exacta. Añadir `city`
   obliga a tocar la lista, que es una decisión visible en el diff.
2. **Que no se pueda filtrar de más** (la que de verdad muerde): un test de
   mutación le pasa a `buildRequestShareText` una fila que **sí** trae `city`,
   `sector`, `lat` y `lng` con valores reconocibles, y afirma que el mensaje no
   contiene ninguno de los cuatro. Si alguien los mete en el texto, se pone rojo.

El ancla 2 existe porque el ancla 1 sola es decorativa: alguien puede leer un
campo desde otra consulta y meterlo en el texto sin tocar la lista blanca. Es el
mismo fallo que el revisor cazó en la web el 09-14 («el ancla de privacidad era
decorativa»).

### 5. El mensaje (app)

`domain/request_share_message.dart`, junto a `share_links.dart` — que ya existe y
ya espeja `src/lib/share.ts` de la web. Función **pura**: se prueba sin base ni
red.

Porta `src/lib/requestShareMessage.ts` literalmente:

```
Hola, tengo un cliente en {zone} que busca: {title}

{descripción recortada a 220 code points, con … si se cortó}

Presupuesto: RD$1,000 – RD$5,000

Míralo aquí: https://jayalo.com/requests/{id}
```

- Sin `zone`: «Hola, tengo un cliente que busca: …».
- Sin título: «un trabajo».
- Presupuesto: ambos → «RD$min – RD$max»; solo mínimo → «desde»; solo máximo →
  «hasta»; ninguno → la línea no sale.
- El recorte es **por code points**, no por `length`: en Dart `String.length`
  cuenta unidades UTF-16 y partiría un emoji por la mitad. Se usa
  `characters`/runes.
- El origen sale de `AppConfig.siteUrl`, y el enlace de `ShareLinks.request(id)`
  — no se concatena a mano.

**Este texto es un espejo del de la web.** Si uno cambia, cambian los dos; el
fichero lo dice en su cabecera, igual que hace `ShareLinks` con `share.ts`.

### 6. El compartir (app)

Botón de WhatsApp en cada fila:

1. `launchUrl(Uri.parse('https://wa.me/?text=<mensaje codificado>'),
   mode: LaunchMode.externalApplication)` — mismo camino que ya usa
   `features/provider/unlock_flow.dart:676`.
2. Si devuelve `false` o lanza → hoja del sistema (`share_plus`, ya en el
   proyecto), con el mismo texto.
3. Si eso también falla → snack «No se pudo abrir WhatsApp».

`wa.me` sin número abre el selector de contactos de WhatsApp, que es justo lo que
se quiere: el proveedor todavía no está en Jayalo, y su número lo tiene el admin
en su agenda.

🔴 Todo `snack` va detrás de una guarda `mounted`, y el `launchUrl` NO se llama
con el `context` de la fila: si la lista se refresca, ese contexto muere y la
acción se descarta en silencio. Es exactamente el fallo del 2026-09-12 («¡Iniciar
conversación!» no abría el chat), que costó cuatro hipótesis refutadas.

### 7. La pantalla (app)

`features/admin/recruit_screen.dart`:

- `AppBar` «Reclutar».
- Segmento `Sin proveedor | Todas`, arranca en «Sin proveedor». Mismo patrón que
  `Activas | Terminadas` de `my_requests_screen.dart` (2026-09-13).
- Cabecera con el conteo del segmento activo. 🔴 El texto dice lo que se está
  viendo: en «Todas» no puede decir «N sin proveedor». Ese fue uno de los siete
  defectos del 09-13.
- Cada fila: título, `zone` si la hay, fecha corta, chip **«Sin proveedor»**
  (rojo) o **«N proveedores»** (gris), y el botón de compartir.
- Vacío honesto y distinto por pestaña: en «Sin proveedor» → «Ninguna solicitud
  abierta se quedó sin proveedor»; en «Todas» → «No hay solicitudes abiertas».
  🔴 El vacío mintió dos veces en la tanda del 09-13; aquí se prueban los dos.
- Error de red: mensaje + reintentar. Un fallo del RPC de cobertura **no** tumba
  el listado: las filas se pintan sin chip.

## Pruebas

**Unitarias (puras, sin red):**

- `request_share_message_test.dart`: con `zone` y sin ella; los cuatro casos de
  presupuesto; título vacío → «un trabajo»; recorte a 220 code points con y sin
  emoji; el enlace sale de `ShareLinks.request`.
- **El test de mutación de privacidad** descrito arriba.
- `kShareableRequestCols` es exactamente la lista esperada.

**De widget:**

- Arranca en «Sin proveedor» y solo pinta las de `fuertes == 0`.
- Cambiar a «Todas» las pinta todas y **la cabecera cambia de texto**.
- Los dos vacíos, cada uno con su frase.
- El botón de compartir invoca al lanzador con la URL esperada (lanzador
  inyectado, no se abre WhatsApp de verdad).
- Si el RPC de cobertura falla, la lista se pinta sin chips y sin excepción.

🔴 Un `findsNothing` sobre un `ListView` largo pasa en falso: hay que bajar
primero (`scrollUntilVisible`).

**Contra producción (las corre el controlador, no un subagente — los subagentes
no heredan la autorización del conector de Supabase):**

- El RPC nuevo devuelve los mismos números que `request_match_counts_bulk` para
  el mismo lote.
- Llamado como `authenticated` **sin** rol admin → 42501.
- `proacl` del RPC nuevo: sin entrada de PUBLIC (la que tiene el beneficiario
  vacío, anclada al inicio — `postgres=X/` también contiene `=X/`).

## Gates

- `flutter analyze` limpio.
- Suite completa en verde (línea base: 1972 el 2026-09-13) más los tests nuevos.
- La migración aplicada en producción **y commiteada en `jayalo-main`**, con el
  nombre del fichero casando con el `name` con que entró — el guardia de
  despliegue casa por versión, nombre completo o slug, y un desajuste aborta el
  siguiente deploy del CI (mordió el 2026-09-14).
- APK `1.0.4+129`. 🔴 El número de build es global entre worktrees y solo cabe
  una versión instalada; el sello se lee con `aapt dump xmltree`. Un APK local no
  se instala encima del de Play (firmas distintas): si el teléfono trae el de
  Play, hay que desinstalar — mirar antes el `installer`, que dice de dónde vino.

## Fuera de alcance

Borrar publicaciones, marcar completada o reabrir, buscador, filtro por rubro,
alta rápida de proveedor desde esta pantalla (ya existe «Registro rápido»),
paginación infinita (tope de 100 y ya), y cualquier cambio en la web.

## Smoke del PO

1. Entrar en la app con la cuenta de admin → el menú del avatar trae «Reclutar».
2. Abre en «Sin proveedor» y enseña solicitudes con el chip rojo.
3. El conteo de la cabecera cuadra con lo que se ve.
4. Cambiar a «Todas» → aparecen más, y la cabecera cambia de texto.
5. Compartir una → WhatsApp abre con el mensaje escrito y el enlace
   `jayalo.com/requests/<id>`.
6. Abrir ese enlace **sin sesión** (o en el navegador privado) → carga, y el
   mensaje no menciona la ciudad ni el sector del cliente.
7. Entrar con una cuenta que no sea admin → «Reclutar» no aparece, y
   `/admin/recruit` a mano rebota a `/gate`.
