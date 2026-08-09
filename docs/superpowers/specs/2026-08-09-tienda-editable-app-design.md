# Tienda editable desde la app — diseño (2026-08-09)

## Contexto

"Mi negocio" en la app es solo lectura desde la V1 (decisión 2026-07-20); editar
exige el editor web embebido (`?embed=app`). El PO decide ahora traer la edición
a la app de forma nativa. La moderación admin que contemplaba el spec del
2026-07-26 queda descartada: **publicación directa**, como funciona hoy la
descripción en la web.

## Alcance

Editable nativamente desde "Mi negocio":

1. Foto de perfil (logo) y portada.
2. Sobre el negocio: descripción + chips de servicios (etiquetas cortas).
3. Catálogo: productos y servicios, **con el molde completo de la oferta** para
   autocompletar al ofertar.
4. Paquetes y trabajos anteriores (secciones nuevas en la app).

**Fuera de alcance:** nombre, contacto y ubicación (siguen en el editor
embebido); CRUD nativo de nada más; pintar los chips de servicios en la web
pública (tarea aparte, lado web); moderación admin.

## Principio de interacción

Todo ocurre en sitio sobre "Mi negocio", sin pantalla de edición aparte:

- **Área vacía** → indicador **«+»** con etiqueta («+ Añadir portada»,
  «+ Añadir descripción», «+ Añadir producto»…). Nunca un lápiz.
- **Área con contenido** → se toca directo y abre su editor (selector de foto o
  bottom sheet). Sin íconos superpuestos sobre fotos.
- Secciones de catálogo con contenido: fila «+ Añadir…» al final para crear.
- Mantener presionado un ítem (o foto de portada/logo) → eliminar/quitar, con
  confirmación.
- Solo el dueño ve los «+» y las áreas tocables. La tienda pública que ve un
  cliente (`provider_store_screen`) no cambia en nada; test explícito de que no
  muestra ningún «+».

## 1. Foto de perfil y portada

- Tocar (o «+») abre el selector de imagen (galería/cámara; infra `image_picker`
  existente del flujo de fotos de ofertas).
- **Paridad exacta con la web** (`uploadCover` de `business.$id.tsx`): bucket
  `business-logos`, ruta `{userId}/covers/{negocioId}-{timestamp}.{ext}` — la
  RLS del bucket exige que la primera carpeta sea el `auth.uid()` —, URL pública
  y `UPDATE` de `cover_url`/`logo_url` en `provider_businesses`. Misma
  validación de tipo y tamaño que `validateImageFile` de la web.
- Mientras sube: spinner sobre el área. Si falla: toast con reintento; la imagen
  anterior no se pierde.
- «Quitar» deja el degradado de marca que `BusinessCoverHero` ya pinta como
  fallback.

## 2. Sobre el negocio: descripción + chips de servicios

- **Descripción**: bottom sheet con campo multilínea; guarda directo en
  `provider_businesses.description` (sin moderación, igual que la web hoy).
- **Chips de servicios**: etiquetas cortas solo-título («Destapes»,
  «Instalación de inodoros»…). Editor de chips: añadir con el teclado, quitar
  con ×. Límites: **máx. 20 chips, 60 caracteres c/u** (heredados del spec
  07-26, que en lo demás queda superado).
- **Migración 1**: `provider_businesses.services text[]` (no existe). Grant de
  SELECT a anon+authenticated y UPDATE por columna al patrón existente de
  `description`.
- Los chips se muestran en "Mi negocio" y en la tienda pública **de la app**.

## 3. Catálogo: productos y servicios con el molde de la oferta

Requisito del PO: los ítems del catálogo llevan los campos de la oferta para
que al usarlos se autocomplete.

- **Crear/editar** (evolución de `add_store_item_screen`): además de nombre,
  descripción, fotos y rubro, el formulario tiene los campos del formulario de
  oferta (`request_detail_screen`), según el tipo:
  - *Producto*: precio fijo o rango; envío / instalación / evaluación con sus
    precios; marca; estado (nuevo/usado); colores; garantía; tiempo de entrega.
  - *Servicio*: los 4 modos de precio (`fixed`, `range`, `hourly` + horas
    estimadas, `needs_evaluation`); disponibilidad; duración.
  - Todo opcional salvo el nombre: es una plantilla, no una oferta.
- **Migración 2**: `provider_products.offer_defaults jsonb`. Las columnas
  visibles actuales (título, descripción, precio, fotos, kind, rubro) se
  conservan tal cual — la web las sigue leyendo y **ignora** el jsonb. Un campo
  nuevo en la oferta mañana no exige migración nueva.
- **Autocompletar al ofertar**: en el formulario de oferta, «Usar de mi tienda»
  (visible solo si el proveedor tiene ítems del `kind` que pide la solicitud).
  Elegir uno prellena todos los campos y las fotos; todo editable antes de
  enviar. La oferta resultante es una oferta normal — el ítem solo ahorra
  tecleo. El snapshot de "sin guardar" (`_formSnapshot`) debe capturar el
  estado tras el prellenado, no marcarlo como sucio.

## 4. Paquetes y trabajos anteriores

- Secciones nuevas en "Mi negocio" (hoy la app no las pinta):
  - **Paquetes** (`provider_packages`): título, descripción, precio, lista de
    ítems incluidos, una foto (`image_url`).
  - **Trabajos anteriores** (`provider_portfolio_items`): título, descripción
    opcional, fotos (`image_urls`, mismo tope `MAX_PHOTOS` de la web).
- Paridad de campos con `PackageEditorDialog` y `PortfolioEditorDialog` de la
  web. Mismas tablas, mismos buckets/rutas de imagen que use la web para cada
  una (verificar en el plan).
- Mismo patrón de interacción que el resto (§ Principio).

## 5. Errores y estados

- Escrituras con el patrón del reporter de errores (I-1 cerrado el 08-01):
  nada de try/catch silencioso sobre supabase.
- Fallo de red o subida → toast + posibilidad de reintentar sin perder lo
  escrito.
- Cada guardado refresca su sección en sitio, sin recargar la pantalla entera.

## 6. Tests

- Widget tests por área: el «+» aparece solo cuando el área está vacía; tocar
  abre el editor correcto; guardar llama al repo con el payload esperado.
- Prellenado oferta←ítem: campo por campo, incluidos los modos de precio y las
  fotos.
- La tienda pública del cliente no muestra ningún «+» ni área editable.
- Chips: límites de 20/60 aplicados en el editor.

## Resumen de trabajo por repos

- **App** (todo lo demás): la tanda entera.
- **BD** (2 migraciones): `provider_businesses.services text[]`;
  `provider_products.offer_defaults jsonb`. Nada del lado del código web.
