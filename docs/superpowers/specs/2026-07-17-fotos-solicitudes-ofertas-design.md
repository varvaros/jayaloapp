# Fotos en solicitudes y ofertas — paridad móvil (jayalo-app)

Fecha: 2026-07-17
Estado: aprobado (PO)
Repos afectados: **solo jayalo-app** (Flutter). Cero cambios en jayalo-main / backend.

## Problema

La web (jayalo.com) ya permite adjuntar fotos en los dos flujos del marketplace:

- **Solicitudes** (cliente): `src/routes/requests/new.tsx` con `ImageDropStrip`, hasta 2
  fotos, subidas al bucket `business-logos`, guardadas en `customer_requests.image_urls[]`.
  Además las fotos se mandan al endpoint de IA como entrada multimodal — **el modelo las
  ve** (`chat-stream.ts` L408-420 las empuja como `type: "image_url"`).
- **Ofertas** (proveedor): `src/components/provider/RequestRespondSection.tsx`, hasta
  `MAX_PRODUCT_PHOTOS`=5 fotos → `provider_offers.image_urls[]`.

La app móvil (jayalo-app) tiene **cero soporte de fotos** en ambos flujos:

- `app/lib/features/client/create_request_screen.dart` — de hecho *rechaza* fotos: cuando la
  IA emite un turno `image_request`, la app responde automáticamente *"No puedo enviar foto
  ahora, sigamos sin foto"* (marcado como "v1 sin fotos").
- `app/lib/features/provider/request_detail_screen.dart` — solo precio/mensaje, sin fotos.

## Contexto que hace esto barato

- **Las columnas ya existen** en la BD (la web las escribe). `submitRequest` y `makeOffer` en
  `app/lib/data/repos.dart` **ya escriben `image_urls: []`** (vacío) — solo falta llenarlo.
- **El endpoint de IA ya acepta y ve la foto**: `imageDataUrl` / `imageDataUrl2` (base64 data
  URL, máx 8 MB c/u) en el body de `/api/ai/chat-stream`; el modelo los recibe como
  multimodal. La app solo debe mandarlos.
- **`image_picker: ^1.2.1` ya está en el pubspec y ya se usa** en el onboarding
  (`provider_onboarding_screen.dart`: `_pickPhoto(ImageSource)` + `uploadBusinessLogo`).
- El helper de subida `uploadBusinessLogo` (repos.dart L377) ya sube al bucket `business-logos`
  y devuelve URL pública — patrón a replicar.

**Consecuencia: cero migraciones, cero cambios de backend. Solo Flutter.**

## Diseño

### 1. Infraestructura compartida (nueva, en `app/lib/data/repos.dart`)

Espeja `src/lib/image/uploadRequestImage.ts` de la web (subir al bucket, guardar URL, nunca
base64 en la BD):

```dart
Future<String> uploadRequestImage(String filePath); // {uid}/requests/<ts>-<rand>.jpg
Future<String> uploadOfferImage(String filePath);   // {uid}/offers/<ts>-<rand>.jpg
```

Ambos suben al bucket **`business-logos`** (reusado, como la web) con prefijo de ruta distinto,
`contentType` inferido de la extensión, y devuelven `getPublicUrl`.

### 2. Validación pura (nueva, `app/lib/domain/image_pick.dart`) — TDD

Función pura testeable que espeja `validateImageFile` de la web (`src/lib/uploadGuards.ts`):

```dart
sealed class ImagePickResult { ok | error(String message) }
ImagePickResult validatePickedImage({required int sizeBytes, required String path, required int currentCount, required int maxCount});
```

Constantes espejo de la web: máx **5 MB** por foto, extensiones `jpg/jpeg/png/webp`. El tope de
cantidad lo pasa el llamador (2 en solicitud, 5 en oferta). Mensajes en español, idénticos en
intención a los de la web ("La imagen supera 5 MB…", "Formato no permitido. Usa JPG, PNG o
WEBP.").

**Nota:** `image_picker` ya entrega imágenes recomprimidas (`maxWidth: 1200, imageQuality: 85`),
así que el chequeo de 5 MB rara vez disparará — pero se mantiene por paridad y defensa.

### 3. Superficie A — Oferta del proveedor (`request_detail_screen.dart`)

Lo mecánico. Espejo de `RequestRespondSection`:

- Sección "Fotos de tu producto (hasta 5)" con botón elegir/tomar (galería + cámara vía
  `ImageSource`), grilla de miniaturas con botón de quitar cada una.
- Las fotos se guardan como rutas de archivo locales (`XFile.path`) durante la edición.
- Al enviar la oferta: `Future.wait` de `uploadOfferImage(path)` para cada una → lista de URLs
  → pasar a `makeOffer(imageUrls: [...])` (nuevo parámetro opcional, default `[]`).
- Tope: **5** fotos.

### 4. Superficie B — Crear solicitud, flujo con IA (`create_request_screen.dart`)

Dos cambios:

**a) La IA ve la foto (reemplaza el stub):** el `AiClient.sendTurn` gana parámetros
`imageDataUrl` / `imageDataUrl2` (base64 data URL, opcionales) que viajan en el body igual que
la web. Cuando la IA emite `image_request`, en vez de auto-rechazar, la app muestra un botón
"Tomar/elegir foto"; al elegirla se convierte a base64 data URL y se guarda en el estado de la
pantalla. **Una vez elegida, ese base64 se incluye en el body de TODOS los turnos siguientes**
(no solo el inmediato) — es el contrato de la web: el cliente manda `imageDataUrl`/`imageDataUrl2`
en cada POST y el servidor decide a qué mensaje del historial adjuntarla
(`chat-stream.ts` L408: la pega al primer mensaje de usuario, una sola vez). El primer slot
libre es `imageDataUrl`, el segundo `imageDataUrl2`.

**b) Adjuntar espontáneo:** un botón de adjuntar foto siempre visible en la barra de entrada
(no solo cuando la IA lo pide), respetando el tope de 2.

**Al enviar la solicitud:** las fotos recolectadas (rutas locales / bytes) se suben con
`uploadRequestImage` → URLs → `submitRequest(imageUrls: [...])` (nuevo parámetro opcional).

Tope: **2** fotos (paridad con `imageDataUrl` + `imageDataUrl2` de la web).

**Modelo de estado:** la pantalla mantiene una lista de hasta 2 fotos pendientes (cada una con
su `XFile` local y su base64 cacheado para no releer). El base64 va a la IA; la ruta local se
sube al storage al enviar.

### 5. Cambios de firma en `repos.dart`

```dart
Future<void> submitRequest({..., List<String> imageUrls = const []});
Future<void> makeOffer({..., List<String> imageUrls = const []});
```

En ambos, `'image_urls': imageUrls` en vez del `[]` hardcodeado.

## Fuera de alcance (YAGNI)

- Recorte / edición de imagen (la web tampoco recorta para solicitudes ni ofertas).
- Bucket nuevo — se reusa `business-logos` (como la web).
- Base64 en la BD — siempre se sube a storage y se guarda la URL.
- Reordenar fotos por drag — la web no lo tiene para estos flujos.
- Drag & drop de escritorio — es una app móvil táctil; no aplica.

## Verificación

- **Unit (TDD):** `validatePickedImage` — tope de cantidad, tamaño > 5 MB, extensión no
  permitida, caso feliz. `flutter test`.
- **`flutter analyze`** en 0.
- **Device E2E (Redmi):**
  1. Oferta: elegir 2 fotos → aparecen miniaturas → quitar una → enviar → confirmar en la web
     (o por query) que `provider_offers.image_urls` tiene la URL subida y la imagen carga.
  2. Solicitud: mandar una foto de algo concreto (ej. un objeto roto) en el flujo de IA →
     confirmar que la IA **la referencia** en su respuesta (prueba de que la ve) → enviar →
     confirmar `customer_requests.image_urls` poblado.

## Riesgos / notas

- El trigger `prevent_base64_image_urls` de la web cubre solo `provider_products`, no
  `provider_offers` ni `customer_requests` — pero como siempre subimos a storage y guardamos
  URL (nunca base64), no es un problema. No introducir base64 en los inserts.
- `image_picker` en Android puede devolver rutas de caché temporales; subir de inmediato al
  enviar (no guardar referencias de largo plazo).
