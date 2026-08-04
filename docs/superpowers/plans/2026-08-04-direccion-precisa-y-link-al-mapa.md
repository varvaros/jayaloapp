# Dirección precisa en la app + link al mapa en el chat — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar `superpowers:subagent-driven-development`
> (recomendado) o `superpowers:executing-plans` para ejecutar tarea por tarea. Los pasos usan
> casillas (`- [ ]`).

**Goal:** Que la dirección que la app captura sea específica y corregible, y que al compartirla en
el chat llegue con un enlace al mapa que el otro pueda abrir.

**Architecture:** La app deja de usar el geocodificador nativo de Android (devuelve la vía grande
más cercana y el municipio, sin nada donde encajar el sector) y pasa a consumir un endpoint nuevo
`/api/app/reverse-geocode` de la web, que envuelve el mismo Nominatim estructurado que ya usa
`/profile`. El sector deja de ser un select cerrado: la lista fija pasa a ser sugerencia y se
acepta lo que devuelva el geocodificador o escriba el usuario. Las coordenadas —que ya se guardan
en `profiles.lat/lng` desde hace tiempo y nadie usaba— se convierten en el enlace del chat.

**Tech Stack:** Flutter (app) · TanStack Start + Supabase (web) · Nominatim (OpenStreetMap).

## Global Constraints

- **Dos repos.** Web = `C:\Users\ac\Downloads\jayalo-main\jayalo-main`. App =
  `C:\Users\ac\Downloads\jayalo-app` (rama `feat/detalle-cliente-plegable`). Son repos distintos
  con git propio; ningún commit cruza.
- **Las tareas 1-5 (web) van ANTES que las 6-11 (app), y entre medias hay un DESPLIEGUE.** La app
  llama a un endpoint que tiene que estar vivo en `jayalo.com`. Tarea 6 en adelante no se puede
  probar en device hasta que la web esté desplegada.
- **Baselines que no pueden bajar:** web `tsc` 0 errores, `lint` 0 errores, 457 tests. App
  `flutter analyze` limpio, 776 tests.
- **Copy en español, sin tildes en los comentarios de código de la app** (convención del repo).
- **Commits:** `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` al final. No pushear ni
  mergear sin pedirlo.
- **Ningún cambio de base de datos.** Las columnas `country,city,sector,street,street_number,unit,
  address_reference,address,lat,lng` ya existen en `profiles` y la web ya las escribe desde
  `/profile`, así que los grants ya están.

---

## Estructura de ficheros

**Web:**
- Modificar `src/lib/reverseGeocode.ts` — el sector/ciudad fuera de catálogo deja de perderse.
- Crear `src/routes/api/app/reverse-geocode.ts` — endpoint para la app.
- Modificar `src/components/consumer/ConsumerProfileForm.tsx` — pasa al geocoder estructurado.
- Borrar `src/lib/geo.ts` y `src/lib/geo.functions.ts` — el geocoder débil.
- Modificar `src/routes/profile.tsx` y `src/routes/profileprovider.tsx` — sector con salida libre.

**App:**
- Reescribir `lib/domain/geo.dart` — modelo estructurado + composición + link de mapa. Puro.
- Crear `lib/core/geocode_client.dart` — cliente del endpoint.
- Modificar `lib/data/repos.dart` — escribir los campos nuevos, `updateMyAddress`, link en
  `myLocationBody`/`myBusinessAddressBody`.
- Modificar los dos `features/onboarding/*_onboarding_screen.dart`.
- Crear `lib/features/settings/address_screen.dart` + ruta `/settings/address`.
- Modificar `lib/features/chat/widgets/bubbles.dart` — burbuja de dirección pulsable.

---

## Tarea 1: El sector fuera de catálogo deja de perderse (web)

Hoy `placeFromNominatim` devuelve `sector: ""` cuando lo que trae Nominatim no está en
`LOCATIONS`. Por eso "Parque del Este" —que NO está en la lista; Santo Domingo Este solo tiene
Alma Rosa, Los Mina, Villa Duarte, San Isidro, Invivienda y Ensanche Ozama— se descarta en
silencio. Esta tarea hace que el valor crudo sobreviva, y marca si venía o no del catálogo para
que la UI sepa pintarlo.

**Files:**
- Modify: `src/lib/reverseGeocode.ts`
- Test: `src/lib/reverseGeocode.test.ts`

**Interfaces:**
- Produces: `GeocodedPlace` con dos campos nuevos, `cityInCatalog: boolean` y
  `sectorInCatalog: boolean`. `city` y `sector` pasan a traer el valor CRUDO cuando no calzan, en
  vez de `""`. Lo consumen las tareas 2, 3 y 5.

- [ ] **Step 1: Escribir el test que falla**

En `src/lib/reverseGeocode.test.ts`, añadir:

```ts
it("conserva el sector aunque no esté en el catálogo", () => {
  const p = placeFromNominatim({
    country: "República Dominicana",
    city: "Santo Domingo Este",
    suburb: "Parque del Este",
    road: "Calle Primera",
    house_number: "12",
  });
  expect(p.city).toBe("Santo Domingo Este");
  expect(p.cityInCatalog).toBe(true);
  expect(p.sector).toBe("Parque del Este");
  expect(p.sectorInCatalog).toBe(false);
  expect(p.addressLine).toBe(
    "Calle Primera 12, Parque del Este, Santo Domingo Este, República Dominicana",
  );
});

it("marca inCatalog cuando sí calza", () => {
  const p = placeFromNominatim({
    country: "República Dominicana",
    city: "Santo Domingo Este",
    suburb: "Alma Rosa",
  });
  expect(p.sector).toBe("Alma Rosa");
  expect(p.sectorInCatalog).toBe(true);
});

it("conserva la ciudad fuera de catálogo y entonces el sector no se valida", () => {
  const p = placeFromNominatim({
    country: "República Dominicana",
    city: "Higüey",
    suburb: "Villa Cerro",
  });
  expect(p.city).toBe("Higüey");
  expect(p.cityInCatalog).toBe(false);
  expect(p.sector).toBe("Villa Cerro");
  expect(p.sectorInCatalog).toBe(false);
});
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `npx vitest run src/lib/reverseGeocode.test.ts`
Expected: FAIL — `p.city` es `"Santo Domingo Este"` pero `cityInCatalog` no existe, y en el
tercer caso `p.city` sale `""`.

- [ ] **Step 3: Implementar**

En `src/lib/reverseGeocode.ts`, sustituir el tipo y el cuerpo de `placeFromNominatim`:

```ts
export type GeocodedPlace = {
  country: string;
  city: string;
  cityInCatalog: boolean;
  sector: string;
  sectorInCatalog: boolean;
  street: string;
  streetNumber: string;
  addressLine: string;
};

/** Primer candidato no vacío, ya recortado. */
const firstNonEmpty = (cands: (string | undefined)[]) =>
  cands.map((c) => (c ?? "").trim()).find((c) => c.length > 0) ?? "";

/**
 * Traduce la respuesta de Nominatim a los campos del formulario.
 *
 * Regla clave (bug PO 2026-08-04): el catálogo `LOCATIONS` es SUGERENCIA, no
 * filtro. Antes, una ciudad o un sector que no estuvieran en la lista se
 * descartaban a `""` y el usuario veía el formulario medio vacío — "Parque del
 * Este" no está en el catálogo y por eso desaparecía. Ahora el valor crudo
 * sobrevive y `*InCatalog` le dice a la UI si tiene que ofrecerlo como opción
 * suelta dentro del select.
 */
export function placeFromNominatim(a: NominatimAddress): GeocodedPlace {
  const rawCountry = String(a.country ?? "");
  const country = COUNTRIES.find((c) => eq(c, rawCountry)) ?? DEFAULT_COUNTRY;

  const cities = LOCATIONS[country] ? Object.keys(LOCATIONS[country]) : [];
  const cityCands = [a.city, a.town, a.village, a.municipality, a.county, a.state];
  const cityMatch =
    cityCands.map((cand) => (cand ? cities.find((c) => eq(c, cand)) : undefined)).find(Boolean) ??
    "";
  const city = cityMatch || firstNonEmpty(cityCands);

  // El sector solo se valida contra el catálogo si la CIUDAD calzó: los sectores
  // están indexados por ciudad, así que sin ciudad de catálogo no hay lista
  // contra la que comparar.
  const sectors = cityMatch ? (LOCATIONS[country]?.[cityMatch] ?? []) : [];
  const sectorCands = [a.suburb, a.neighbourhood, a.quarter, a.city_district, a.district];
  const sectorMatch =
    sectorCands
      .map((cand) => (cand ? sectors.find((s) => eq(s, cand)) : undefined))
      .find(Boolean) ?? "";
  const sector = sectorMatch || firstNonEmpty(sectorCands);

  const street = String(a.road ?? "");
  const streetNumber = String(a.house_number ?? "");

  const line1 = [street, streetNumber].filter(Boolean).join(" ").trim();
  const addressLine = [line1, sector, city, rawCountry].filter(Boolean).join(", ");

  return {
    country,
    city,
    cityInCatalog: !!cityMatch,
    sector,
    sectorInCatalog: !!sectorMatch,
    street,
    streetNumber,
    addressLine,
  };
}
```

- [ ] **Step 4: Correr los tests**

Run: `npx vitest run src/lib/reverseGeocode.test.ts`
Expected: PASS. Si algún test viejo esperaba `sector: ""` para un valor fuera de catálogo,
actualizarlo — ese comportamiento es justo el bug.

- [ ] **Step 5: Commit**

```bash
git add src/lib/reverseGeocode.ts src/lib/reverseGeocode.test.ts
git commit -m "fix(web): el sector fuera del catalogo deja de descartarse en silencio"
```

---

## Tarea 2: Endpoint `/api/app/reverse-geocode` (web)

La app no debe llamar a Nominatim directo: su política de uso pide un User-Agent identificable y
un techo de peticiones, y repartir eso entre miles de teléfonos es justo lo que no quieren. El
endpoint mantiene una sola implementación y un solo User-Agent.

**Files:**
- Create: `src/routes/api/app/reverse-geocode.ts`
- Test: `src/routes/api/app/reverse-geocode.test.ts`

**Interfaces:**
- Consumes: `placeFromNominatim` de la tarea 1.
- Produces: `POST {lat: number, lng: number}` → `200 GeocodedPlace` (el objeto entero de la
  tarea 1). Lo consume la tarea 7.

- [ ] **Step 1: Escribir el test que falla**

Crear `src/routes/api/app/reverse-geocode.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { placeFromNominatim } from "@/lib/reverseGeocode";

// El handler HTTP se prueba en el smoke; aquí se fija el CONTRATO de la
// respuesta, que es lo que la app parsea y lo que se rompería en silencio.
describe("contrato de /api/app/reverse-geocode", () => {
  it("la respuesta trae las 8 claves que la app espera", () => {
    const place = placeFromNominatim({ country: "República Dominicana", city: "Santiago" });
    expect(Object.keys(place).sort()).toEqual([
      "addressLine",
      "city",
      "cityInCatalog",
      "country",
      "sector",
      "sectorInCatalog",
      "street",
      "streetNumber",
    ]);
  });
});
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `npx vitest run src/routes/api/app/reverse-geocode.test.ts`
Expected: FAIL — el fichero de test existe pero la ruta no; si el import resuelve, el test pasa
ya (es un contrato sobre la tarea 1). En ese caso vale como red de regresión: seguir al paso 3.

- [ ] **Step 3: Implementar el endpoint**

Crear `src/routes/api/app/reverse-geocode.ts`, calcado de
`src/routes/api/app/business-editor-link.ts` (Origin fail-closed + rate limit + Bearer):

```ts
import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { extractBearerToken } from "@/lib/aiSession.server";
import { checkRateLimit } from "@/lib/rateLimit.server";
import { placeFromNominatim, type NominatimAddress } from "@/lib/reverseGeocode";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const Body = z.object({ lat: z.number(), lng: z.number() });

/**
 * Geocodificación inversa para la app (bug PO 2026-08-04: el geocoder nativo de
 * Android devuelve la via grande mas cercana y el municipio, sin sector).
 * Envuelve el MISMO Nominatim estructurado que usa /profile, para que app y web
 * entiendan una direccion igual. Va por aqui y no directo desde el telefono
 * porque la politica de uso de Nominatim pide un User-Agent identificable.
 *
 * Exige Bearer: el onboarding de la app siempre corre con sesion, y sin auth
 * esto seria un proxy gratuito de geocodificacion abierto a cualquiera.
 */
export const Route = createFileRoute("/api/app/reverse-geocode")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const origin = request.headers.get("origin") ?? "";
        const allowedOrigins = [
          process.env.SITE_URL ?? "",
          "https://jayalo.com",
          "https://jallalo.com",
          "https://jayalo.net",
          "https://jallalo.net",
        ].filter(Boolean);
        if (!origin || !allowedOrigins.includes(origin)) {
          return json({ error: "Forbidden" }, 403);
        }

        const allowed = await checkRateLimit(request, {
          bucket: "reverse-geocode",
          limit: 30,
          windowSeconds: 60,
        });
        if (!allowed) return json({ error: "Demasiadas solicitudes" }, 429);

        const token = extractBearerToken(request);
        if (!token) return json({ error: "No autenticado" }, 401);
        const { data: userData, error: userErr } = await supabase.auth.getUser(token);
        if (userErr || !userData?.user) return json({ error: "No autenticado" }, 401);

        let parsed: z.infer<typeof Body>;
        try {
          parsed = Body.parse(await request.json());
        } catch {
          return json({ error: "Petición inválida" }, 400);
        }

        try {
          const url =
            `https://nominatim.openstreetmap.org/reverse?format=jsonv2` +
            `&lat=${parsed.lat}&lon=${parsed.lng}&accept-language=es&zoom=18&addressdetails=1`;
          const res = await fetch(url, {
            headers: {
              "User-Agent": "jayalo.com (soporte@jayalo.com)",
              Accept: "application/json",
            },
          });
          if (!res.ok) return json({ error: "No se pudo geocodificar" }, 502);
          const data = (await res.json()) as { address?: NominatimAddress };
          return json(placeFromNominatim(data.address ?? {}), 200);
        } catch {
          return json({ error: "No se pudo geocodificar" }, 502);
        }
      },
    },
  },
});
```

⚠️ Verificar la firma real de `checkRateLimit` en `src/lib/rateLimit.server.ts` y ajustar los
nombres de los parámetros si difieren — no inventarlos.

- [ ] **Step 4: Verificar**

Run: `npx tsc --noEmit && npx vitest run src/routes/api/app/reverse-geocode.test.ts`
Expected: 0 errores y test en verde.

- [ ] **Step 5: Commit**

```bash
git add src/routes/api/app/reverse-geocode.ts src/routes/api/app/reverse-geocode.test.ts
git commit -m "feat(web): endpoint de geocodificacion inversa para la app"
```

---

## Tarea 3: El registro de cliente de la web usa el geocoder bueno

`ConsumerProfileForm` usa `reverseGeocode` de `geo.functions.ts`, que devuelve una sola cadena
con un `join` plano — exactamente el mismo defecto que la app. Es la tercera de las cuatro
puertas de entrada que rellena tímido.

**Files:**
- Modify: `src/components/consumer/ConsumerProfileForm.tsx:7,99` y el sitio donde usa `revGeo`
- Delete: `src/lib/geo.ts`, `src/lib/geo.functions.ts`

**Interfaces:**
- Consumes: `reverseGeocode(lat, lon): Promise<GeocodedPlace>` de `@/lib/reverseGeocode`
  (tarea 1).

- [ ] **Step 1: Leer el formulario entero antes de tocarlo**

Leer `src/components/consumer/ConsumerProfileForm.tsx` completo. Localizar qué campos de
dirección tiene hoy (posiblemente solo uno de texto libre, con `placeholder="Calle, número,
sector, ciudad"` en la línea 302) y decidir si el formulario gana campos separados o si se
conserva el campo único rellenado con `place.addressLine`.

**Criterio:** si el formulario hoy tiene UN campo, rellenarlo con `place.addressLine` y además
persistir `city`/`sector`/`street`/`street_number` en el `upsert` de `profiles`. No añadir
campos visibles nuevos en esta tarea — el sitio para editarlos con detalle es `/profile`, que ya
existe. El objetivo aquí es que los campos estructurados dejen de perderse.

- [ ] **Step 2: Sustituir la llamada**

Cambiar el import de la línea 7 a `import { reverseGeocode } from "@/lib/reverseGeocode";`,
quitar el `useServerFn` de la línea 99 (ya no es una server fn, es una función normal que corre
en el cliente contra Nominatim — igual que en `/profile`), y usar `place.addressLine` donde antes
usaba `res.address`. Añadir `city`, `sector`, `street`, `street_number` al `upsert` de
`profiles`.

- [ ] **Step 3: Borrar el geocoder débil**

```bash
git rm src/lib/geo.ts src/lib/geo.functions.ts
```

Si existe `src/lib/geo.test.ts`, borrarlo también. Comprobar que no queda ningún import:

```bash
grep -rn "lib/geo\"\|lib/geo.functions\|formatNominatimAddress" src/
```

Expected: sin resultados. Ajustar `src/lib/csp.server.ts:6`, que menciona `reverseGeocode` en un
comentario, si el comentario queda desfasado.

- [ ] **Step 4: Verificar**

Run: `npx tsc --noEmit && npx vitest run && npm run lint`
Expected: 0 errores, 0 errores de lint, todos los tests en verde.

- [ ] **Step 5: Commit**

```bash
git add -A src/
git commit -m "fix(web): el registro de cliente rellena la direccion estructurada"
```

---

## Tarea 4: El sector admite lo que no está en el catálogo (web)

`/profile` y `/profileprovider` pintan el sector como `<select>` cerrado. Con la tarea 1 el
sector detectado puede venir fuera de catálogo, y un select cerrado no puede mostrarlo.

**Files:**
- Modify: `src/routes/profile.tsx:153-200` (zona de `detectLocation`) y el `<select>` del sector
- Modify: `src/routes/profileprovider.tsx:519` y su `<select>` del sector

- [ ] **Step 1: Leer las dos pantallas**

Leer las zonas del select de sector en ambos ficheros. Anotar cómo se construye `sectorOptions`
(en `profile.tsx` está en la línea 68, un `useMemo`).

- [ ] **Step 2: Añadir el valor detectado a las opciones**

En ambos, hacer que las opciones del sector incluyan el valor actual aunque no esté en el
catálogo:

```tsx
const sectorOptions = useMemo(() => {
  const catalog = city ? (LOCATIONS[country]?.[city] ?? []) : [];
  // El sector detectado o escrito puede no estar en el catalogo (Parque del
  // Este, por ejemplo). Si se deja fuera, el select no puede mostrarlo y el
  // valor se pierde al primer render.
  return sector && !catalog.some((s) => s.toLowerCase() === sector.toLowerCase())
    ? [sector, ...catalog]
    : catalog;
}, [country, city, sector]);
```

- [ ] **Step 3: Permitir escribirlo a mano**

Convertir el select en un `<input list=...>` + `<datalist>` (nativo, sin dependencias nuevas):
la lista sigue sugiriendo el catálogo y el usuario puede teclear el suyo. Mantener el mismo
`value`/`onChange` que tenía el select.

- [ ] **Step 4: Quitar el copy que ya no aplica**

En `detectLocation` de `profile.tsx` (líneas 187-194) el mensaje "Selecciona tu sector" existía
porque el sector se descartaba. Con la tarea 1 ya viene relleno. Ajustar los tres toasts: éxito
si hay ciudad y sector; si falta alguno, decir qué falta.

- [ ] **Step 5: Verificar y commitear**

Run: `npx tsc --noEmit && npm run lint && npx vitest run`

```bash
git add src/routes/profile.tsx src/routes/profileprovider.tsx
git commit -m "feat(web): el sector acepta valores fuera del catalogo"
```

---

## Tarea 5: Desplegar la web — GATE

**No es una tarea de código. La app no funciona sin esto.**

- [ ] **Step 1: Verificar los baselines**

Run: `npx tsc --noEmit && npm run lint && npx vitest run`
Expected: 0 / 0 / ≥457 tests.

- [ ] **Step 2: Pedir permiso para pushear**

El push a `master` despliega solo (job `deploy` del CI). **Preguntar al PO antes de pushear** —
la rama `fix/grants-update-oferta-app` lleva 9 commits sin pushear y hay que decidir si esto va
encima o en rama aparte.

- [ ] **Step 3: Verificar el endpoint en vivo**

Tras el despliegue, comprobar que responde 403 sin Origin (fail-closed) y 401 sin Bearer:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://jayalo.com/api/app/reverse-geocode
```

Expected: `403`.

---

## Tarea 6: El dominio de geo de la app (puro y testeable)

**Files:**
- Rewrite: `app/lib/domain/geo.dart`
- Test: `app/test/geo_test.dart`

**Interfaces:**
- Produces: `GeocodedPlace` (modelo + `fromJson`), `composeAddressLine(...)`,
  `mapsLinkFor(lat, lng)`, `splitMapLink(body)`. Los consumen las tareas 7, 8, 9, 10 y 11.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `app/test/geo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/domain/geo.dart';

void main() {
  test('composeAddressLine omite vacios y no repite', () {
    expect(
      composeAddressLine(
          street: 'Calle Primera',
          streetNumber: '12',
          sector: 'Parque del Este',
          city: 'Santo Domingo Este'),
      'Calle Primera 12, Parque del Este, Santo Domingo Este',
    );
    expect(
      composeAddressLine(
          street: '', streetNumber: '', sector: 'Alma Rosa', city: 'Alma Rosa'),
      'Alma Rosa',
    );
  });

  test('mapsLinkFor arma un enlace universal', () {
    expect(mapsLinkFor(18.482243, -69.854165),
        'https://www.google.com/maps/search/?api=1&query=18.482243,-69.854165');
  });

  test('splitMapLink separa el enlace del texto', () {
    const body = 'Calle Primera 12\nParque del Este\n'
        'https://www.google.com/maps/search/?api=1&query=18.48,-69.85';
    final r = splitMapLink(body);
    expect(r.text, 'Calle Primera 12\nParque del Este');
    expect(r.mapUrl, 'https://www.google.com/maps/search/?api=1&query=18.48,-69.85');
  });

  test('splitMapLink deja intacto un cuerpo sin enlace', () {
    final r = splitMapLink('Calle Primera 12');
    expect(r.text, 'Calle Primera 12');
    expect(r.mapUrl, isNull);
  });

  test('GeocodedPlace.fromJson tolera claves ausentes', () {
    final p = GeocodedPlace.fromJson({'city': 'Santiago'});
    expect(p.city, 'Santiago');
    expect(p.sector, '');
    expect(p.sectorInCatalog, false);
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `cd app && flutter test test/geo_test.dart`
Expected: FAIL — no compila, `composeAddressLine` no existe.

- [ ] **Step 3: Implementar**

Reescribir `app/lib/domain/geo.dart` ENTERO (el `formatPlacemarkAddress` viejo desaparece):

```dart
/// Dominio de direcciones. Puro y testeable: aqui no entra Flutter ni la red.
///
/// Sustituye a `formatPlacemarkAddress`, que unia lo que devolvia el
/// geocodificador NATIVO de Android. En RD ese geocoder devuelve la via grande
/// mas cercana y el municipio, asi que la direccion salia tan vaga que no
/// servia ("Autopista Las Americas, Santo Domingo Este" para alguien de Parque
/// del Este). Ahora los campos vienen estructurados del endpoint de la web.
class GeocodedPlace {
  const GeocodedPlace({
    this.country = '',
    this.city = '',
    this.cityInCatalog = false,
    this.sector = '',
    this.sectorInCatalog = false,
    this.street = '',
    this.streetNumber = '',
    this.addressLine = '',
  });

  final String country;
  final String city;
  final bool cityInCatalog;
  final String sector;
  final bool sectorInCatalog;
  final String street;
  final String streetNumber;
  final String addressLine;

  static const empty = GeocodedPlace();

  factory GeocodedPlace.fromJson(Map<String, dynamic> j) => GeocodedPlace(
        country: (j['country'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        cityInCatalog: (j['cityInCatalog'] as bool?) ?? false,
        sector: (j['sector'] as String?) ?? '',
        sectorInCatalog: (j['sectorInCatalog'] as bool?) ?? false,
        street: (j['street'] as String?) ?? '',
        streetNumber: (j['streetNumber'] as String?) ?? '',
        addressLine: (j['addressLine'] as String?) ?? '',
      );
}

/// Une los componentes en una linea legible, sin vacios ni duplicados.
String composeAddressLine({
  required String street,
  required String streetNumber,
  required String sector,
  required String city,
}) {
  final line1 = [street.trim(), streetNumber.trim()]
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();
  final seen = <String>{};
  final parts = <String>[];
  for (final raw in [line1, sector.trim(), city.trim()]) {
    if (raw.isEmpty || seen.contains(raw.toLowerCase())) continue;
    seen.add(raw.toLowerCase());
    parts.add(raw);
  }
  return parts.join(', ');
}

/// Enlace universal al mapa.
///
/// A proposito NO se usa el esquema `geo:`: lo entiende Android, pero no el
/// navegador ni WhatsApp, y este texto viaja en un chat que el otro puede abrir
/// donde sea. El de Google Maps abre la app nativa si esta instalada y el
/// navegador si no.
String mapsLinkFor(double lat, double lng) =>
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

/// Separa el enlace del mapa del resto del cuerpo de un mensaje de direccion,
/// para que la burbuja pinte texto arriba y un boton abajo en vez de una URL
/// cruda de 60 caracteres.
({String text, String? mapUrl}) splitMapLink(String body) {
  final lines = body.split('\n');
  final i = lines.indexWhere(
      (l) => l.trim().startsWith('https://www.google.com/maps/'));
  if (i == -1) return (text: body, mapUrl: null);
  final url = lines[i].trim();
  lines.removeAt(i);
  return (text: lines.join('\n').trimRight(), mapUrl: url);
}
```

- [ ] **Step 4: Correr los tests**

Run: `cd app && flutter test test/geo_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/geo.dart app/test/geo_test.dart
git commit -m "feat(app): dominio de direcciones estructurado con enlace al mapa"
```

---

## Tarea 7: Cliente del endpoint de geocodificación (app)

**Files:**
- Create: `app/lib/core/geocode_client.dart`
- Modify: `app/lib/core/config.dart` — añadir `reverseGeocodeEndpoint`
- Test: `app/test/geocode_client_test.dart`

**Interfaces:**
- Consumes: `GeocodedPlace.fromJson` (tarea 6).
- Produces: `GeocodeClient.lookup({lat, lng, accessToken}) → Future<GeocodedPlace>`. Devuelve
  `GeocodedPlace.empty` si algo falla — nunca lanza. Lo consumen las tareas 9 y 10.

- [ ] **Step 1: Escribir el test que falla**

Crear `app/test/geocode_client_test.dart` usando `http.MockClient` (el repo ya usa `http`):

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo/core/geocode_client.dart';

void main() {
  test('parsea la respuesta del endpoint', () async {
    final c = GeocodeClient(inner: MockClient((_) async => http.Response(
        jsonEncode({'city': 'Santo Domingo Este', 'sector': 'Parque del Este'}), 200)));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.sector, 'Parque del Este');
  });

  test('devuelve empty y NO lanza si el endpoint falla', () async {
    final c = GeocodeClient(
        inner: MockClient((_) async => http.Response('{"error":"x"}', 502)));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.addressLine, '');
  });

  test('devuelve empty si la red revienta', () async {
    final c = GeocodeClient(inner: MockClient((_) async => throw Exception('sin red')));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.addressLine, '');
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `cd app && flutter test test/geocode_client_test.dart`
Expected: FAIL — `geocode_client.dart` no existe.

- [ ] **Step 3: Implementar**

Añadir a `app/lib/core/config.dart`, junto a los otros endpoints:

```dart
  static const reverseGeocodeEndpoint = '$siteUrl/api/app/reverse-geocode';
```

Crear `app/lib/core/geocode_client.dart` (mismo patrón que `editor_link_client.dart`):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/geo.dart';
import 'config.dart';

/// Geocodificacion inversa contra la web (bug PO 2026-08-04). El geocoder
/// nativo de Android no sirve en RD: devuelve la via grande mas cercana.
///
/// NUNCA lanza: rellenar la direccion es una ayuda, no un requisito. Si falla,
/// devuelve `empty` y el usuario escribe la suya — que es justo lo que hacia el
/// `catch (_)` del onboarding viejo.
class GeocodeClient {
  GeocodeClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<GeocodedPlace> lookup({
    required double lat,
    required double lng,
    required String accessToken,
  }) async {
    try {
      final res = await _http
          .post(
            Uri.parse(AppConfig.reverseGeocodeEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Origin': AppConfig.siteUrl,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return GeocodedPlace.empty;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return GeocodedPlace.fromJson(j);
    } catch (_) {
      return GeocodedPlace.empty;
    }
  }
}
```

- [ ] **Step 4: Correr los tests**

Run: `cd app && flutter test test/geocode_client_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/geocode_client.dart app/lib/core/config.dart app/test/geocode_client_test.dart
git commit -m "feat(app): cliente del endpoint de geocodificacion inversa"
```

---

## Tarea 8: `profiles` guarda los campos estructurados y `myLocationBody` lleva el enlace

**Files:**
- Modify: `app/lib/data/repos.dart:1306-1333` (`completeConsumerProfile`)
- Modify: `app/lib/data/repos.dart:1931-1954` (`myBusinessAddressBody`)
- Modify: `app/lib/data/repos.dart:1980-2001` (`myLocationBody`)
- Create: `updateMyAddress` en el mismo fichero
- Test: `app/test/location_body_test.dart`

**Interfaces:**
- Consumes: `composeAddressLine`, `mapsLinkFor` (tarea 6).
- Produces: `updateMyAddress({address, city, sector, street, streetNumber, reference, lat, lng})`
  y `buildLocationBody(...)` puro. Los consumen las tareas 10 y 11.

- [ ] **Step 1: Escribir el test que falla**

El cuerpo del mensaje se puede probar si se extrae la composición a una función pura. Crear
`app/test/location_body_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/data/location_body.dart';

void main() {
  test('el cuerpo lleva el enlace al mapa cuando hay coordenadas', () {
    final b = buildLocationBody(
      address: 'Calle Primera 12',
      cityLine: 'Parque del Este, Santo Domingo Este',
      reference: 'Casa azul',
      lat: 18.48,
      lng: -69.85,
    );
    expect(b, contains('Calle Primera 12'));
    expect(b, contains('Referencia: Casa azul'));
    expect(b, contains('https://www.google.com/maps/search/?api=1&query=18.48,-69.85'));
    expect(b!.split('\n').last, startsWith('https://www.google.com/maps/'));
  });

  test('sin coordenadas no hay enlace, pero el cuerpo sigue valiendo', () {
    final b = buildLocationBody(
        address: 'Calle Primera 12', cityLine: '', reference: '', lat: null, lng: null);
    expect(b, 'Calle Primera 12');
  });

  test('sin nada devuelve null', () {
    expect(
        buildLocationBody(
            address: '', cityLine: '', reference: '', lat: null, lng: null),
        isNull);
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `cd app && flutter test test/location_body_test.dart`
Expected: FAIL — `location_body.dart` no existe.

- [ ] **Step 3: Implementar la función pura**

Crear `app/lib/data/location_body.dart`:

```dart
import '../domain/geo.dart';

/// Compone el cuerpo del mensaje de direccion del chat.
///
/// El enlace va SIEMPRE en la ULTIMA linea: `splitMapLink` lo busca por prefijo
/// y la burbuja lo saca del texto para pintarlo como boton.
String? buildLocationBody({
  required String address,
  required String cityLine,
  required String reference,
  required double? lat,
  required double? lng,
}) {
  final parts = <String>[
    if (address.trim().isNotEmpty) address.trim(),
    if (cityLine.trim().isNotEmpty) cityLine.trim(),
    if (reference.trim().isNotEmpty) 'Referencia: ${reference.trim()}',
  ];
  if (parts.isEmpty) return null;
  if (lat != null && lng != null) parts.add(mapsLinkFor(lat, lng));
  return parts.join('\n');
}
```

- [ ] **Step 4: Cablearlo en `repos.dart`**

En `myLocationBody()`: añadir `lat,lng` al `select` y devolver
`buildLocationBody(address: ..., cityLine: ..., reference: ..., lat: ..., lng: ...)`.

En `myBusinessAddressBody()`: añadir `lat,lng` al `select` de `provider_businesses` y añadir
`mapsLinkFor` como última línea cuando existan. **Ojo:** el nombre del negocio va primero, así
que componer a mano en vez de reutilizar `buildLocationBody`.

En `completeConsumerProfile()`: añadir los parámetros `city`, `sector`, `street`, `streetNumber`
y escribirlos en el `upsert` (`'city'`, `'sector'`, `'street'`, `'street_number'`).

Añadir `updateMyAddress`:

```dart
/// Actualiza SOLO la direccion del perfil. Existe porque hasta 2026-08-04 la
/// direccion solo se podia poner en el onboarding: si salia mal el dia del alta,
/// no habia ninguna forma de corregirla dentro de la app.
Future<void> updateMyAddress({
  required String address,
  required String city,
  required String sector,
  required String street,
  required String streetNumber,
  required String reference,
  double? lat,
  double? lng,
}) async {
  final uid = supa.auth.currentUser!.id;
  await supa.from('profiles').update({
    'address': address,
    'city': city.isEmpty ? null : city,
    'sector': sector.isEmpty ? null : sector,
    'street': street.isEmpty ? null : street,
    'street_number': streetNumber.isEmpty ? null : streetNumber,
    'address_reference': reference.isEmpty ? null : reference,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (lat != null && lng != null)
      'location_captured_at': DateTime.now().toIso8601String(),
  }).eq('user_id', uid);
}
```

- [ ] **Step 5: Verificar y commitear**

Run: `cd app && flutter test && flutter analyze lib/data/`
Expected: tests en verde (779+), analyze limpio.

```bash
git add app/lib/data/ app/test/location_body_test.dart
git commit -m "feat(app): direccion estructurada en profiles y enlace al mapa en el chat"
```

---

## Tarea 9: Los dos onboardings usan el geocoder nuevo

**Files:**
- Modify: `app/lib/features/onboarding/consumer_onboarding_screen.dart:85-134,157-159`
- Modify: `app/lib/features/onboarding/provider_onboarding_screen.dart:264-290,381,390-391`

- [ ] **Step 1: Subir la precisión del GPS**

En ambos, cambiar `LocationAccuracy.medium` por `LocationAccuracy.high`. Conservar el
`timeLimit: Duration(seconds: 15)` y su comentario — sigue siendo obligatorio.

Comentario a añadir:

```dart
      // `high` y no `medium`: en este device `medium` declara 100 m de precision
      // y `high` 4,6 m. Con 100 m el geocodificador puede enganchar la avenida
      // de al lado en vez de la calle real.
```

- [ ] **Step 2: Sustituir el geocoder nativo**

Quitar el `import 'package:geocoding/geocoding.dart';` y el bloque
`placemarkFromCoordinates(...)` + `formatPlacemarkAddress(...)`. En su lugar:

```dart
      if (_address.text.trim().isEmpty) {
        final token = supa.auth.currentSession?.accessToken;
        if (token != null) {
          final place = await GeocodeClient()
              .lookup(lat: pos.latitude, lng: pos.longitude, accessToken: token);
          if (mounted && place.addressLine.isNotEmpty &&
              _address.text.trim().isEmpty) {
            setState(() {
              _address.text = place.addressLine;
              _city = place.city;
              _sector = place.sector;
              _street = place.street;
              _streetNumber = place.streetNumber;
            });
          }
        }
      }
```

Declarar los cuatro campos nuevos (`String _city = ''`, etc.) junto a `_lat`/`_lng`.

- [ ] **Step 3: Pasar los campos al guardado**

En el consumer: pasar `city: _city, sector: _sector, street: _street, streetNumber:
_streetNumber` a `completeConsumerProfile`. En el provider: añadirlos al mapa del paso de alta
junto a `'lat'`/`'lng'` (líneas 390-391).

- [ ] **Step 4: Quitar la dependencia si queda huérfana**

```bash
grep -rn "package:geocoding" app/lib/
```

Si no quedan usos, quitar `geocoding` de `app/pubspec.yaml` y correr `flutter pub get`.

- [ ] **Step 5: Verificar y commitear**

Run: `cd app && flutter analyze && flutter test`

```bash
git add app/lib/features/onboarding/ app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): el onboarding geocodifica contra la web, no contra Android"
```

---

## Tarea 10: Pantalla para corregir la dirección

Este es el agujero de fondo: hasta ahora la dirección solo se podía poner una vez, en el alta.

**Files:**
- Create: `app/lib/features/settings/address_screen.dart`
- Modify: el router (añadir `path: '/settings/address'`)
- Modify: `app/lib/features/settings/settings_screen.dart` — fila nueva
- Test: `app/test/address_screen_test.dart`

**Interfaces:**
- Consumes: `updateMyAddress` (tarea 8), `GeocodeClient` (tarea 7), `GeocodedPlace` (tarea 6).

- [ ] **Step 1: Escribir el test que falla**

La pantalla debe aceptar inyección para ser testeable (patrón `MyRequestsScreen.myFetch`):

```dart
// app/test/address_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/features/settings/address_screen.dart';

void main() {
  testWidgets('precarga los campos y guarda lo editado', (t) async {
    Map<String, dynamic>? guardado;
    await t.pumpWidget(MaterialApp(
      home: AddressScreen(
        load: () async => {
          'address': 'Calle Primera 12',
          'sector': 'Parque del Este',
          'city': 'Santo Domingo Este',
          'address_reference': '',
        },
        save: (m) async => guardado = m,
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Parque del Este'), findsOneWidget);
    await t.enterText(find.byKey(const Key('campo-referencia')), 'Casa azul');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(guardado!['address_reference'], 'Casa azul');
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `cd app && flutter test test/address_screen_test.dart`
Expected: FAIL — `address_screen.dart` no existe.

- [ ] **Step 3: Implementar la pantalla**

La firma tiene que ser EXACTAMENTE esta, porque el test del paso 1 depende de ella:

```dart
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key, this.load, this.save});

  /// Costura de test (patron de `MyRequestsScreen.myFetch`): sustituye la
  /// lectura de Supabase entera, asi el test pasa filas ya formadas.
  final Future<Map<String, dynamic>?> Function()? load;

  /// Recibe el mismo mapa que se manda a `updateMyAddress`.
  final Future<void> Function(Map<String, dynamic>)? save;

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}
```

Por defecto, `load` lee
`profiles.select('address,city,sector,street,street_number,address_reference,lat,lng')` del
usuario actual y `save` llama a `updateMyAddress`.

Campos y claves (las `Key` son las que usa el test):
- Dirección — `Key('campo-direccion')`, multilínea.
- Sector — `Key('campo-sector')`, `Autocomplete<String>` cuyo `optionsBuilder` filtra
  `sectorsFor(country, city)` de `locations.dart` **pero que acepta texto libre**: no usar
  `DropdownButton`, que es justo lo que rompe el caso de Parque del Este.
- Ciudad — `Key('campo-ciudad')`, mismo patrón.
- Referencia — `Key('campo-referencia')`.
- Botón "Detectar mi ubicación": repite el flujo de la tarea 9 (permiso → `getCurrentPosition`
  con `LocationAccuracy.high` → `GeocodeClient.lookup`) y **pisa** dirección, ciudad, sector,
  calle y número, pero NO la referencia — es una nota humana ("casa azul al lado del colmado")
  que ningún geocodificador puede reproducir. Esa regla ya está decidida en la web
  (`profile.tsx:163-169`); copiarla, no reinventarla.
- Botón "Guardar" con el texto literal `Guardar`.

Usar `VioletHeader` y `_SettingsRow` tal como los usa `settings_screen.dart` — leerla antes y
copiar el estilo, no inventar uno nuevo.

⚠️ El catálogo de sectores hay que portarlo: crear `app/lib/domain/locations.dart` con el
contenido de `src/mocks/locations.ts` de la web traducido a Dart (`Map<String, Map<String,
List<String>>>`). Son 89 líneas.

- [ ] **Step 4: Cablear la ruta y la fila de ajustes**

Añadir `path: '/settings/address'` al router, y en `settings_screen.dart` una `_SettingsRow` con
`Icons.place_outlined`, título "Mi dirección" y subtítulo "Dónde te encuentran los proveedores".
Colocarla arriba, junto a las filas de confirmación de cuenta.

- [ ] **Step 5: Verificar y commitear**

Run: `cd app && flutter analyze && flutter test`

```bash
git add app/lib/features/settings/ app/lib/domain/locations.dart app/test/address_screen_test.dart
git commit -m "feat(app): pantalla para corregir la direccion despues del alta"
```

---

## Tarea 11: La burbuja de dirección abre el mapa

**Files:**
- Modify: `app/lib/features/chat/widgets/bubbles.dart:186-225`
- Test: `app/test/address_bubble_test.dart`

**Interfaces:**
- Consumes: `splitMapLink` (tarea 6).

- [ ] **Step 1: Escribir el test que falla**

`buildBubble` es una FUNCION de nivel superior, no una clase de widget. Crear
`app/test/address_bubble_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/domain/chat.dart';
import 'package:jayalo/features/chat/widgets/bubbles.dart';

Widget _host(ChatMessage m) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => buildBubble(
            ctx,
            m,
            own: false,
            groupEnd: true,
            peerAvatarUrl: null,
            onImageTap: (_) {},
            onQuickAnswer: (_, __) {},
            canAnswerQuick: false,
          ),
        ),
      ),
    );

ChatMessage _msg(String body) => ChatMessage(
      id: 'm1',
      senderId: 'u1',
      kind: 'address',
      body: body,
      createdAtRaw: '2026-08-04T12:00:00Z',
    );

void main() {
  const url = 'https://www.google.com/maps/search/?api=1&query=18.48,-69.85';

  testWidgets('con enlace: sale el boton y la URL cruda NO se pinta', (t) async {
    await t.pumpWidget(_host(_msg('Calle Primera 12\nParque del Este\n$url')));
    expect(find.text('Abrir en el mapa'), findsOneWidget);
    expect(find.text('Calle Primera 12\nParque del Este'), findsOneWidget);
    expect(find.text(url), findsNothing);
  });

  testWidgets('sin enlace: la burbuja se ve como siempre', (t) async {
    await t.pumpWidget(_host(_msg('Calle Primera 12')));
    expect(find.text('Abrir en el mapa'), findsNothing);
    expect(find.text('Calle Primera 12'), findsOneWidget);
  });
}
```

⚠️ Verificar los nombres reales de los parámetros de `buildBubble` antes de correr — están en
`bubbles.dart:33-42`.

- [ ] **Step 2: Correr y verificar que falla**

Run: `cd app && flutter test test/address_bubble_test.dart`
Expected: FAIL — hoy pinta el cuerpo entero como texto plano.

- [ ] **Step 3: Implementar**

En `bubbles.dart`, dentro del `if (m.kind == 'address')`, sustituir
`Text(m.body, ...)` por el resultado de `splitMapLink(m.body)`: el texto arriba y, si hay
`mapUrl`, un `InkWell` con `Icons.map_outlined` + "Abrir en el mapa" que llame a
`launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)`.

⚠️ `url_launcher` ya es dependencia (lo usa el onboarding). El `Text(m.body)` de la línea 221 lo
comparten TODOS los kinds — cambiar solo la rama de `address`, no la común.

- [ ] **Step 4: Verificar y commitear**

Run: `cd app && flutter analyze && flutter test`

```bash
git add app/lib/features/chat/widgets/bubbles.dart app/test/address_bubble_test.dart
git commit -m "feat(app): la burbuja de direccion abre el mapa"
```

---

## Tarea 12: Guion de smoke

**Files:**
- Create: `app/docs/qa/2026-08-04-smoke-direccion-y-mapa.md`

Ningún test cubre el camino real (GPS → endpoint → formulario → chat). Escribir el guion con
casillas, incluyendo:

- Detectar ubicación en el alta y comprobar que el sector sale **"Parque del Este"**, no "Las
  Américas". Este es el caso que reportó el PO y es el criterio de aceptación de todo el plan.
- Corregir la dirección desde `/settings/address` y ver que persiste al salir y volver.
- Compartir "Mi ubicación" en el chat y comprobar que llega con "Abrir en el mapa" y que el
  enlace cae en el sitio correcto.
- Compartir "Enviar dirección del local" como proveedor: mismo enlace, con el nombre del negocio
  arriba.
- Con el modo avión: detectar ubicación falla y deja escribir la dirección a mano.
- Un cliente registrado por la WEB comparte su dirección en la app: debe llevar enlace también.

```bash
git add app/docs/qa/2026-08-04-smoke-direccion-y-mapa.md
git commit -m "docs(app): guion de smoke de direccion precisa y enlace al mapa"
```

---

## Riesgos anotados

- **El catálogo de sectores queda duplicado** en `src/mocks/locations.ts` y
  `app/lib/domain/locations.dart`. Divergirán. Se acepta porque la app no puede importar TS; si
  molesta, el paso siguiente es servirlo desde `app_settings` y cachearlo.
- **Nominatim es gratuito y sin SLA.** El cliente devuelve `empty` y el usuario escribe a mano,
  así que una caída degrada pero no bloquea. Si el volumen crece, toca un geocodificador de pago.
- **La dirección de los usuarios ya registrados no se arregla sola.** Quedan con el texto tímido
  hasta que entren a `/settings/address`. No se plantea migración de datos: no hay forma fiable de
  re-geocodificar sin coordenadas buenas, y muchos perfiles viejos no tienen `lat`/`lng`.
