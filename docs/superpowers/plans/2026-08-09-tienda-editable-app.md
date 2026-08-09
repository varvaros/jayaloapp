# Tienda editable desde la app — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edición nativa en "Mi negocio": logo, portada, descripción, chips de
servicios, y CRUD de productos/servicios (con el molde completo de la oferta
para autocompletar), paquetes y trabajos anteriores.

**Architecture:** Todo en sitio sobre `my_business_screen.dart` con el patrón
«+» solo-en-vacío / tocar-lo-lleno / mantener-para-borrar. Escrituras nuevas en
`repos.dart` (thin, inyectables en las pantallas para testear con dobles, como
`loadPackages` en `CreditShopScreen`). Dos migraciones SQL que NO se aplican
hasta la tarea final (gate PO). El molde de oferta viaja en
`provider_products.offer_defaults jsonb`.

**Tech Stack:** Flutter + supabase_flutter; Supabase Postgres/Storage
(buckets `business-logos` y `provider-products`, RLS "primera carpeta = uid").

**Spec:** `docs/superpowers/specs/2026-08-09-tienda-editable-app-design.md`

## Global Constraints

- Repo APP = worktree `C:\Users\ac\Downloads\jayalo-app-playbilling` (rama
  `feat/play-billing`), código en `app/`. NO pushear, NO mergear.
- **NUNCA `dart format`** (la máquina usa estilo "tall" y reformatea el repo).
- **NUNCA `comando | tail`** para verificar: se traga el exit code. Redirigir a
  fichero y mirar `$?`.
- `flutter analyze` = 0 y `flutter test` completo verde antes de cada commit.
- En `flutter test` el texto mide ~2×: los widget tests usan superficies altas
  (`tester.view.physicalSize`) si un Column se desborda.
- Tokens de color: `JayaloColors` (`core/brand.dart`). No existe clase `Brand`.
- Escrituras supabase: sin try/catch silencioso — dejar propagar o reportar vía
  `core/error_reporter.dart`. Los toasts de error van tras el `catch` de la
  PANTALLA, nunca en repos.
- Guard "sin guardar" es una PILA (`core/unsaved_guard.dart`): toda pantalla
  nueva que edite debe adquirir/soltar como hace `add_store_item_screen.dart`.
- Imágenes: SIEMPRE URL pública en la BD, nunca base64. Validación paridad web:
  jpg/jpeg/png/webp, máx. **5 MB** (`MAX_IMAGE_MB` de `uploadGuards.ts`).
- Migraciones: SOLO escribir los ficheros. Aplicarlas a prod es la tarea 11,
  con OK explícito del PO.
- Copy en español neutral-dominicano como el existente («Añadir», «Quitar»,
  «RD$»).

## Lo que YA existe (no reconstruir)

- `BusinessCoverHero` (`features/shared/business_cover_hero.dart`): portada +
  logo + nombre, con degradado de fallback.
- Agregador «tarjeta vacía con ＋» en Mi negocio (PO 08-05) →
  `add_store_item_screen.dart` con kinds `producto`/`servicio`/`trabajo`,
  fotos a Storage con caché anti-reintento, y `saveProductToStore(...)` /
  alta de portafolio en `repos.dart`.
- «De mi tienda» y «Cargar trabajos anteriores» en el formulario de oferta
  (`request_detail_screen.dart`: `_pickFromStore`, `_pickFromPortfolio`,
  `_applyStoreProduct`) — prellenan precio/rango, color, condición, los 3
  booleanos de logística y fotos.
- `myStoreProducts` (con `storeProductCols`), `myPortfolioItems`,
  `uploadBusinessLogo` (solo sube, NO escribe `logo_url`),
  `_uploadMarketplaceImage` (patrón de ruta con rand), `safe_image_picker.dart`.
- Portafolio ya se PINTA en Mi negocio (`_PortfolioTile`). Paquetes no.
- Tablas: `provider_products` ya tiene `color, price_min, price_max, condition,
  offers_shipping, offers_installation, requires_evaluation, rubro, kind`.
  `provider_packages` (cols web: `id,user_id,business_id,name,description,
  price,items,image_url,is_featured,created_at,updated_at`) y
  `provider_portfolio_items` (`title,description,image_urls,category_id,
  completed_at,position`) existen y la web les hace insert/update como
  authenticated. El servidor ya rechaza datos de contacto en esos payloads
  (la web solo traduce el error) — la app hace lo mismo: traducir, no filtrar.

---

### Task 1: Migraciones SQL (escribir, NO aplicar)

**Files:**
- Create: `supabase/migrations/20260809120000_business_services_chips.sql`
- Create: `supabase/migrations/20260809120001_products_offer_defaults.sql`

**Interfaces:**
- Produces: columna `provider_businesses.services text[] not null default '{}'`
  (SELECT anon+authenticated, UPDATE authenticated, CHECK máx. 20) y columna
  `provider_products.offer_defaults jsonb` (SELECT/INSERT/UPDATE authenticated).

- [ ] **Step 1: Escribir la migración de chips**

```sql
-- 20260809120000_business_services_chips.sql
-- Chips de servicios del perfil (spec 2026-08-09). Publicación directa, sin
-- moderación (decisión PO 08-09 que supera el spec del 07-26).
alter table public.provider_businesses
  add column if not exists services text[] not null default '{}',
  add constraint provider_businesses_services_max20
    check (coalesce(array_length(services, 1), 0) <= 20);

-- Mismo patrón por columna que description: lectura pública, escritura del
-- dueño (la RLS de fila ya limita el UPDATE al user_id propio).
grant select (services) on public.provider_businesses to anon, authenticated;
grant update (services) on public.provider_businesses to authenticated;
```

- [ ] **Step 2: Escribir la migración del molde de oferta**

```sql
-- 20260809120001_products_offer_defaults.sql
-- Molde de oferta del ítem de tienda (spec 2026-08-09): lo que no tiene
-- columna propia viaja en jsonb y la web lo ignora.
alter table public.provider_products
  add column if not exists offer_defaults jsonb;

grant select (offer_defaults), insert (offer_defaults),
      update (offer_defaults) on public.provider_products to authenticated;
```

- [ ] **Step 3: Releer ambos ficheros** comprobando: `if not exists`, grants por
  columna (no de tabla), y que NINGÚN paso los aplica a prod.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260809120000_business_services_chips.sql supabase/migrations/20260809120001_products_offer_defaults.sql
git commit -m "feat(db): migraciones services chips y offer_defaults (sin aplicar)"
```

---

### Task 2: Repos de identidad del negocio

**Files:**
- Modify: `app/lib/data/repos.dart` (junto a `uploadBusinessLogo`, ~:1557)
- Test: `app/test/business_identity_repos_test.dart`

**Interfaces:**
- Consumes: `supa`, `File`, `FileOptions` ya importados en `repos.dart`;
  `_imageContentType(ext)` existente.
- Produces (firmas exactas que consumen las tareas 3-5):

```dart
Future<String> updateBusinessLogo(String businessId, String filePath);
Future<String> updateBusinessCover(String businessId, String filePath);
Future<void> clearBusinessLogo(String businessId);
Future<void> clearBusinessCover(String businessId);
Future<void> updateBusinessDescription(String businessId, String description);
Future<void> updateBusinessServices(String businessId, List<String> services);
String businessImagePath({required String uid, required String businessId,
    required String kind, required String ext, required int ts}); // pura, testeable
```

- [ ] **Step 1: Test de la función pura de rutas** (lo único unit-testeable sin
  supabase; el resto se cubre por inyección en los widget tests de las tareas
  3-5):

```dart
// test/business_identity_repos_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/data/repos.dart';

void main() {
  test('businessImagePath espeja la ruta de la web y arranca con el uid', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'covers', ext: 'png', ts: 123);
    expect(p, 'u1/covers/b1-123.png'); // RLS: primera carpeta = auth.uid()
  });
  test('businessImagePath para logo no repite el patrón viejo', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'logos', ext: 'jpg', ts: 9);
    expect(p, 'u1/logos/b1-9.jpg');
  });
}
```

- [ ] **Step 2: Correr y ver fallar** — `flutter test test/business_identity_repos_test.dart`
  → FAIL (símbolo no existe).

- [ ] **Step 3: Implementar en repos.dart**

```dart
/// Ruta de imagen de negocio. Espeja la web (`uploadCover` en
/// `business.$id.tsx`): la RLS del bucket exige primera carpeta = auth.uid().
String businessImagePath({required String uid, required String businessId,
    required String kind, required String ext, required int ts}) =>
    '$uid/$kind/$businessId-$ts.$ext';

Future<String> _uploadBusinessImage(
    String businessId, String filePath, String kind, String column) async {
  final uid = supa.auth.currentUser!.id;
  final dot = filePath.lastIndexOf('.');
  final ext = (dot == -1 ? 'jpg' : filePath.substring(dot + 1).toLowerCase());
  final path = businessImagePath(
      uid: uid, businessId: businessId, kind: kind, ext: ext,
      ts: DateTime.now().millisecondsSinceEpoch);
  await supa.storage.from('business-logos').upload(path, File(filePath),
      fileOptions: FileOptions(
          upsert: true, contentType: _imageContentType(ext)));
  final url = supa.storage.from('business-logos').getPublicUrl(path);
  await supa.from('provider_businesses')
      .update({column: url}).eq('id', businessId);
  return url;
}

Future<String> updateBusinessLogo(String businessId, String filePath) =>
    _uploadBusinessImage(businessId, filePath, 'logos', 'logo_url');
Future<String> updateBusinessCover(String businessId, String filePath) =>
    _uploadBusinessImage(businessId, filePath, 'covers', 'cover_url');

Future<void> clearBusinessLogo(String businessId) async => supa
    .from('provider_businesses').update({'logo_url': null}).eq('id', businessId);
Future<void> clearBusinessCover(String businessId) async => supa
    .from('provider_businesses').update({'cover_url': null}).eq('id', businessId);

Future<void> updateBusinessDescription(
        String businessId, String description) async =>
    supa.from('provider_businesses')
        .update({'description': description.trim()}).eq('id', businessId);

Future<void> updateBusinessServices(
        String businessId, List<String> services) async =>
    supa.from('provider_businesses')
        .update({'services': services}).eq('id', businessId);
```

- [ ] **Step 4: Añadir `services` a `myBusinessProfile`** — sumar `services` al
  string del `.select(...)` y al record de retorno como
  `List<String> services` (`(biz['services'] as List?)?.cast<String>() ?? const []`).
  Ojo: hasta la tarea 11 la columna NO existe en prod — el select fallaría.
  Protegerlo igual que hizo la tanda del 08-01 con columnas nuevas: pedir
  `services` en un select APARTE con `catch` que devuelve lista vacía si la
  columna no existe todavía, y un `// TODO(tarea-11):` para plegarlo al select
  principal tras aplicar la migración. Lo mismo aplica a la tienda pública
  (tarea 5).

- [ ] **Step 5: Correr tests + analyze** — `flutter test test/business_identity_repos_test.dart`
  PASS y `flutter analyze` 0.

- [ ] **Step 6: Commit** — `git commit -m "feat(app): repos de identidad del negocio (logo/portada/descripcion/chips)"`

---

### Task 3: Portada y logo editables en Mi negocio

**Files:**
- Modify: `app/lib/features/shared/business_cover_hero.dart`
- Modify: `app/lib/features/provider/my_business_screen.dart`
- Test: `app/test/business_cover_edit_test.dart`

**Interfaces:**
- Consumes: `updateBusinessLogo/Cover`, `clearBusinessLogo/Cover` (Task 2);
  `safe_image_picker.dart`; `BusinessCoverHero` existente.
- Produces: `BusinessCoverHero` gana parámetros opcionales
  `VoidCallback? onCoverTap, onLogoTap, onCoverLongPress, onLogoLongPress` y
  `bool coverBusy = false, logoBusy = false`. Con callback nulo se comporta
  EXACTO como hoy (la tienda pública no cambia).

- [ ] **Step 1: Widget test del «+» solo-en-vacío**

```dart
// test/business_cover_edit_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo/features/shared/business_cover_hero.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('sin portada y editable: aparece + Añadir portada', (t) async {
    await t.pumpWidget(_wrap(BusinessCoverHero(
        name: 'Mi negocio', coverUrl: null, onCoverTap: () {})));
    expect(find.text('Añadir portada'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
  });
  testWidgets('con portada y editable: NO hay + encima', (t) async {
    await t.pumpWidget(_wrap(BusinessCoverHero(
        name: 'Mi negocio', coverUrl: 'https://x/y.jpg', onCoverTap: () {})));
    expect(find.text('Añadir portada'), findsNothing);
  });
  testWidgets('sin callbacks (tienda pública): cero indicios de edición',
      (t) async {
    await t.pumpWidget(_wrap(
        const BusinessCoverHero(name: 'Ajeno', coverUrl: null)));
    expect(find.text('Añadir portada'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });
  testWidgets('tocar la portada editable dispara el callback', (t) async {
    var taps = 0;
    await t.pumpWidget(_wrap(BusinessCoverHero(
        name: 'N', coverUrl: 'https://x/y.jpg', onCoverTap: () => taps++)));
    await t.tap(find.byType(BusinessCoverHero));
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Correr y ver fallar** (parámetros no existen).

- [ ] **Step 3: Implementar en `BusinessCoverHero`** — envolver el Stack actual
  en `GestureDetector(onTap: onCoverTap, onLongPress: onCoverLongPress)` solo
  si el callback no es nulo; el avatar/logo con su propio GestureDetector.
  «+ Añadir portada»: pill centrado (`Icons.add` + texto) visible solo si
  `!hasCover && onCoverTap != null`. En el logo vacío editable: badge circular
  con `Icons.add` en la esquina. `coverBusy/logoBusy` pintan un
  `CircularProgressIndicator` pequeño superpuesto. Cero cambios cuando todos
  los parámetros nuevos van por defecto.

- [ ] **Step 4: Cablear Mi negocio** — en `my_business_screen.dart`, donde se
  construye el hero (`~:246`): pasar callbacks solo-dueño. Flujo de cada uno:

```dart
Future<void> _changeCover() async {
  final file = await pickImageSafely(context); // safe_image_picker existente
  if (file == null || !mounted) return;
  final err = validateLocalImage(file); // helper nuevo: ext + <=5MB
  if (err != null) return _toast(err);
  setState(() => _coverBusy = true);
  try {
    final url = await widget.updateCover(_biz.id, file.path);
    if (mounted) setState(() => _coverUrl = url);
  } catch (e) {
    reportError('updateBusinessCover', e);
    if (mounted) _toast('No se pudo subir la portada. Intenta de nuevo.');
  } finally {
    if (mounted) setState(() => _coverBusy = false);
  }
}
```

  `updateCover`/`updateLogo`/`clearCover`/`clearLogo` entran como parámetros
  inyectables del widget con default = las funciones reales de repos (patrón
  `CreditShopScreen.loadPackages`). Long-press con contenido → diálogo
  «¿Quitar la portada?» (patrón confirm existente) → `clearCover` →
  setState(null). `validateLocalImage` (ext jpg/jpeg/png/webp, tamaño ≤ 5 MB
  vía `File(...).lengthSync()`) vive en `features/shared/` y lo REUSAN las
  tareas 6-8.

- [ ] **Step 5: Test de cableado con doble** — en el mismo fichero de test:
  montar la pantalla del dueño con `updateCover` inyectado que devuelve una URL
  y afirmar que se llamó con el id del negocio (mismo montaje con fakes que ya
  usan los tests existentes de Mi negocio — copiar su setup).

- [ ] **Step 6: Suite + analyze + commit** —
  `git commit -m "feat(app): portada y logo editables en Mi negocio"`

---

### Task 4: Descripción con bottom sheet

**Files:**
- Modify: `app/lib/features/provider/my_business_screen.dart`
- Test: `app/test/business_about_edit_test.dart`

**Interfaces:**
- Consumes: `updateBusinessDescription` (Task 2), descripción ya presente en
  `myBusinessProfile`.
- Produces: sección «Sobre el negocio» editable; helper
  `Future<String?> showTextEditorSheet(BuildContext, {required String title,
  required String initial, int maxLines = 6})` en
  `app/lib/features/shared/text_editor_sheet.dart` (lo reusa la tarea 7 para
  descripciones largas).

- [ ] **Step 1: Test** — tres casos: (a) sin descripción el dueño ve
  «+ Añadir descripción»; (b) con descripción se ve el texto y NO el «+»;
  (c) tocar abre el sheet, escribir y guardar llama al doble inyectado con el
  texto nuevo (usar `tester.enterText` + botón «Guardar»).

- [ ] **Step 2: Ver fallar.**

- [ ] **Step 3: Implementar** — `showTextEditorSheet` devuelve el texto o null
  si se canceló: `showModalBottomSheet` + `TextField(maxLines: maxLines,
  autofocus: true)` + fila Cancelar/Guardar. En Mi negocio, la fila de
  descripción (texto o «+ Añadir descripción» con `Icons.add`) →
  `showTextEditorSheet(title: 'Sobre el negocio', initial: _desc ?? '')` →
  si cambió: `await widget.updateDescription(_biz.id, texto)` con el mismo
  patrón busy/catch/toast de la Task 3, y setState local.

- [ ] **Step 4: Suite + analyze + commit** —
  `git commit -m "feat(app): descripcion del negocio editable en la app"`

---

### Task 5: Chips de servicios

**Files:**
- Create: `app/lib/features/shared/service_chips_editor.dart`
- Modify: `app/lib/features/provider/my_business_screen.dart`
- Modify: `app/lib/features/client/provider_store_screen.dart`
- Modify: `app/lib/data/repos.dart` (query de la tienda pública + `services`)
- Test: `app/test/service_chips_test.dart`

**Interfaces:**
- Consumes: `updateBusinessServices` y `services` de `myBusinessProfile`
  (Task 2); `searchFold` (`domain/search_fold.dart`).
- Produces:
  `Future<List<String>?> showServiceChipsEditor(BuildContext, {required List<String> initial})`
  (null = cancelado) y la constante `kMaxServiceChips = 20`,
  `kMaxServiceChipLen = 60` exportadas desde `service_chips_editor.dart`.

- [ ] **Step 1: Tests del editor** (montado directo, sin pantalla):

```dart
testWidgets('añade chip con el teclado y respeta el tope de 60 chars', ...);
testWidgets('no duplica ignorando tildes/mayúsculas (searchFold)', ...);
testWidgets('con 20 chips el campo de añadir se deshabilita y avisa', ...);
testWidgets('quitar con la x elimina el chip', ...);
```

  Casos concretos: añadir «Destapes» dos veces y «destapés» → 1 chip; string
  de 61 chars → recortado o rechazado con aviso (elegir rechazo + toast);
  llegar a 20 → `TextField.enabled == false`.

- [ ] **Step 2: Ver fallar.**

- [ ] **Step 3: Implementar el editor** — bottom sheet con `Wrap` de
  `InputChip(onDeleted: ...)` + `TextField(textInputAction: TextInputAction.done,
  onSubmitted: _add)` + contador «N/20» + Cancelar/Guardar. `_add` hace trim,
  valida longitud ≤ 60, dedupe por `searchFold`, tope 20.

- [ ] **Step 4: Display + cableado** — en Mi negocio, bajo la descripción:
  `Wrap` de `Chip`s o «+ Añadir servicios» si vacío (solo dueño); tocar
  cualquiera abre el editor con la lista actual; al volver no-null →
  `updateBusinessServices` (busy/catch/toast) + setState. En
  `provider_store_screen.dart`: localizar el select del perfil público en
  `repos.dart`, sumar `services` con el MISMO fallback tolerante de la Task 2
  Step 4 (select aparte + catch → `[]` hasta la tarea 11) y pintar el `Wrap`
  de chips (solo lectura, sin «+») bajo la descripción del negocio.

- [ ] **Step 5: Test de la tienda pública** — render con services no vacío
  muestra los chips y `find.byIcon(Icons.add)` → nothing.

- [ ] **Step 6: Suite + analyze + commit** —
  `git commit -m "feat(app): chips de servicios en perfil y tienda publica"`

---

### Task 6: Editor de ítem con el molde de la oferta

**Files:**
- Create: `app/lib/features/shared/offer_field_options.dart`
- Create: `app/lib/domain/offer_defaults.dart`
- Modify: `app/lib/features/provider/add_store_item_screen.dart`
- Modify: `app/lib/features/provider/request_detail_screen.dart` (solo para
  importar las opciones extraídas)
- Modify: `app/lib/data/repos.dart` (`saveProductToStore` ampliado,
  `updateStoreItem`, `deleteStoreItem`, `storeProductCols` + `offer_defaults`)
- Test: `app/test/offer_defaults_test.dart`, `app/test/store_item_editor_test.dart`

**Interfaces:**
- Consumes: `saveProductToStore` existente; selectores de garantía / tiempo de
  entrega / estado del formulario de oferta (`request_detail_screen.dart`,
  bloque «Producto: detalles» `~:114-120`).
- Produces:

```dart
// domain/offer_defaults.dart — puro, sin Flutter.
/// Claves canónicas del jsonb offer_defaults. Las consumen el editor (write),
/// el prellenado de la oferta (read, Task 9) y nada más.
class OfferDefaults {
  static const pricingMode = 'pricing_mode';   // fixed|range|hourly|needs_evaluation
  static const hourlyRate = 'hourly_rate';     // num
  static const estimatedHours = 'estimated_hours'; // num
  static const availability = 'availability';  // String
  static const duration = 'duration';          // String
  static const shippingPrice = 'shipping_price';       // num
  static const installationPrice = 'installation_price'; // num
  static const evaluationPrice = 'evaluation_price';   // num
  static const brand = 'brand';                // String
  static const warranty = 'warranty';          // String (etiqueta del selector)
  static const delivery = 'delivery';          // String (etiqueta del selector)
  static const colors = 'colors';              // List<String>
}
Map<String, dynamic> buildOfferDefaults({...todos los campos nombrados...});
// Devuelve SOLO las claves con valor (sin nulls ni strings vacíos).

// repos.dart
Future<void> saveProductToStore({
  // ...los 8 parámetros actuales igual...
  double? priceMin, double? priceMax, String? condition,
  List<String> colors = const [],
  bool offersShipping = false, bool offersInstallation = false,
  bool requiresEvaluation = false,
  Map<String, dynamic>? offerDefaults,
});
Future<void> updateStoreItem(String id, Map<String, dynamic> payload);
Future<void> deleteStoreItem(String id);
```

- [ ] **Step 1: Tests de `buildOfferDefaults`** (unit, puro):

```dart
test('omite claves vacías y nulas', () {
  final d = buildOfferDefaults(brand: ' Bosch ', warranty: '', hourlyRate: null);
  expect(d, {'brand': 'Bosch'});
});
test('serializa el molde completo de producto', () { /* todas las claves */ });
test('serializa el molde de servicio con pricing_mode hourly', () { ... });
```

- [ ] **Step 2: Ver fallar → implementar `offer_defaults.dart` → ver pasar.**

- [ ] **Step 3: Extraer opciones compartidas** — mover las listas de opciones
  de garantía, tiempo de entrega y estado (Nuevo/Usado) de
  `request_detail_screen.dart` a `offer_field_options.dart` como
  `const List<String> kWarrantyOptions / kDeliveryOptions / kConditionOptions`,
  e importarlas desde la pantalla de oferta (cero cambio de comportamiento;
  correr la suite de oferta existente para probarlo). NO mover widgets.

- [ ] **Step 4: Tests del editor ampliado** (`store_item_editor_test.dart`):
  (a) kind=producto muestra fijo/rango, envío/instalación/evaluación con campo
  de precio al activarse, marca, estado, colores, garantía, entrega;
  (b) kind=servicio muestra los 4 modos + disponibilidad + duración y NO los
  campos de producto; (c) guardar producto llama al doble de
  `saveProductToStore` con `offerDefaults` == mapa esperado campo por campo;
  (d) kind=trabajo queda EXACTO como hoy (sin campos nuevos).

- [ ] **Step 5: Ver fallar → implementar** — `add_store_item_screen.dart`:
  sección «Detalles para tus ofertas (opcional)» plegable
  (`ExpansionTile`) tras el precio, replicando los controles del formulario de
  oferta pero SIN validación obligatoria (es plantilla). El toggle fijo/rango
  reemplaza el campo único de precio para producto; servicio usa un
  `SegmentedButton` con los 4 modos. Guardado: columnas existentes
  (price/min/max, condition en minúscula `nuevo|usado`, color = primer color,
  offers_* booleanos) + `offerDefaults: buildOfferDefaults(...)`. El save real:
  ampliar `saveProductToStore` para escribir las columnas nuevas y
  `offer_defaults`; añadir `offer_defaults` a `storeProductCols`, protegido
  con el MISMO fallback tolerante de la Task 2 Step 4 hasta la tarea 11.
  `updateStoreItem` = `supa.from('provider_products').update(payload).eq('id', id)`;
  `deleteStoreItem` = `.delete().eq('id', id)`.

- [ ] **Step 6: Modo edición + borrado** — `AddStoreItemScreen` gana
  `final Map<String, dynamic>? initial;` — si viene, prellena todo (incluido
  `offer_defaults`) y guarda vía `updateStoreItem`. En Mi negocio: tocar una
  tarjeta de producto/servicio propio abre el editor con `initial`;
  mantener presionada → confirm «¿Eliminar de tu tienda?» → `deleteStoreItem`
  → refresh. Test: prellenado desde `initial` campo por campo + payload del
  update.

- [ ] **Step 7: Suite completa + analyze + commit** —
  `git commit -m "feat(app): editor de item de tienda con molde de oferta"`

---

### Task 7: Sección Paquetes

**Files:**
- Modify: `app/lib/data/repos.dart`
- Create: `app/lib/features/provider/package_editor_screen.dart`
- Modify: `app/lib/features/provider/my_business_screen.dart`
- Test: `app/test/packages_section_test.dart`

**Interfaces:**
- Consumes: `validateLocalImage` (Task 3), `showTextEditorSheet` (Task 4),
  `safe_image_picker`, patrón de guard sin-guardar de `add_store_item_screen`.
- Produces:

```dart
// repos.dart
const packageCols =
    'id,business_id,name,description,price,items,image_url,created_at';
Future<List<Map<String, dynamic>>> myPackages(String businessId);
Future<void> savePackage({String? id, required String businessId,
    required String name, String description = '', double? price,
    required List<String> items, String? imageUrl});
Future<void> deletePackage(String id);
Future<String> uploadPackageImage(String filePath);
// bucket provider-products, ruta '{uid}/packages/{ts}-{rand}.{ext}'
// (espeja `${user.id}/packages/${uuid}` de PackageEditorDialog.tsx:121;
//  el rand-hex del patrón _uploadMarketplaceImage cumple el mismo papel).
```

- [ ] **Step 1: Tests de la sección** — con dobles inyectados en Mi negocio:
  (a) sin paquetes el dueño ve «+ Añadir paquete»; (b) con paquetes se pintan
  nombre y precio y la fila «+ Añadir…» al final; (c) mantener presionado un
  paquete → confirm → llama al doble de `deletePackage`.

- [ ] **Step 2: Tests del editor** — nombre obligatorio (guardar sin nombre →
  aviso y NO llama al repo); items dinámicos (añadir/quitar filas de texto);
  guardar llama a `savePackage` con
  `items` sin vacíos y `price` parseado o null.

- [ ] **Step 3: Ver fallar → implementar repos** — `myPackages` =
  select `packageCols` por `business_id` orden `created_at` desc límite 100.
  `savePackage`: sin `id` → insert (el `user_id` lo pone el default de la
  tabla/RLS; si el insert exige `user_id`, tomarlo de
  `supa.auth.currentUser!.id` — la web lo manda explícito, hacer lo mismo);
  con `id` → update. `uploadPackageImage`: calcado de
  `_uploadMarketplaceImage` cambiando bucket a `provider-products` y prefijo a
  `packages`.

- [ ] **Step 4: Implementar pantalla y sección** —
  `package_editor_screen.dart`: Scaffold con nombre, descripción, precio
  (teclado numérico), lista de items (`TextField` por fila + botón añadir/
  quitar, patrón del PackageEditorDialog web), UNA foto (picker + preview +
  quitar), guard sin-guardar, busy/catch/toast. Sección en Mi negocio entre
  Servicios y Trabajos (orden web), tiles con foto/nombre/precio; tocar →
  editor con `initial`; «+ Añadir paquete» → editor vacío; long-press →
  eliminar con confirm.

- [ ] **Step 5: Suite + analyze + commit** —
  `git commit -m "feat(app): paquetes visibles y editables en Mi negocio"`

---

### Task 8: Trabajos anteriores — editar y borrar

**Files:**
- Modify: `app/lib/data/repos.dart`
- Modify: `app/lib/features/provider/my_business_screen.dart`
- Modify: `app/lib/features/provider/add_store_item_screen.dart`
- Test: `app/test/portfolio_edit_test.dart`

**Interfaces:**
- Consumes: `_PortfolioTile` y el kind `trabajo` del agregador (existen);
  `myPortfolioItems` existente.
- Produces:

```dart
Future<void> updatePortfolioItem(String id, {required String title,
    String? description, required List<String> imageUrls});
Future<void> deletePortfolioItem(String id);
const int kMaxPortfolioPhotos = 8; // MAX_PORTFOLIO_PHOTOS de la web
```

- [ ] **Step 1: Tests** — (a) tocar un `_PortfolioTile` propio abre el editor
  con título/descripción/fotos prellenados; (b) el editor de trabajo rechaza
  la novena foto con aviso («Máximo 8 fotos»); (c) guardar llama a
  `updatePortfolioItem` con las URLs conservadas + nuevas; (d) long-press →
  confirm → `deletePortfolioItem`.

- [ ] **Step 2: Ver fallar → implementar** — repos: update/delete triviales
  sobre `provider_portfolio_items`. `add_store_item_screen` en modo
  `initial` para kind=trabajo: reusar el mecanismo de la Task 6 Step 6
  (mismas `initial` + fotos conservadas estilo `_keptUrls` de la oferta) y el
  tope `kMaxPortfolioPhotos` al elegir fotos (hoy el agregador no lo impone
  para trabajo: imponerlo). Cablear tap/long-press en `_PortfolioTile` solo
  cuando la pantalla es del dueño.

- [ ] **Step 3: Suite + analyze + commit** —
  `git commit -m "feat(app): editar y borrar trabajos anteriores"`

---

### Task 9: Prellenado extendido de la oferta

**Files:**
- Modify: `app/lib/features/provider/request_detail_screen.dart`
  (`_applyStoreProduct` `~:651` y `_cleanSnapshot`)
- Test: `app/test/offer_prefill_from_store_test.dart`

**Interfaces:**
- Consumes: claves de `OfferDefaults` (Task 6); `offer_defaults` ya presente en
  `storeProductCols` (Task 6); `_formSnapshot`/`_cleanSnapshot` existentes.
- Produces: `_applyStoreProduct` mapea el molde completo; tras prellenar,
  `_cleanSnapshot = _formSnapshot()` (spec: elegir de la tienda NO marca el
  formulario como sucio).

- [ ] **Step 1: Tests** — con la pantalla de oferta montada sobre una solicitud
  fake (copiar el setup de los tests de oferta existentes) y un ítem con
  `offer_defaults` completo:
  (a) producto: marca, garantía, entrega, colores (lista completa, sin
  duplicar), precios de envío/instalación/evaluación aparecen en sus campos;
  (b) servicio con `pricing_mode: 'hourly'`: modo por hora activo,
  tarifa + horas + disponibilidad + duración rellenos;
  (c) tras prellenar, el guard de salida NO avisa (snapshot capturado);
  (d) ítem SIN `offer_defaults` (vieja data): se comporta exactamente como hoy
  (test de regresión sobre el mapeo actual precio/color/condición/booleanos).

- [ ] **Step 2: Ver fallar → implementar** — en `_applyStoreProduct`, tras el
  bloque actual:

```dart
final d = (p['offer_defaults'] as Map?)?.cast<String, dynamic>();
if (d != null) {
  final mode = d[OfferDefaults.pricingMode] as String?;
  if (_isService && mode != null) {
    final i = _svcModes.indexOf(mode);
    if (i >= 0) _svcMode = i;
  }
  void setText(TextEditingController c, Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isNotEmpty) c.text = s;
  }
  setText(_hourly, d[OfferDefaults.hourlyRate]);
  setText(_hours, d[OfferDefaults.estimatedHours]);
  setText(_availability, d[OfferDefaults.availability]);
  setText(_duration, d[OfferDefaults.duration]);
  setText(_shipping, d[OfferDefaults.shippingPrice]);
  setText(_installation, d[OfferDefaults.installationPrice]);
  setText(_evaluation, d[OfferDefaults.evaluationPrice]);
  setText(_brand, d[OfferDefaults.brand]);
  setText(_warranty, d[OfferDefaults.warranty]);
  setText(_delivery, d[OfferDefaults.delivery]);
  for (final c in ((d[OfferDefaults.colors] as List?)?.cast<String>() ??
      const <String>[])) {
    if (!_colors.contains(c)) _colors.add(c);
  }
}
```

  y al final del método (fuera del setState, tras `_addKeptUrls`):
  `_cleanSnapshot = _formSnapshot();`.

- [ ] **Step 3: Suite + analyze + commit** —
  `git commit -m "feat(app): la oferta se autocompleta con el molde completo del item"`

---

### Task 10: Cierre — suite completa, analyze, acta

**Files:**
- Modify: `.superpowers/sdd/2026-08-08-play-billing/progress.md` (o ledger
  nuevo `.superpowers/sdd/2026-08-09-tienda-editable/progress.md`)

- [ ] **Step 1:** `flutter analyze > analyze.log 2>&1; echo $?` → 0.
- [ ] **Step 2:** `flutter test > test.log 2>&1; echo $?` → 0 (sin pipes).
- [ ] **Step 3:** Grep anti-regresión de steering (los tests de Play Billing
  vigilan qué ficheros abren el navegador): confirmar que NINGÚN fichero nuevo
  llama a `launchUrl` — esta tanda no debe tocar la lista blanca.
- [ ] **Step 4:** Escribir el acta en el ledger: qué quedó, desvíos, y el
  recordatorio de que los fallbacks tolerantes de `services`/`offer_defaults`
  se pliegan tras la tarea 11.
- [ ] **Step 5: Commit** — `git commit -m "chore(app): acta tienda editable"`

---

### Task 11: Migraciones a prod + smoke (GATE PO)

**⛔ NO ejecutar sin OK explícito del PO en la conversación.**

- [ ] **Step 1:** Pedir OK al PO para aplicar las 2 migraciones de la Task 1 a
  prod (proyecto Supabase `mfaiklvobnvgusbcssbx`, vía MCP `apply_migration`).
- [ ] **Step 2:** Aplicarlas y verificar con un select de columnas
  (`information_schema.columns`) que `services` y `offer_defaults` existen.
- [ ] **Step 3:** Plegar los fallbacks tolerantes (Task 2 Step 4 / Task 5 /
  Task 6): sumar las columnas al select principal y borrar los catch — commit
  `refactor(app): selects directos tras aplicar migraciones`.
- [ ] **Step 4:** Compilar APK release (OJO: mirar el `versionCode` instalado
  en el device con `dumpsys` y pasar `--build-number` mayor; el 08-09 quedó
  en 15) e instalar con `adb install -r`.
- [ ] **Step 5:** Smoke en device por adb (receta en memoria
  `jayalo-conducir-device-por-adb`): portada, logo, descripción, chips, alta y
  edición de producto con molde, paquete, trabajo, y una oferta prellenada
  «De mi tienda» de punta a punta.
