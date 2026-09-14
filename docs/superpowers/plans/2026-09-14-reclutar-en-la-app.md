# Reclutar desde el teléfono — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el admin vea en la app las solicitudes abiertas, sepa cuáles no tienen ni un proveedor, y le ofrezca una por WhatsApp a alguien que todavía no está en Jayalo.

**Architecture:** Una pantalla nueva en la app (`/admin/recruit`) que lee `customer_requests` con la RLS que ya deja leer todo a un admin, y pide el conteo de cobertura a un RPC envoltorio nuevo que comprueba `has_role` y delega en la función viva. El texto del mensaje es una función pura en `domain/`, espejo del de la web, con la lista blanca de privacidad anclada por un test de mutación.

**Tech Stack:** Flutter 3 / Dart, `supabase_flutter`, `go_router`, `url_launcher`, `share_plus`; Postgres (Supabase) para el RPC.

**Spec:** `docs/superpowers/specs/2026-09-14-reclutar-en-la-app-design.md`

## Global Constraints

- **Dos repos.** La migración de la Task 1 va en `C:/Users/ac/Downloads/jayalo-main` (almacén canónico, 451 migraciones + guardia de despliegue). Todo lo demás va en `C:/Users/ac/Downloads/jayalo-app`. La web **no** se redespliega.
- **Rama de la app:** `feat/fecha-pautada-app`, en `C:/Users/ac/Downloads/jayalo-app` (el carril VIVO, el que se compila). No crear worktree: un worktree hermano sucio hace que el diseño desaparezca del APK, y el número de build es global.
- **Rama de la web:** crear `feat/reclutar-rpc` desde `origin/master` en el worktree `C:/Users/ac/Downloads/jayalo-main/reclutamiento`. 🔴 NUNCA commitear en el worktree `aplicar`: su `master` local es historia divergente.
- **El candado es del servidor, no del cliente.** El APK ya repartido no se puede actualizar: toda comprobación de permiso vive en la RLS y en el `has_role` del RPC. El `redirect` del router es defensa en profundidad.
- **Privacidad (regla dura):** el mensaje solo lleva `id, title, zone, description, budget_min, budget_max, urgency, kind`. Nunca `city`, `sector`, `lat`, `lng` ni contacto del cliente.
- **Copy exacto del mensaje:** espejo literal de `src/lib/requestShareMessage.ts`. Separador de presupuesto: `–` (guion largo, U+2013), no `-`.
- **Nada de `print`**: la app usa `debugPrint` o nada. `flutter analyze` tiene que quedar limpio.
- **Todo `ScaffoldMessenger` detrás de `if (!mounted) return;`**, y el lanzador de WhatsApp NO se llama con el `context` de la fila.
- **Suite de partida:** 1972 pruebas en verde (2026-09-13). Ninguna puede ponerse roja.

## Cambio respecto al spec (leer antes de empezar)

El spec decía que el `.select()` se construye con la lista blanca. Al escribir el plan aparece que la fila necesita `created_at` para pintar la fecha, y `created_at` **no** está en la lista blanca del mensaje (la web tampoco lo comparte).

Se separan en **dos listas con dos responsabilidades**, y la frontera de privacidad pasa a ser el modelo, no el `select`:

- `kShareableRequestCols` — lo que el MENSAJE puede llevar. Es la lista blanca.
- `kAdminListCols` = `kShareableRequestCols + ['created_at']` — lo que la PANTALLA pide.

`ShareableRequest.fromRow` lee **solo** claves de `kShareableRequestCols`, así que aunque la fila traiga `created_at` (o cualquier otra cosa), el mensaje no la ve. El ancla que de verdad lo sujeta es el test de mutación de la Task 2, que le pasa una fila con `city`, `sector`, `lat` y `lng` y exige que no salgan en el texto.

---

### Task 1: El RPC envoltorio (repo web + producción)

**Files:**
- Create: `jayalo-main/supabase/migrations/20260914120000_admin_request_match_counts_bulk.sql`

**Interfaces:**
- Consumes: `public.request_match_counts_bulk(uuid[]) RETURNS TABLE(request_id uuid, fuertes integer, amplios integer)` y `public.has_role(uuid, app_role)` (ambos vivos, verificados contra producción el 2026-09-14).
- Produces: `public.admin_request_match_counts_bulk(_request_ids uuid[]) RETURNS TABLE(request_id uuid, fuertes integer, amplios integer)`, ejecutable por `authenticated` solo si es admin. Lo consume la Task 3.

- [ ] **Step 1: Crear la rama en el worktree de la web**

```bash
cd C:/Users/ac/Downloads/jayalo-main/reclutamiento
git fetch origin --quiet
git checkout -b feat/reclutar-rpc origin/master
```

Esperado: `Switched to a new branch 'feat/reclutar-rpc'`.

- [ ] **Step 2: Escribir la migración**

Crear `supabase/migrations/20260914120000_admin_request_match_counts_bulk.sql`:

```sql
-- El conteo de cobertura para la pantalla "Reclutar" de la APP.
--
-- POR QUE UN ENVOLTORIO Y NO ABRIR LA FUNCION VIVA:
-- `request_match_counts_bulk` la llama el trigger `notify_new_request_matches`,
-- que reparte TODAS las solicitudes nuevas. En ese contexto `auth.uid()` es
-- NULL, asi que meterle dentro una guarda de admin apagaria el reparto entero.
-- Y copiar el predicado aqui seria la CUARTA copia viva (ya hay tres, deuda
-- aceptada y documentada en el plan 2026-09-13): la que se desincroniza.
--
-- POR QUE `authenticated` Y NO `service_role`: quien llama es la APP con la
-- sesion del admin. El permiso real lo pone `has_role`, que lee `user_roles`.
--
-- 🔴 El REVOKE incluye PUBLIC. Postgres concede EXECUTE a PUBLIC al CREAR la
-- funcion, y PUBLIC cubre a anon y a authenticated aunque se revoquen por
-- nombre. Revocar solo por nombre de rol es el agujero que llego a produccion
-- el 2026-09-14 en las cuatro funciones de la tanda del reclutamiento web.
create or replace function public.admin_request_match_counts_bulk(
  _request_ids uuid[]
)
returns table (request_id uuid, fuertes integer, amplios integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_role(auth.uid(), 'admin'::app_role) then
    raise exception 'solo admin' using errcode = '42501';
  end if;

  return query
  select b.request_id, b.fuertes, b.amplios
  from public.request_match_counts_bulk(_request_ids) as b;
end;
$$;

revoke all on function public.admin_request_match_counts_bulk(uuid[]) from public, anon;
grant execute on function public.admin_request_match_counts_bulk(uuid[]) to authenticated;

comment on function public.admin_request_match_counts_bulk(uuid[]) is
  'Cobertura de solicitudes para la pantalla Reclutar de la app. Envoltorio de '
  'request_match_counts_bulk con guarda has_role(admin). Spec '
  'jayalo-app/docs/superpowers/specs/2026-09-14-reclutar-en-la-app-design.md';
```

- [ ] **Step 3: Aplicar en producción**

Esto lo hace **el controlador**, con el conector MCP de Supabase (`apply_migration`, proyecto `mfaiklvobnvgusbcssbx`). 🔴 Un subagente NO hereda esa autorización: si esta tarea va a un subagente, el subagente escribe el fichero y el controlador lo aplica.

Nombre de la migración al aplicarla: `admin_request_match_counts_bulk`.

🔴 Al aplicar con el MCP, la fila queda con la versión de la HORA, no la del fichero. Anotar el `name` con el que entró: el fichero del repo tiene que casar por versión, nombre completo **o slug** con esa fila, o el guardia `scripts/verificar-migraciones-aplicadas.mjs` aborta el siguiente deploy del CI (mordió el 2026-09-14). Con el nombre de arriba, el slug del fichero (`admin_request_match_counts_bulk`) casa.

- [ ] **Step 4: Sonda 1 — los números cuadran con la función viva**

```sql
with ids as (
  select array_agg(id) as arr from (
    select id from public.customer_requests where status = 'open' limit 20
  ) s
)
select
  (select count(*) from public.admin_request_match_counts_bulk((select arr from ids))) as envoltorio,
  (select count(*) from public.request_match_counts_bulk((select arr from ids))) as viva,
  (select count(*) from public.admin_request_match_counts_bulk((select arr from ids)) a
     join public.request_match_counts_bulk((select arr from ids)) b
       on b.request_id = a.request_id
      and b.fuertes = a.fuertes
      and b.amplios = a.amplios) as identicas;
```

Esperado: las tres columnas con el mismo número (20 si hay 20 abiertas). Esto corre como `postgres`, donde `auth.uid()` es NULL — **por eso la guarda tiene que ir en el `if` y no en un `WHERE`**: como `postgres` no es admin, la llamada fallaría. Si falla con 42501, envolver la sonda en un `set local role` no sirve; usar en su lugar la comparación de la Sonda 1b.

- [ ] **Step 4b: Sonda 1b — si la 1 falla por la propia guarda**

```sql
select set_config('request.jwt.claims', json_build_object('sub', u.user_id)::text, true)
from public.user_roles u where u.role = 'admin' limit 1;

select count(*) as filas from public.admin_request_match_counts_bulk(
  (select array_agg(id) from (select id from public.customer_requests where status='open' limit 20) s)
);
```

Esperado: `filas = 20`. `auth.uid()` lee de `request.jwt.claims`, así que esto ejecuta la función **como el admin real** sin tocar ninguna sesión.

- [ ] **Step 5: Sonda 2 — sin rol admin, 42501**

```sql
select set_config('request.jwt.claims', json_build_object('sub', p.id)::text, true)
from public.profiles p
where not exists (select 1 from public.user_roles u where u.user_id = p.id and u.role = 'admin')
limit 1;

select * from public.admin_request_match_counts_bulk(array[]::uuid[]);
```

Esperado: error `42501` con el mensaje `solo admin`. Si devuelve cero filas **sin error**, la guarda no está mordiendo: parar y arreglar antes de seguir.

- [ ] **Step 6: Sonda 3 — PUBLIC no ejecuta**

```sql
select coalesce(array_to_string(p.proacl, ' | '), '(sin acl: PUBLIC ejecuta)') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'admin_request_match_counts_bulk';
```

Esperado: `postgres=X/postgres | authenticated=X/postgres` (el orden puede variar). 🔴 La entrada de PUBLIC es la que tiene el **beneficiario vacío** (`=X/postgres`): hay que mirar el inicio de cada entrada, porque `postgres=X/` también contiene la subcadena `=X/`. Si aparece una entrada que empieza por `=`, el REVOKE no mordió.

- [ ] **Step 7: Cotejar md5 repo ↔ producción**

```sql
select md5(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='admin_request_match_counts_bulk';
```

Comparar con el md5 del **cuerpo** (lo que va entre `$$`) del fichero. Si difieren, lo aplicado no es lo commiteado: es la deriva que crea migraciones huérfanas. Ojo: la cabecera la reescribe Postgres, así que se cotea el cuerpo, nunca el `functiondef` entero.

- [ ] **Step 8: Commit y push**

```bash
cd C:/Users/ac/Downloads/jayalo-main/reclutamiento
git add supabase/migrations/20260914120000_admin_request_match_counts_bulk.sql
git commit -m "feat(db): RPC admin_request_match_counts_bulk para la pantalla Reclutar de la app"
git push origin HEAD:refs/heads/feat/reclutar-rpc
```

No mergear a `master` todavía: se mergea cuando la app esté probada (Task 7).

---

### Task 2: El mensaje de compartir (función pura)

**Files:**
- Create: `app/lib/domain/request_share_message.dart`
- Create: `app/test/request_share_message_test.dart`

**Interfaces:**
- Consumes: `AppConfig.siteUrl` (`core/config.dart`), `ShareLinks.request(String id)` (`domain/share_links.dart`), `fmtRD(num?)` (`domain/money.dart`).
- Produces: `kShareableRequestCols` (`List<String>`), `class ShareableRequest` con `ShareableRequest.fromRow(Map<String, dynamic>)`, `String buildRequestShareText(ShareableRequest)`, `Uri whatsappShareUri(ShareableRequest)`. Los consumen las Tasks 3, 4 y 5.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/request_share_message_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_share_message.dart';

ShareableRequest _r({
  String id = 'r1',
  String? title = 'Silla decorativa de caoba',
  String? zone,
  String? description,
  num? budgetMin,
  num? budgetMax,
}) =>
    ShareableRequest(
      id: id,
      title: title,
      zone: zone,
      description: description,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      urgency: null,
      kind: 'product',
    );

void main() {
  group('buildRequestShareText', () {
    test('con zona, la nombra en la cabecera', () {
      final t = buildRequestShareText(_r(zone: 'Piantini'));
      expect(t, startsWith(
          'Hola, tengo un cliente en Piantini que busca: Silla decorativa de caoba'));
    });

    test('sin zona, la cabecera no la inventa', () {
      final t = buildRequestShareText(_r());
      expect(t, startsWith('Hola, tengo un cliente que busca: Silla decorativa de caoba'));
      expect(t, isNot(contains(' en  que busca')));
    });

    test('una zona de solo espacios cuenta como sin zona', () {
      expect(buildRequestShareText(_r(zone: '   ')),
          startsWith('Hola, tengo un cliente que busca:'));
    });

    test('sin titulo dice "un trabajo"', () {
      expect(buildRequestShareText(_r(title: '  ')),
          startsWith('Hola, tengo un cliente que busca: un trabajo'));
      expect(buildRequestShareText(_r(title: null)),
          startsWith('Hola, tengo un cliente que busca: un trabajo'));
    });

    test('los cuatro casos de presupuesto', () {
      expect(buildRequestShareText(_r(budgetMin: 1000, budgetMax: 5000)),
          contains('Presupuesto: RD\$1,000 – RD\$5,000'));
      expect(buildRequestShareText(_r(budgetMin: 1000)),
          contains('Presupuesto: desde RD\$1,000'));
      expect(buildRequestShareText(_r(budgetMax: 5000)),
          contains('Presupuesto: hasta RD\$5,000'));
      expect(buildRequestShareText(_r()), isNot(contains('Presupuesto')));
    });

    test('el enlace sale de ShareLinks, al final', () {
      expect(buildRequestShareText(_r(id: 'abc')),
          endsWith('Míralo aquí: https://jayalo.com/requests/abc'));
    });

    test('la descripcion larga se recorta a 220 code points con …', () {
      final larga = 'a' * 300;
      final t = buildRequestShareText(_r(description: larga));
      expect(t, contains('${'a' * 220}…'));
      expect(t, isNot(contains('a' * 221)));
    });

    test('una descripcion corta viaja entera y sin …', () {
      final t = buildRequestShareText(_r(description: 'Dos sillas'));
      expect(t, contains('Dos sillas'));
      expect(t, isNot(contains('Dos sillas…')));
    });

    test('recorta por CODE POINTS: no parte un emoji por la mitad', () {
      // 300 emojis = 300 code points = 600 unidades UTF-16. Recortar por
      // `length` partiria el par subrogado y dejaria un caracter invalido.
      final t = buildRequestShareText(_r(description: '🪑' * 300));
      final cuerpo = t.split('\n\n')[1];
      expect(cuerpo.runes.length, 221); // 220 + el …
      expect(cuerpo, endsWith('…'));
      expect(cuerpo, isNot(contains('\uFFFD')));
    });
  });

  group('privacidad', () {
    test('la lista blanca es exactamente esta', () {
      // Espejo de SHAREABLE_FIELDS en src/lib/requestShareMessage.ts.
      expect(kShareableRequestCols, [
        'id', 'title', 'zone', 'description',
        'budget_min', 'budget_max', 'urgency', 'kind',
      ]);
    });

    test('ANCLA: una fila con datos del perfil NO los filtra al mensaje', () {
      // `city`/`sector` se copian del PERFIL del cliente en la misma consulta
      // que su GPS (web: requests/new.tsx) y la pagina publica no los muestra.
      // Es el barrio de su casa. Si alguien los mete en el texto, esto cae.
      final fila = <String, dynamic>{
        'id': 'r9',
        'title': 'Mesa de comedor',
        'zone': 'Piantini',
        'description': 'Para seis personas',
        'budget_min': 1000,
        'budget_max': 2000,
        'urgency': 'normal',
        'kind': 'product',
        'city': 'SANTIAGOSECRETO',
        'sector': 'LOSJARDINESSECRETO',
        'lat': 19.4517,
        'lng': -70.6970,
        'user_id': 'UUIDDELCLIENTE',
      };
      final texto = buildRequestShareText(ShareableRequest.fromRow(fila));
      for (final prohibido in [
        'SANTIAGOSECRETO', 'LOSJARDINESSECRETO', '19.4517', '70.6970',
        'UUIDDELCLIENTE',
      ]) {
        expect(texto, isNot(contains(prohibido)), reason: 'se filtro $prohibido');
      }
      expect(texto, contains('Piantini')); // `zone` SI puede viajar
    });
  });

  group('whatsappShareUri', () {
    test('apunta a wa.me sin numero y con el texto codificado', () {
      final u = whatsappShareUri(_r(id: 'r7', zone: 'Piantini'));
      expect(u.origin, 'https://wa.me');
      expect(u.path, '/');
      expect(u.queryParameters['text'], buildRequestShareText(_r(id: 'r7', zone: 'Piantini')));
    });
  });
}
```

- [ ] **Step 2: Correr los tests para verlos fallar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/request_share_message_test.dart
```

Esperado: FALLA al compilar — `Error: Couldn't resolve the package 'jayalo_app/domain/request_share_message.dart'`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `app/lib/domain/request_share_message.dart`:

```dart
import 'money.dart';
import 'share_links.dart';

/// El mensaje con el que el ADMIN le ofrece una solicitud a un proveedor que
/// todavia no esta en Jayalo, desde la pantalla "Reclutar" de la app.
///
/// 🔴 ESPEJO DE `src/lib/requestShareMessage.ts` (repo web). Si uno cambia,
/// cambian los dos. La web ancla la privacidad con dos comprobaciones de TIPOS
/// (`satisfies` + `AssertCovers`) que Dart no puede replicar; aqui la sujeta el
/// test de mutacion `ANCLA: una fila con datos del perfil NO los filtra`.
///
/// PRIVACIDAD (regla dura): este texto sale de la plataforma por WhatsApp, a
/// alguien SIN SESION. Solo puede llevar campos que `/requests/<id>` ya muestra
/// sin sesion. La lista blanca NO es el `GRANT SELECT` de la base, que es mas
/// permisivo y protege la lista equivocada. Nada de lat/lng, nada de contacto, y
/// nada de `city`/`sector`: esos dos no salen en la ruta publica y se copian del
/// PERFIL del cliente junto a su GPS — es el barrio de su casa. `zone` SI, que
/// es columna de la solicitud.
library;

/// Lo unico que el MENSAJE puede llevar. Espejo de `SHAREABLE_FIELDS`.
/// (La PANTALLA pide ademas `created_at`; ver `kAdminListCols` en repos.dart.)
const kShareableRequestCols = <String>[
  'id',
  'title',
  'zone',
  'description',
  'budget_min',
  'budget_max',
  'urgency',
  'kind',
];

/// La solicitud tal y como puede salir de la plataforma. `fromRow` lee SOLO
/// claves de `kShareableRequestCols`: aunque la fila traiga mas columnas (y las
/// trae: `created_at`, y el admin podria leer todas), aqui no entran.
class ShareableRequest {
  const ShareableRequest({
    required this.id,
    required this.title,
    required this.zone,
    required this.description,
    required this.budgetMin,
    required this.budgetMax,
    required this.urgency,
    required this.kind,
  });

  final String id;
  final String? title;
  final String? zone;
  final String? description;
  final num? budgetMin;
  final num? budgetMax;
  final String? urgency;
  final String? kind;

  factory ShareableRequest.fromRow(Map<String, dynamic> r) => ShareableRequest(
        id: r['id'] as String,
        title: r['title'] as String?,
        zone: r['zone'] as String?,
        description: r['description'] as String?,
        budgetMin: r['budget_min'] as num?,
        budgetMax: r['budget_max'] as num?,
        urgency: r['urgency'] as String?,
        kind: r['kind'] as String?,
      );
}

/// La descripcion de una solicitud manual es el texto COMPLETO del cliente y
/// puede ser larga: no se manda entera.
const _maxDescripcionCodePoints = 220;

/// 🔴 Por CODE POINTS (`runes`), no por `length`: en Dart `length` cuenta
/// unidades UTF-16 y recortar ahi parte un emoji en dos mitades invalidas. Es
/// el equivalente exacto del `Array.from(...)` de la web.
String? _descripcionRecortada(String? description) {
  final t = description?.trim();
  if (t == null || t.isEmpty) return null;
  final puntos = t.runes.toList();
  if (puntos.length <= _maxDescripcionCodePoints) return t;
  return '${String.fromCharCodes(puntos.take(_maxDescripcionCodePoints))}…';
}

/// 🔴 NO se reusa `requestBudgetLabel` de money.dart: usa " - " y aqui la web
/// manda "–" (guion largo) y ademas el prefijo "Presupuesto: ". Reusarla
/// cambiaria el mensaje en silencio. `fmtRD` si se reusa: su salida
/// ("RD$1,000") es identica a la de `toLocaleString('es-DO')` de la web.
String? _presupuesto(num? min, num? max) {
  if (min != null && max != null) return 'Presupuesto: ${fmtRD(min)} – ${fmtRD(max)}';
  if (min != null) return 'Presupuesto: desde ${fmtRD(min)}';
  if (max != null) return 'Presupuesto: hasta ${fmtRD(max)}';
  return null;
}

/// `zone` es `text NOT NULL DEFAULT ''` y el creador web no la escribe, asi que
/// casi siempre resuelve a null y el mensaje queda sin ubicacion — a proposito,
/// para que se lea natural.
String? _lugar(String? zone) {
  final z = zone?.trim();
  return (z == null || z.isEmpty) ? null : z;
}

String buildRequestShareText(ShareableRequest r) {
  final donde = _lugar(r.zone);
  final titulo = (r.title?.trim().isNotEmpty ?? false) ? r.title!.trim() : 'un trabajo';

  final cabecera = donde != null
      ? 'Hola, tengo un cliente en $donde que busca: $titulo'
      : 'Hola, tengo un cliente que busca: $titulo';

  final bloques = <String>[
    cabecera,
    ?_descripcionRecortada(r.description),
    ?_presupuesto(r.budgetMin, r.budgetMax),
    'Míralo aquí: ${ShareLinks.request(r.id)}',
  ];

  return bloques.join('\n\n');
}

Uri whatsappShareUri(ShareableRequest r) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buildRequestShareText(r))}');
```

⚠️ Si la versión de Dart del proyecto no admite los elementos opcionales de colección (`?expr` dentro de un literal de lista), sustituir la lista por:

```dart
  final bloques = <String>[cabecera];
  final desc = _descripcionRecortada(r.description);
  if (desc != null) bloques.add(desc);
  final pres = _presupuesto(r.budgetMin, r.budgetMax);
  if (pres != null) bloques.add(pres);
  bloques.add('Míralo aquí: ${ShareLinks.request(r.id)}');
```

- [ ] **Step 4: Correr los tests hasta verlos pasar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/request_share_message_test.dart
```

Esperado: `All tests passed!` (11 pruebas).

- [ ] **Step 5: Probar por MUTACIÓN que el ancla de privacidad no es decorativa**

Un test que nunca se ha visto rojo no prueba nada. Romper el código a propósito, en tres sitios exactos, y **volver a dejarlo como estaba**:

1. En `ShareableRequest`, añadir el campo: `final String? city;` (y a la lista de parámetros del constructor, como `this.city`).
2. En `fromRow`, añadir: `city: r['city'] as String?,`.
3. En `buildRequestShareText`, cambiar la cabecera por:

```dart
  final cabecera = donde != null
      ? 'Hola, tengo un cliente en $donde (${r.city}) que busca: $titulo'
      : 'Hola, tengo un cliente que busca: $titulo';
```

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/request_share_message_test.dart
```

Esperado: **ROJO**, con `se filtro SANTIAGOSECRETO`.

Deshacer los tres cambios (`git checkout -- lib/domain/request_share_message.dart` si aún no está commiteado) y volver a correr: verde. Si no se puso rojo, el ancla no vale y hay que arreglarla antes de seguir — es exactamente el fallo que el revisor cazó en la web el 2026-09-14.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/lib/domain/request_share_message.dart app/test/request_share_message_test.dart
git commit -m "feat(app): el mensaje para ofrecer una solicitud por WhatsApp, espejo de la web"
```

---

### Task 3: Los datos en `repos.dart`

**Files:**
- Modify: `app/lib/data/repos.dart` (añadir al final de la zona de solicitudes)
- Create: `app/test/admin_recruit_repos_test.dart`

**Interfaces:**
- Consumes: `kShareableRequestCols` (Task 2), `supa` (cliente Supabase ya global en `repos.dart`), el RPC `admin_request_match_counts_bulk` (Task 1).
- Produces: `kAdminListCols` (`List<String>`), `Future<List<Map<String, dynamic>>> adminListRequests({int limit})`, `Future<Map<String, int>> adminRequestCoverage(List<String> ids)`. Los consume la Task 4.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/admin_recruit_repos_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';
import 'package:jayalo_app/domain/request_share_message.dart';

void main() {
  test('la pantalla pide la lista blanca MAS created_at, y nada mas', () {
    // Dos listas, dos responsabilidades: `kShareableRequestCols` es lo que el
    // MENSAJE puede llevar; `kAdminListCols` es lo que la PANTALLA pide (le
    // hace falta la fecha). Si alguien mete `city` aqui para pintarla en la
    // fila, este test lo hace visible en el diff.
    expect(kAdminListCols, [...kShareableRequestCols, 'created_at']);
    for (final prohibido in ['city', 'sector', 'lat', 'lng', 'user_id']) {
      expect(kAdminListCols, isNot(contains(prohibido)));
    }
  });

  test('el select es la lista separada por comas, sin espacios', () {
    // PostgREST parte por comas: un espacio dentro haria que pidiera una
    // columna llamada " title" y devolveria 400.
    expect(kAdminListCols.join(','), isNot(contains(' ')));
  });
}
```

- [ ] **Step 2: Correr para verlo fallar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/admin_recruit_repos_test.dart
```

Esperado: FALLA — `Undefined name 'kAdminListCols'`.

- [ ] **Step 3: Implementar en `repos.dart`**

Añadir el import arriba, junto a los demás de `domain/`:

```dart
import '../domain/request_share_message.dart' show kShareableRequestCols;
```

Y las tres piezas, al final de la zona de solicitudes:

```dart
/// Lo que pide la PANTALLA "Reclutar" (solo admin): la lista blanca del mensaje
/// mas `created_at` para pintar la fecha. La frontera de privacidad NO es esta
/// lista sino `ShareableRequest.fromRow`, que solo lee claves de
/// `kShareableRequestCols` — ver `domain/request_share_message.dart`.
const kAdminListCols = <String>[...kShareableRequestCols, 'created_at'];

/// Solicitudes abiertas para la pantalla "Reclutar".
///
/// No hay guarda de admin en el cliente A PROPOSITO: la pone la RLS de
/// `customer_requests` (la politica `Requests: select` trae
/// `has_role(auth.uid(),'admin')`). Un usuario normal ve aqui solo las abiertas
/// y publicas, que ya son publicas de todos modos — nada que proteger en el
/// cliente, que ademas no se puede actualizar una vez repartido el APK.
Future<List<Map<String, dynamic>>> adminListRequests({int limit = 100}) async =>
    List<Map<String, dynamic>>.from(
      await supa
          .from('customer_requests')
          .select(kAdminListCols.join(','))
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(limit),
    );

/// Cobertura por solicitud: id → cuantos proveedores FUERTES (mismo rubro u
/// oficio) le tocan hoy. Una sola llamada por pagina, nunca una por fila.
///
/// Se queda con `fuertes` y descarta `amplios`: el chip habla de a quien le toca
/// de verdad, y contar el circulo amplio diria que hay cobertura donde no la
/// hay.
Future<Map<String, int>> adminRequestCoverage(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = List<Map<String, dynamic>>.from(
    await supa.rpc(
      'admin_request_match_counts_bulk',
      params: {'_request_ids': ids},
    ),
  );
  return {
    for (final r in rows)
      r['request_id'] as String: (r['fuertes'] as num).toInt(),
  };
}
```

- [ ] **Step 4: Correr los tests y el analizador**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/admin_recruit_repos_test.dart && flutter analyze
```

Esperado: `All tests passed!` y `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/lib/data/repos.dart app/test/admin_recruit_repos_test.dart
git commit -m "feat(app): lectura de solicitudes y cobertura para la pantalla Reclutar"
```

---

### Task 4: La pantalla

**Files:**
- Create: `app/lib/features/admin/recruit_screen.dart`
- Create: `app/test/recruit_screen_test.dart`

**Interfaces:**
- Consumes: `adminListRequests`, `adminRequestCoverage`, `kAdminListCols` (Task 3); `ShareableRequest` (Task 2); `fmtRD`, `timeAgo` no — la fecha se pinta con `_fechaCorta` local.
- Produces: `class RecruitScreen extends StatefulWidget` con constructor `RecruitScreen({super.key, this.load, this.coverage, this.onShare})`. La Task 5 rellena `onShare`; la Task 6 la enruta.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/recruit_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/admin/recruit_screen.dart';

Map<String, dynamic> _fila(String id, String titulo) => {
      'id': id,
      'title': titulo,
      'zone': 'Piantini',
      'description': 'Descripcion',
      'budget_min': 1000,
      'budget_max': 2000,
      'urgency': 'normal',
      'kind': 'product',
      'created_at': '2026-09-14T10:00:00Z',
    };

Widget _app({
  List<Map<String, dynamic>>? filas,
  Map<String, int>? cobertura,
  Future<Map<String, int>> Function(List<String>)? coverage,
}) =>
    MaterialApp(
      home: RecruitScreen(
        load: ({int limit = 100}) async => filas ?? const [],
        coverage: coverage ?? (ids) async => cobertura ?? const {},
      ),
    );

void main() {
  testWidgets('arranca en "Sin proveedor" y solo pinta las de cobertura 0',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba'), _fila('r2', 'Nevera')],
      cobertura: {'r1': 0, 'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('Silla de caoba'), findsOneWidget);
    expect(find.text('Nevera'), findsNothing);
    expect(find.text('Sin proveedor'), findsOneWidget);
  });

  testWidgets('en "Todas" salen las dos y LA CABECERA CAMBIA DE TEXTO',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba'), _fila('r2', 'Nevera')],
      cobertura: {'r1': 0, 'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('1 sin proveedor'), findsOneWidget);

    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Nevera'), findsOneWidget);
    // 🔴 La cabecera no puede seguir diciendo "sin proveedor" en "Todas": ese
    // fue uno de los siete defectos de la tanda del 2026-09-13.
    expect(find.text('2 abiertas'), findsOneWidget);
    expect(find.text('2 sin proveedor'), findsNothing);
    expect(find.text('3 proveedores'), findsOneWidget);
  });

  testWidgets('los dos vacios dicen cosas DISTINTAS', (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r2', 'Nevera')],
      cobertura: {'r2': 3},
    ));
    await t.pumpAndSettle();
    expect(find.text('Ninguna solicitud abierta se quedó sin proveedor'),
        findsOneWidget);

    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Nevera'), findsOneWidget);
  });

  testWidgets('sin ninguna solicitud abierta, el vacio de "Todas" es el suyo',
      (t) async {
    await t.pumpWidget(_app(filas: const []));
    await t.pumpAndSettle();
    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('No hay solicitudes abiertas'), findsOneWidget);
  });

  testWidgets('si la cobertura falla, la lista se pinta SIN chips y sin reventar',
      (t) async {
    await t.pumpWidget(_app(
      filas: [_fila('r1', 'Silla de caoba')],
      coverage: (ids) async => throw Exception('sin red'),
    ));
    await t.pumpAndSettle();
    // Cae a "Todas" porque sin cobertura no se puede saber que es un hueco.
    expect(find.text('Silla de caoba'), findsOneWidget);
    expect(find.text('Sin proveedor'), findsNothing);
    // `pumpAndSettle` no falla por una excepcion que el framework ya capturo;
    // esto la hace explicita (idioma de la suite: brand_kit_test.dart:174).
    expect(t.takeException(), isNull);
  });

  testWidgets('si la lista falla, ofrece reintentar', (t) async {
    await t.pumpWidget(MaterialApp(
      home: RecruitScreen(
        load: ({int limit = 100}) async => throw Exception('sin red'),
        coverage: (ids) async => const {},
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr para verlos fallar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_screen_test.dart
```

Esperado: FALLA — no existe `recruit_screen.dart`.

- [ ] **Step 3: Implementar la pantalla**

Crear `app/lib/features/admin/recruit_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../../domain/request_share_message.dart';

/// "Reclutar" (SOLO admin): las solicitudes abiertas, marcando cuales no tienen
/// ni un proveedor al que les toque, para ofrecerselas por WhatsApp a alguien
/// que todavia no esta en Jayalo.
///
/// Espeja `/admin/requests?coverage=gap` de la web (desplegado 2026-09-14), pero
/// SOLO la parte de reclutar: aqui no se borra, no se marca completada y no se
/// reabre. Eso se queda en la web, que tiene pantalla grande.
///
/// `load`/`coverage`/`onShare` se inyectan para poder probar sin red (mismo
/// patron que `AddressScreen`).
class RecruitScreen extends StatefulWidget {
  // 🔴 NO `const`: `load ?? adminListRequests` no es una expresion constante,
  // asi que un constructor `const` no compila. Por eso la ruta la construye
  // como `RecruitScreen()`, sin `const` (a diferencia de las de al lado).
  RecruitScreen({
    super.key,
    Future<List<Map<String, dynamic>>> Function({int limit})? load,
    Future<Map<String, int>> Function(List<String>)? coverage,
    this.onShare,
  })  : load = load ?? adminListRequests,
        coverage = coverage ?? adminRequestCoverage;

  final Future<List<Map<String, dynamic>>> Function({int limit}) load;
  final Future<Map<String, int>> Function(List<String>) coverage;

  /// La rellena la Task 5. Se inyecta para que el test no abra WhatsApp.
  final void Function(ShareableRequest)? onShare;

  @override
  State<RecruitScreen> createState() => _RecruitScreenState();
}

class _RecruitScreenState extends State<RecruitScreen> {
  bool _soloHuecos = true;
  bool _cargando = true;
  bool _error = false;
  List<Map<String, dynamic>> _filas = const [];

  /// id → proveedores fuertes. VACIO si el RPC fallo: en ese caso no se puede
  /// afirmar que algo sea un hueco, asi que no se pinta ningun chip y la vista
  /// cae a "Todas" (mentir con un "Sin proveedor" inventado seria peor que no
  /// decir nada).
  Map<String, int> _cobertura = const {};
  bool _coberturaOk = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final filas = await widget.load();
      Map<String, int> cob = const {};
      var ok = false;
      try {
        cob = await widget.coverage([for (final f in filas) f['id'] as String]);
        ok = true;
      } catch (_) {
        // Un fallo de la cobertura NO tumba el listado.
      }
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _cobertura = cob;
        _coberturaOk = ok;
        if (!ok) _soloHuecos = false;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _cargando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibles => _soloHuecos
      ? [for (final f in _filas) if ((_cobertura[f['id']] ?? 0) == 0) f]
      : _filas;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibles = _visibles;
    return Scaffold(
      appBar: AppBar(title: const Text('Reclutar')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No se pudieron cargar las solicitudes'),
                      const SizedBox(height: 8),
                      FilledButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          if (_coberturaOk) ...[
                            _pastilla('Sin proveedor', _soloHuecos,
                                () => setState(() => _soloHuecos = true)),
                            const SizedBox(width: 8),
                          ],
                          _pastilla('Todas', !_soloHuecos,
                              () => setState(() => _soloHuecos = false)),
                          const Spacer(),
                          // 🔴 El texto dice lo que se esta VIENDO: en "Todas"
                          // no puede decir "sin proveedor".
                          Text(
                            _soloHuecos
                                ? '${visibles.length} sin proveedor'
                                : '${visibles.length} abiertas',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visibles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _soloHuecos
                                      ? 'Ninguna solicitud abierta se quedó sin proveedor'
                                      : 'No hay solicitudes abiertas',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: ListView.separated(
                                itemCount: visibles.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => _Fila(
                                  fila: visibles[i],
                                  fuertes: _coberturaOk
                                      ? (_cobertura[visibles[i]['id']] ?? 0)
                                      : null,
                                  onShare: widget.onShare,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _pastilla(String label, bool sel, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: sel ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? Colors.white : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.fila, required this.fuertes, this.onShare});
  final Map<String, dynamic> fila;

  /// null = no se pudo saber (el RPC fallo): no se pinta chip.
  final int? fuertes;
  final void Function(ShareableRequest)? onShare;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = (fila['title'] as String?)?.trim();
    final zona = (fila['zone'] as String?)?.trim();
    return ListTile(
      title: Text(titulo == null || titulo.isEmpty ? 'Sin título' : titulo),
      subtitle: Row(
        children: [
          if (zona != null && zona.isNotEmpty) ...[
            Text(zona, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(width: 8),
          ],
          if (fuertes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: fuertes == 0
                    ? cs.errorContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                fuertes == 0 ? 'Sin proveedor' : '$fuertes proveedores',
                style: TextStyle(
                  fontSize: 11,
                  color: fuertes == 0 ? cs.onErrorContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: 'Compartir por WhatsApp',
        onPressed: onShare == null
            ? null
            : () => onShare!(ShareableRequest.fromRow(fila)),
      ),
    );
  }
}
```

- [ ] **Step 4: Correr los tests hasta verlos pasar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_screen_test.dart && flutter analyze
```

Esperado: `All tests passed!` y `No issues found!`. Si un `findsNothing` falla, comprobar que no sea el falso positivo de un `ListView` largo (hace falta `scrollUntilVisible`).

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/lib/features/admin/recruit_screen.dart app/test/recruit_screen_test.dart
git commit -m "feat(app): pantalla Reclutar con el segmento Sin proveedor / Todas"
```

---

### Task 5: Compartir por WhatsApp

**Files:**
- Create: `app/lib/features/admin/recruit_share.dart`
- Modify: `app/lib/features/admin/recruit_screen.dart` (el `onShare` por defecto)
- Create: `app/test/recruit_share_test.dart`

**Interfaces:**
- Consumes: `whatsappShareUri`, `buildRequestShareText`, `ShareableRequest` (Task 2).
- Produces: `Future<void> compartirSolicitud(ShareableRequest r, {Future<bool> Function(Uri)? abrir, Future<void> Function(String)? hoja, void Function(String)? aviso})`. La consume `RecruitScreen`.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/recruit_share_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_share_message.dart';
import 'package:jayalo_app/features/admin/recruit_share.dart';

const _r = ShareableRequest(
  id: 'r1',
  title: 'Silla de caoba',
  zone: 'Piantini',
  description: null,
  budgetMin: null,
  budgetMax: null,
  urgency: null,
  kind: 'product',
);

void main() {
  test('abre WhatsApp con el mensaje y NO usa la hoja del sistema', () async {
    Uri? abierta;
    var hojas = 0;
    await compartirSolicitud(_r,
        abrir: (u) async {
          abierta = u;
          return true;
        },
        hoja: (_) async => hojas++);
    expect(abierta!.origin, 'https://wa.me');
    expect(abierta!.queryParameters['text'], buildRequestShareText(_r));
    expect(hojas, 0);
  });

  test('si WhatsApp no abre, cae a la hoja del sistema con el MISMO texto',
      () async {
    String? texto;
    await compartirSolicitud(_r,
        abrir: (_) async => false, hoja: (t) async => texto = t);
    expect(texto, buildRequestShareText(_r));
  });

  test('si launchUrl LANZA, tambien cae a la hoja (no se pierde el toque)',
      () async {
    String? texto;
    await compartirSolicitud(_r,
        abrir: (_) async => throw Exception('sin WhatsApp'),
        hoja: (t) async => texto = t);
    expect(texto, buildRequestShareText(_r));
  });

  test('si los dos fallan, avisa y no lanza', () async {
    String? aviso;
    await compartirSolicitud(_r,
        abrir: (_) async => false,
        hoja: (_) async => throw Exception('nada'),
        aviso: (m) => aviso = m);
    expect(aviso, 'No se pudo abrir WhatsApp');
  });
}
```

- [ ] **Step 2: Correr para verlo fallar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_share_test.dart
```

Esperado: FALLA — no existe `recruit_share.dart`.

- [ ] **Step 3: Implementar**

Crear `app/lib/features/admin/recruit_share.dart`:

```dart
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/request_share_message.dart';

/// Ofrecer una solicitud por WhatsApp.
///
/// `wa.me` SIN numero abre el selector de contactos de WhatsApp, que es lo que
/// se quiere: el proveedor todavia no esta en Jayalo y su numero lo tiene el
/// admin en su agenda. Mismo camino que `features/provider/unlock_flow.dart`.
///
/// Los tres huecos se inyectan para poder probarlo sin abrir nada.
Future<void> compartirSolicitud(
  ShareableRequest r, {
  Future<bool> Function(Uri)? abrir,
  Future<void> Function(String)? hoja,
  void Function(String)? aviso,
}) async {
  final abrirFn = abrir ??
      (u) => launchUrl(u, mode: LaunchMode.externalApplication);
  final hojaFn = hoja ??
      (t) => SharePlus.instance.share(ShareParams(text: t)).then((_) {});

  final texto = buildRequestShareText(r);

  try {
    if (await abrirFn(whatsappShareUri(r))) return;
  } catch (_) {
    // Sin WhatsApp instalado, o el sistema rechaza el intent: se intenta la
    // hoja antes de rendirse.
  }

  try {
    await hojaFn(texto);
  } catch (_) {
    aviso?.call('No se pudo abrir WhatsApp');
  }
}
```

La API de `share_plus` es la que ya usa `features/shared/share_button.dart:20`:
`SharePlus.instance.share(ShareParams(text: ...))`. No inventar otra.

🔴 Aquí NO se usa `ShareLinks.mensaje(texto, url)`: ese helper es para el
compartir del cliente, que manda título + enlace en dos líneas. El mensaje del
admin ya trae su enlace dentro, en su propio bloque.

- [ ] **Step 4: Engancharlo en la pantalla**

En `recruit_screen.dart`, sustituir el uso de `widget.onShare` por un envoltorio que avise por snack. 🔴 El `ScaffoldMessenger` se captura ANTES del `await` y todo va detrás de `mounted`: si la lista se refresca, el `context` de la fila muere y el aviso se pierde en silencio — es el fallo del 2026-09-12 que costó cuatro hipótesis.

En `_RecruitScreenState`:

```dart
  void _compartir(ShareableRequest r) {
    // El messenger se captura ANTES del await, y el aviso va detras de
    // `mounted`. `unawaited` es el idioma del repo (core/error_reporter.dart).
    final messenger = ScaffoldMessenger.of(context);
    unawaited(compartirSolicitud(
      r,
      aviso: (m) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(m)));
      },
    ));
  }
```

Y en el `itemBuilder`: `onShare: widget.onShare ?? _compartir`. Añadir los dos
imports: `import 'dart:async';` (por `unawaited`) y `import 'recruit_share.dart';`.

- [ ] **Step 5: Correr toda la suite nueva**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_share_test.dart test/recruit_screen_test.dart test/request_share_message_test.dart && flutter analyze
```

Esperado: todo verde, `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/lib/features/admin/recruit_share.dart app/lib/features/admin/recruit_screen.dart app/test/recruit_share_test.dart
git commit -m "feat(app): compartir una solicitud por WhatsApp desde Reclutar"
```

---

### Task 6: La ruta y el ítem de menú

**Files:**
- Modify: `app/lib/core/router.dart:280-292` (junto a `/admin/quick-register`)
- Modify: `app/lib/features/shared/profile_avatar_button.dart:274-276` y `:327-360`
- Create: `app/test/recruit_entry_test.dart`

**Interfaces:**
- Consumes: `RecruitScreen` (Task 4), `isAdmin()` (`data/repos.dart`).
- Produces: la ruta `/admin/recruit` y el ítem «Reclutar» del menú del avatar.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/recruit_entry_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';

void main() {
  testWidgets('el menu de admin ofrece las DOS herramientas, cada una con su ruta',
      (t) async {
    final rutas = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminMenuItems(
          esAdmin: true,
          onSelect: rutas.add,
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Registro rápido'), findsOneWidget);
    expect(find.text('Reclutar'), findsOneWidget);
    expect(find.text('Solicitudes sin proveedor'), findsOneWidget);

    await t.tap(find.text('Reclutar'));
    await t.pumpAndSettle();
    expect(rutas, ['/admin/recruit']);
  });

  testWidgets('quien no es admin no ve ninguna de las dos', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminMenuItems(esAdmin: false, onSelect: _nada)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Registro rápido'), findsNothing);
    expect(find.text('Reclutar'), findsNothing);
  });
}

void _nada(String _) {}
```

- [ ] **Step 2: Correr para verlo fallar**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_entry_test.dart
```

Esperado: FALLA — `AdminMenuItems` no existe (hoy es `_AdminMenuItem`, privado y con un solo ítem).

- [ ] **Step 3: Abrir el widget y darle los dos ítems**

En `app/lib/features/shared/profile_avatar_button.dart`, sustituir `_AdminMenuItem` por una versión pública y parametrizable. El estado sigue consultando `isAdmin()`, pero se puede forzar desde el test con `esAdmin`:

```dart
/// Los items de menu que SOLO ve un admin. Publico (no `_`) para poder probarlo
/// sin montar el menu entero; `esAdmin` es para el test — en produccion queda
/// null y lo decide `isAdmin()`.
class AdminMenuItems extends StatefulWidget {
  const AdminMenuItems({super.key, required this.onSelect, this.esAdmin});
  final void Function(String ruta) onSelect;
  final bool? esAdmin;
  @override
  State<AdminMenuItems> createState() => _AdminMenuItemsState();
}

class _AdminMenuItemsState extends State<AdminMenuItems> {
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    if (widget.esAdmin != null) {
      _admin = widget.esAdmin!;
    } else {
      isAdmin().then((v) => mounted ? setState(() => _admin = v) : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_admin) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(height: 1),
      ListTile(
        leading: Icon(Icons.person_add_alt, color: cs.primary),
        title: const Text('Registro rápido'),
        subtitle: const Text('Registrar un proveedor por correo'),
        onTap: () => widget.onSelect('/admin/quick-register'),
      ),
      ListTile(
        leading: Icon(Icons.campaign_outlined, color: cs.primary),
        title: const Text('Reclutar'),
        subtitle: const Text('Solicitudes sin proveedor'),
        onTap: () => widget.onSelect('/admin/recruit'),
      ),
    ]);
  }
}
```

Y en el menú (línea ~274), cambiar la llamada:

```dart
                AdminMenuItems(onSelect: (ruta) => Navigator.pop(ctx, ruta)),
```

- [ ] **Step 4: Añadir la ruta**

En `app/lib/core/router.dart`, justo después del bloque de `/admin/quick-register`:

```dart
            GoRoute(
                path: '/admin/recruit',
                // Mismo gate que quick-register, y por la misma razon: esto es
                // defensa en profundidad. La barrera REAL es del servidor — la
                // RLS de `customer_requests` y el `has_role` del RPC
                // `admin_request_match_counts_bulk` — porque el APK ya
                // repartido no se puede actualizar.
                redirect: (_, _) async => await isAdmin() ? null : '/gate',
                // Sin `const` (ver el comentario del constructor de
                // RecruitScreen): las rutas de al lado si lo llevan, y copiarlas
                // aqui no compila.
                builder: (_, _) => BackGuard(child: RecruitScreen())),
```

Añadir el import de `RecruitScreen` junto a los demás de `features/admin/`.

- [ ] **Step 5: Correr el test y la suite entera**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter test test/recruit_entry_test.dart && flutter analyze && flutter test
```

Esperado: el test nuevo pasa, `No issues found!`, y la suite completa en verde con **1972 + las nuevas**. Si alguna prueba vieja toca `_AdminMenuItem`, actualizarla al nombre nuevo.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/lib/core/router.dart app/lib/features/shared/profile_avatar_button.dart app/test/recruit_entry_test.dart
git commit -m "feat(app): ruta /admin/recruit y el item Reclutar en el menu del admin"
```

---

### Task 7: Gates, APK y el merge de la migración

**Files:**
- Modify: `app/pubspec.yaml:22` (`version: 1.0.4+128` → `1.0.4+129`)

- [ ] **Step 1: Comprobar que ningún worktree hermano está sucio**

```bash
cd C:/Users/ac/Downloads/jayalo-app && git worktree list
for w in /c/Users/ac/Downloads/jayalo-app-*; do echo "== $w"; git -C "$w" status --porcelain | head -3; done
```

🔴 Un worktree hermano sucio hace que el diseño DESAPAREZCA del APK. Si alguno tiene cambios, commitearlos o parar y avisar antes de compilar.

- [ ] **Step 2: Subir el número de build**

En `app/pubspec.yaml`, línea 22: `version: 1.0.4+129`.

🔴 El número de build es GLOBAL entre worktrees y solo cabe una versión instalada.

- [ ] **Step 3: Gates completos**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter analyze && flutter test
```

Esperado: `No issues found!` y toda la suite verde.

- [ ] **Step 4: Compilar el APK**

```bash
cd C:/Users/ac/Downloads/jayalo-app/app && flutter build apk --release
```

Esperado: `✓ Built build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 5: Verificar el sello del APK**

```bash
aapt dump xmltree build/app/outputs/flutter-apk/app-release.apk AndroidManifest.xml | grep -i versionName -A1
```

Esperado: `versionCode` **129** y `versionName` `1.0.4`. Leer el sello, no fiarse del nombre del fichero.

- [ ] **Step 6: Commit y push de la app**

```bash
cd C:/Users/ac/Downloads/jayalo-app
git add app/pubspec.yaml
git commit -m "chore(app): 1.0.4+129 — Reclutar en el menu del admin"
git push origin feat/fecha-pautada-app
```

- [ ] **Step 7: Mergear la migración a `master` en la web**

```bash
cd C:/Users/ac/Downloads/jayalo-main/reclutamiento
git push origin feat/reclutar-rpc:master
```

Esperado: fast-forward. El CI arranca solo; el job `deploy` reconstruye y despliega la web sin cambios de código (la migración no toca el bundle). Comprobar que el paso «Las migraciones del repo están aplicadas en producción» pasa: si dice que falta `admin_request_match_counts_bulk`, el nombre del fichero no casa con el `name` de producción y hay que renombrarlo (ver Task 1, Step 3).

- [ ] **Step 8: Instalar y avisar al PO**

Antes de proponer desinstalar nada, mirar de dónde vino lo instalado:

```bash
adb shell pm list packages -i | grep jayalo
```

Si el `installer` es `null`, el teléfono ya trae un APK local y se instala encima. Si es `com.android.vending`, viene de Play: firmas distintas, hay que desinstalar primero (y eso borra sus datos).

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Luego pasarle al PO el smoke de 7 pasos del spec.

---

## Notas de ejecución

- **Las medidas contra producción las hace el controlador**, no un subagente: los subagentes no heredan la autorización del conector MCP de Supabase (medido 2026-09-12).
- **Orden:** la Task 1 tiene que estar aplicada en producción antes de la Task 3, o `adminRequestCoverage` devuelve 404 del RPC y la pantalla se queda sin chips.
- Las Tasks 2 y 3 pueden ir en paralelo con la 1 (no dependen del RPC para compilar ni para sus tests, que son puros).
