# Barra flotante — iteración 2: color, muesca, avatar y Catálogo

**Fecha:** 2026-07-18 (feedback del PO tras ver la iteración 1 en el Redmi)
**Estado:** decisiones del PO capturadas; plan en `docs/superpowers/plans/2026-07-18-navbar-iteracion-2.md`
**Base:** iteración 1 completa (`ef75b52..0602252`, instalada y vista en device)

---

## 1. Qué dijo el PO al ver la v1

1. **La barra no se percibe**: su fondo (`surfaceContainerLowest`, blanco) es del mismo color
   que el fondo de la app. Debe ir **teñida de violeta claro**, con **botón, iconos y letras en
   violeta oscuro**.
2. **Falta la curvatura del centro**: en el diseño de referencia la píldora tiene una **muesca
   cóncava** que abraza al botón circular; la nuestra es una píldora recta con el círculo
   simplemente superpuesto.
3. **Reorganización de destinos** (ver §3).
4. **Catálogo**: v1 con el **flujo completo de la web** — interés + desbloqueo (decisión
   explícita del PO frente a las alternativas más chicas).

## 2. Color de la barra

Tokens de `core/brand.dart` — nada inventado:

| Elemento | Claro | Oscuro |
|---|---|---|
| Fondo de la píldora | `accent` `#F0EAFF` (violeta claro) | `dAccent` `#142C55` |
| Iconos y etiquetas (activo e inactivo se distinguen por peso/opacidad, no por otro color) | `accentFg` `#3C1590` (violeta oscuro); inactivo con opacidad reducida | `dForeground` `#F3F5F8`; inactivo `dMutedFg` |
| Botón central (círculo) | `accentFg` `#3C1590` | `dPrimary` `#3E98FF` |
| Icono dentro del círculo | `primaryFg` (blanco) | `dPrimaryFg` |

Regla: el activo se marca con el color pleno + etiqueta; el inactivo con el mismo tono
atenuado. Verificar contraste WCAG del inactivo sobre el fondo teñido.

## 3. La muesca (curvatura del centro)

La píldora deja de ser un `Container` con `borderRadius`: pasa a dibujarse con un
`CustomPainter` (o `ShapeBorder` custom) cuyo path incluye la **muesca cóncava** alrededor del
círculo central — el mismo concepto que `CircularNotchedRectangle` de Material usa en
`BottomAppBar`, pero sobre nuestra píldora con esquinas redondeadas. La sombra debe seguir el
path (no un rectángulo), y el círculo central se asienta EN la muesca, como en la referencia.

## 4. Reorganización de destinos (decisión PO 2026-07-18)

**Ajustes sale de la barra en ambos roles** → vive dentro del menú del avatar (§5).

| Rol | Izquierda | **Centro** | Derecha |
|---|---|---|---|
| **Cliente** | Mis solicitudes · **Catálogo** | **＋ Nueva solicitud** | Mensajes · **Reputación** |
| **Proveedor** | Mis ofertas · **Mi negocio** | **🔍 Ver solicitudes** | Mensajes · *(4º puesto ABIERTO — preguntar al PO)* |

- Cliente: Reputación se muda del puesto 2 al 4; Catálogo ocupa el 2.
- Proveedor: **Estadísticas y Ajustes van al menú del avatar**; "Mi negocio" entra a la barra.
  El PO enumeró Solicitudes (centro), Mis ofertas, Mensajes y Mi negocio — son 3 laterales +
  centro. **Pregunta abierta**: ¿4º lateral vacío (barra asimétrica) o qué lo llena?

## 5. Avatar de perfil en el AppBar

Un avatar circular en la esquina del AppBar, **al lado de la campana**, en las pantallas raíz.
Al tocarlo se abre un menú (bottom sheet o menú anclado):

- **Cliente:** Ajustes.
- **Proveedor:** Estadísticas · Ajustes.

Las rutas `/settings` y `/provider/stats` NO se borran — solo dejan de ser pestañas. La
pantalla de Estadísticas construida en la iteración 1 se conserva íntegra; solo cambia cómo se
llega a ella. `activeIndex` ya devuelve `-1` para rutas fuera de la barra (fix I2 de la it. 1),
así que navegar desde el menú no enciende pestañas falsas.

## 6. Mi negocio (proveedor) — pantalla nueva

Contenido **no especificado por el PO** — propuesta mínima a validar al inicio de la próxima
sesión: nombre y logo del negocio, badge de verificación, saldo de créditos con botón de
recarga (el flujo de recarga por navegador ya existe, ADR-0031), y datos de contacto. NO
edición en v1 (se administra en la web).

## 7. Catálogo de proveedores — flujo completo (cliente)

Paridad con la web (decisión PO): el cliente navega los productos/servicios publicados,
ve el detalle y marca **"Me interesa"**; el proveedor recibe el interés y **desbloquea el
contacto con créditos** (`try_unlock_product_interest`, RPC ya en producción con el costo
calculado server-side).

Fuentes de la web a leer antes de planificar en detalle (jayalo-main):
- `src/routes/products.$productId.tsx` — detalle de producto
- `src/components/marketplace/InterestConfirmDialog.tsx` — confirmación de interés
- `src/lib/product-interest.functions.ts` — cómo se registra el interés (⚠️ es una server
  function: verificar si la app puede replicarlo con RPC/insert directo bajo RLS o si hace
  falta una RPC nueva — ÚNICA excepción admitida al "cero backend", con su migración y ADR si
  se confirma)
- `src/components/provider/ProviderInterestsSection.tsx` — lado proveedor
- La pestaña Catálogo de `src/routes/requests/index.tsx` — listado y filtros

Lado proveedor en la app: `providerInbox()` hoy FILTRA `source == 'marketplace'` y descarta
los ítems de producto que `get_provider_inbox_unified` ya devuelve — hay que dejar de
filtrarlos y pintarlos con su acción de desbloqueo.

## 8. Decisiones del PO registradas (esta iteración)

1. Barra teñida de violeta claro; botón/iconos/letras violeta oscuro.
2. La píldora lleva la muesca cóncava de la referencia.
3. Catálogo v1 = flujo completo de la web (interés + desbloqueo), no vitrina.
4. Cliente: Catálogo en el puesto 2, Reputación al 4, Ajustes al avatar.
5. Proveedor: Mi negocio a la barra; Estadísticas y Ajustes al avatar.
6. Avatar de perfil en el AppBar junto a la campana, con el menú dentro.

## 9. Preguntas abiertas — CERRADAS (2026-07-18)

1. **4º lateral del proveedor** → el PO reordenó la barra entera:
   `Solicitudes · Mis ofertas | ＋ Crear solicitud | Mensajes · Mi negocio`.
   - "Solicitudes" (`/provider`) va **primera**: *"la primera ventana de interés es las
     solicitudes sin responder que tenga de su rubro"*. Coincide con el landing del proveedor.
   - El centro deja de ser 🔍 "Ver solicitudes" y pasa a **＋ "Crear solicitud"**
     (`/client/create`): *"habíamos olvidado que un proveedor también puede solicitar"*.
     Verificado que `redirectTarget` no restringe rutas por rol.
2. **"Mi negocio" v1** → *"productos, servicios y trabajos realizados (los tenemos en
   estadísticas actualmente, lo movemos aquí)"*. Es un MOVIMIENTO desde `/provider/stats`, no
   una copia. La propuesta del §6 (saldo/recarga/contacto) queda descartada para v1.
3. **Registro del interés** → verificado en el código de la web: **hace falta backend nuevo**.
   La web usa la server function `createProductInterest` con service_role (deriva
   provider/business/nombre del producto). Además se halló una **vulnerabilidad viva**: el flujo
   de paquetes de `provider/business.$id.tsx` inserta DIRECTO desde el cliente y la política de
   INSERT solo valida `customer_id`, así que se pueden forjar intereses a nombre de un proveedor
   ajeno. Plan autorizado: RPC `create_product_interest` + `REVOKE INSERT` + migrar el flujo de
   paquetes de la web. Detalle en la Task 5 del plan.
