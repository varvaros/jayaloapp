# Smoke — seis correcciones de UI (2026-08-04)

Estado: **pendiente de ejecutar**. Este documento solo se escribe en esta tarea; no se corre.

Cierra el plan `2026-08-04-correcciones-ui-seis-puntos` (17 tareas: los seis puntos pedidos por
el PO más la Tarea 17, añadida a mitad de camino). **Nada automático cubre lo que esta tanda
realmente cambia**: cómo se ve en pantalla y el cableado entre pantallas. Las suites prueban
lógica pura (`conditionFromOfferMessage`, `offerFormDirty`) y widgets aislados montados por su
cuenta (`WholesaleCard`, `LocationCoveragePicker`, `OfferRequirementCoverage`); ninguna monta
`request_detail_screen.dart` (1856 líneas) ni `RequestRespondSection.tsx`, que son las pantallas
reales donde vive el cableado. El punto 4 además depende de `PopScope` y del predictive back de
Android 13+, que ya se comprobó una vez que no se deduce leyendo el código.

**Este guion es el único gate real de la tanda.** Tres de sus casillas reproducen bugs que la
revisión de código encontró y arregló ANTES de llegar aquí — con las 16 tareas de código en verde
todo el tiempo:

1. Tocar una provincia o un sector **concreto** (no el atajo "Todos los sectores") lanzaba una
   excepción de Flutter (`DropdownButtonFormField`) — 8 tests no lo cazaron porque ninguno elegía
   un ítem puntual.
2. Abrir la edición de una oferta con la lectura de red fallida dejaba el formulario **editable**
   sin registrar el aviso de "cambios sin guardar" — se podía escribir y perder el trabajo en
   silencio al salir.
3. En la web, el aviso de salida podía dispararse **después** de un envío exitoso (carrera entre
   la animación de "enviado" y la navegación).

Los tres ya están arreglados en el código de esta rama; las casillas 1.b/1.c/1.e, 4.f y el bloque
de la web punto 4 son las que lo confirman en el dispositivo real, no en el simulador de tests.

Usar la receta de la nota de memoria `jayalo-conducir-device-por-adb` para conducir el teléfono
por `adb` sin que el PO lo toque: factor ×1.36 entre la captura y lo que se ve en pantalla,
sondeo de estabilidad por tamaño de PNG en vez de sleeps a ojo, cómo instalar sin perder sesión,
y el gate de Producto/Servicio de `create_request_screen.dart` que hace parecer que enviar "no
hace nada". Esa nota también dice lo que NO se puede hacer sin una persona delante: registrar
cuentas nuevas y teclear el OTP. Este smoke necesita **dos** cuentas (cliente y proveedor) más
altas nuevas de proveedor para el punto 1 — repartir el trabajo con el PO en consecuencia.

---

## Paso 0 — Cuentas y datos de prueba

- [ ] Cuenta **cliente** ya existente o nueva (para crear solicitudes y ver el cotejo).
- [ ] Cuenta **proveedor** con un negocio ya configurado en `provider_businesses` (sin negocio,
      `request_detail_screen.dart` no pinta el formulario de oferta en absoluto — no confundir
      eso con un fallo de esta tanda).
- [ ] En el negocio del proveedor de prueba, agregar **al menos un producto** a "Mi tienda
      virtual" (`provider_products`). Hace falta para el Paso Web-5 (ofertar desde el catálogo).
- [ ] Con el cliente, crear:
  - **Una solicitud de producto** (para los pasos App-2, App-4, App-5, Web-2, Web-4, Web-5).
  - **Una solicitud de servicio** (para los pasos App-3 y Web-3).
  - **Una solicitud de mayoreo con todos los datos** — elegir "Al por mayor", dar cantidad,
    división, empaque y una nota de detalle, y dejar que la conversación con la mascota deje
    además algún bullet y un presupuesto. Sirve para ver la tarjeta llena (App-6a, Web-6a).
  - **Una solicitud de mayoreo SIN bullets y SIN presupuesto** — elegir "Al por mayor" y, en la
    conversación, dar solo lo mínimo de mayoreo (cantidad/división/empaque) evitando que la IA
    extraiga viñetas o un presupuesto. Si la conversación igual termina generando un bullet o un
    rango de presupuesto (la IA decide sola qué extraer, no es 100% controlable a mano), corregir
    esa única fila de prueba por SQL: `UPDATE customer_requests SET bullets = '{}',
    budget_min = NULL, budget_max = NULL WHERE id = '<id de esta solicitud>';` — es dato de QA,
    no hace falta revertirlo. Esta es la solicitud que reproduce el bug de "INFORMACIÓN" flotando
    (App-6b).
- [ ] Para el cotejo (Paso App-7): una solicitud (puede ser cualquiera de las de arriba, o una
      nueva) marcando al menos un requisito (p. ej. "requiere comprobante fiscal") y **dos**
      ofertas sobre ella: una que lo declare y otra que no. El recetario completo de este
      escenario está en `docs/qa/2026-08-03-smoke-cotejo-visible-cliente.md`, sección 0 — no
      repetirlo aquí, solo hace falta una oferta en cada estado para ver los dos colores.

---

# APP

## 1. Alta de proveedor — cascada país → provincia → sector

**Sesión: registro nuevo** (no hace falta cuenta previa; este paso ES el registro). Ir hasta el
paso "Dónde trabajas" del alta de proveedor.

- [ ] El desplegable **"País"** se ve encima, con el país elegido como chip removible-o-no debajo
      (ver la nota siguiente).
- [ ] ⚠️ **Pregunta para el PO, no una casilla de pasa/no pasa**: hoy el catálogo tiene un solo
      país. Tras elegirlo, el desplegable "País" se queda **deshabilitado** (no le queda ninguna
      opción que ofrecer una vez descontado el ya elegido) — el país sigue visible en su chip
      debajo, y el control se reactivará solo cuando el catálogo tenga un segundo país. Es el
      comportamiento diseñado (verificado en la revisión de código), pero nunca se ha visto en un
      dispositivo real. **Mostrárselo al PO y anotar aquí su veredicto**: ¿aceptable tal cual, o
      hay que ocultar/reemplazar el desplegable cuando solo hay una opción?
      → Veredicto del PO: ______________________________________________
- [ ] Tocar el desplegable **"Provincia"** y elegir **una provincia concreta por su nombre** (no
      "Todos los sectores" — ese atajo es del selector de sector, no de este). **Esto es el caso
      que antes lanzaba una excepción de Flutter y tumbaba la pantalla.** Confirmar que NO
      crashea y que la provincia aparece como chip removible debajo.
- [ ] Elegir una **segunda provincia concreta**, distinta de la primera, del mismo desplegable
      (que ahora ya no ofrece la primera, porque está elegida). Confirmar que tampoco crashea —
      es la prueba de que el fallo no reaparece al repetir la interacción.
- [ ] Abrir el desplegable **"Sector"**: la primera opción es **"🗺️ Todos los sectores"**, seguida
      de la lista. Confirmar que esa lista es exactamente la **unión** de los sectores de las dos
      provincias elegidas, sin repetidos.
- [ ] Elegir **un sector concreto por su nombre** de esa lista (no el atajo). Confirmar que NO
      crashea y que aparece como chip removible.
- [ ] Quitar ese sector (botón de borrar del chip) y esta vez elegir **"🗺️ Todos los sectores"**.
      Confirmar que **no** aparece un chip por cada sector: sale un **único** chip resumen
      "🗺️ Todos los sectores".
- [ ] Quitar una de las dos provincias (botón de borrar del chip). Confirmar que los sectores que
      SOLO pertenecían a esa provincia desaparecen de la selección, y los que también pertenecen
      a la provincia que queda se mantienen.
- [ ] Cambiar el país (si el catálogo llegara a tener más de uno; si hoy solo hay uno, dejar esta
      fila marcada como "N/A — un solo país" y no como fallo). Confirmar que provincias y
      sectores elegidos se vacían por completo.
- [ ] Con el GPS del dispositivo (real, o en el sitio físico si es posible — mismo criterio que
      `docs/qa/2026-08-04-smoke-direccion-y-mapa.md`), pulsar **"Usar mi ubicación"** en un punto
      cuyo sector detectado NO esté en `locations.dart` (el caso conocido es "Parque del Este",
      Santo Domingo Este). Confirmar que ese sector aparece como chip seleccionado **aunque no
      esté en el catálogo** y no desaparece al tocar otra cosa en el picker. Si el GPS no fija o
      el geocodificador no responde, ver el Paso 0/1 de `2026-08-04-smoke-direccion-y-mapa.md`
      antes de reportar esto como fallo — puede ser el mismo comportamiento de reserva ya
      documentado allí, no una regresión de esta tanda.

## 2. Oferta de producto — marco violeta + Nuevo/Usado y Garantía obligatorios

**Sesión: proveedor.** Abrir la solicitud de producto del Paso 0 y entrar al formulario de
oferta.

- [ ] Todo el bloque de precio — el selector "Precio fijo / Rango" **y** los campos de importe —
      queda dentro de un marco con borde violeta visible. El marco no se corta ni se ve raro en
      modo oscuro (cambiar el tema del sistema o de la app y volver a mirar).
- [ ] Rellenar precio y demás campos **sin** elegir "Estado" (Nuevo/Usado) y pulsar enviar.
      Sale el aviso **"Elige si el producto es nuevo o usado."** y la oferta NO se envía.
- [ ] Elegir "Nuevo" o "Usado", dejar "Garantía" vacía y pulsar enviar. Sale el aviso
      **"Elige la garantía."** y la oferta NO se envía.
- [ ] Marcar el preset **"Sin garantía"** (uno de los chips de garantía) y enviar: esta vez SÍ
      envía — exigir el campo no exige prometer una garantía, solo declararla.

## 3. Oferta de servicio — marco violeta, SIN Estado ni Garantía

**Sesión: proveedor.** Abrir la solicitud de servicio del Paso 0.

- [ ] Probar los **cuatro modos** de precio de servicio (Fijo, Rango, Por hora, A evaluar): en
      cada uno, el bloque completo (selector de modo + campos de ese modo) queda dentro del mismo
      marco violeta que en producto.
- [ ] ⚠️ **Regresión específica a comprobar**: en NINGUNO de los cuatro modos aparecen los campos
      "Estado" ni "Garantía". Rellenar el resto del formulario y enviar sin que aparezcan esos dos
      campos: la oferta se envía sin pedir nada de eso. Si en algún modo aparecen o el envío los
      exige, la validación de la Tarea 2 se coló fuera del `if (!isService)` — es un fallo real,
      no un detalle cosmético.

## 4. Salir con cambios sin guardar

**Sesión: proveedor.** Usar la solicitud de producto del Paso 0.

- [ ] Entrar a crear una oferta nueva, escribir algo en el campo de precio, y pulsar la **flecha
      flotante** de volver. Sale el diálogo **"¿Salir y descartar los cambios?"** con los botones
      **"Seguir editando"** y **"Salir y descartar"**.
- [ ] Pulsar **"Seguir editando"**: el diálogo se cierra y el formulario sigue ahí, con lo escrito
      intacto.
- [ ] Repetir (escribir precio) y esta vez usar el **botón atrás del sistema** (o el gesto
      predictive back de Android 13+ si el device lo soporta). Sale el mismo diálogo.
- [ ] Pulsar **"Salir y descartar"**: sale de la pantalla sin guardar nada.
- [ ] Entrar de nuevo a crear una oferta y, **sin tocar ningún campo**, pulsar la flecha flotante
      y luego (en otro intento) el atrás del sistema. **Ninguna de las dos** debe mostrar el
      diálogo — el formulario limpio no cuenta como "cambios sin guardar".
- [ ] Rellenar el formulario completo y **enviar la oferta con éxito**. Inmediatamente después de
      que se confirme el envío, navegar hacia atrás (flecha o botón del sistema). **No debe
      aparecer el diálogo** — lo que hay en el formulario ya está guardado. Repetir esta prueba
      dos o tres veces (fue justo aquí donde la versión web tuvo una carrera por una animación de
      "enviado" que corría después de limpiar el aviso; en la app el mecanismo es distinto pero
      vale la pena confirmarlo más de una vez).
- [ ] ⚠️ **Trampa específica — edición con la carga de red fallida**: activar **modo avión**,
      entrar a "Mis ofertas" (dashboard del proveedor) y pulsar **editar** sobre una oferta ya
      enviada. Como la lectura de la oferta (`offerForEdit`) va a fallar por falta de red, el
      formulario de todos modos se pinta **editable** (no una pantalla de error bloqueante).
      Escribir algo en cualquier campo y pulsar atrás: **debe** salir el mismo diálogo de
      descarte. Antes de la corrección de esta tanda, ese registro no se activaba en este camino
      y el trabajo se podía perder en silencio — esta es la casilla que lo confirma arreglado.
      Desactivar el modo avión al terminar.

## 5. Editar una oferta enviada — recuperar Nuevo/Usado

**Sesión: proveedor.** Sobre la oferta de producto ya enviada en el paso anterior (o cualquier
otra oferta de producto ya enviada): "Mis ofertas" → editar.

- [ ] El chip de **"Estado"** (Nuevo/Usado) aparece **ya marcado**, con el mismo valor que se
      declaró al enviar la oferta — se recupera del mensaje guardado, no queda vacío pidiendo que
      se vuelva a elegir.
- [ ] Entrar a editar y **salir sin tocar nada** (flecha o atrás del sistema): **no** debe
      aparecer el diálogo de descarte — el prellenado no debe leerse como "cambios sin guardar".

## 6. Solicitud de mayoreo — tarjeta y el hueco vacío

**Sesión: proveedor.** Abrir el detalle de las dos solicitudes de mayoreo del Paso 0.

- [ ] **6a — la solicitud con todos los datos**: la tarjeta "Al por mayor" sale con el rótulo
      grande **como encabezado** de la tarjeta (no un chip pequeño aparte) y, dentro de la misma
      tarjeta, cantidad, división, empaque y el detalle de texto libre. Ya no hay cuatro líneas
      sueltas de texto plano en ningún otro sitio de la pantalla.
- [ ] **6b — la solicitud sin bullets y sin presupuesto** (la corregida en el Paso 0): la tarjeta
      "Al por mayor" sigue mostrando su rótulo (es la identidad de la solicitud, se pinta aunque
      no haya datos). ⚠️ **Esto es el bug real que se cazó en device**: el encabezado
      **"INFORMACIÓN"** (la sección que antes mostraba viñetas y presupuesto) **NO debe
      aparecer** flotando vacío sobre un divisor. Si aparece un "INFORMACIÓN" sin nada debajo, es
      una regresión de `_hasInfo` en `request_detail_screen.dart`.

## 7. Tarjeta de oferta del cliente — verde y gris

**Sesión: cliente.** Abrir la solicitud del Paso 0 que tiene una oferta que declara el requisito
y otra que no.

- [ ] En la oferta que SÍ declara el requisito, esa fila del bloque "Tus condiciones" se ve en
      **verde** con el ícono de check relleno.
- [ ] En la oferta que NO lo declara, esa fila se ve en **gris** (el mismo tono neutro de antes),
      con el ícono de "remove" — nunca ámbar ni un ícono de alarma.
- [ ] Repetir la misma comparación con el **tema oscuro** activado: el verde debe ser el verde de
      paleta oscura (no el mismo verde claro sobre fondo oscuro, que se vería mal).

---

# WEB

Repetir aquí los puntos 2, 3, 4 y 6, más la Tarea 17 (recién añadida) que solo existe en la web.
El punto 5 web equivale a "mejorar oferta" vía `ImproveOfferDialog`. El punto 7 (cotejo) **no
se repite aquí**: el componente que lo pinta solo existe en la rama `feat/cotejo-visible-cliente`
del repo web, que todavía no está integrada — esa rama sigue debiendo su propio smoke completo
(deuda de la tanda del 2026-08-03, no de esta). Cuando se integre, repetir el Paso App-7 en la
web contra ese componente.

Todo lo de abajo se prueba en `/provider` (o `/provider/requests/:requestId`, que redirige ahí),
con la cuenta de proveedor del Paso 0, sobre las mismas solicitudes usadas en la app.

## Web-2. Oferta de producto

**Sesión: proveedor.**

- [ ] El bloque "Precio (RD$)" tiene un borde violeta grueso visible (`border-primary/60`), no el
      borde gris tenue de antes.
- [ ] Los campos **"Estado"** y **"Garantía"** aparecen siempre visibles en una oferta de
      producto (ya no dependen de activarlos con un interruptor opt-in), cada uno con un
      asterisco rojo junto al rótulo.
- [ ] Enviar sin elegir Estado: error **"Elige si el producto es nuevo o usado."** — mismo texto,
      palabra por palabra, que en la app.
- [ ] Elegir Estado, dejar Garantía vacía, enviar: error **"Elige la garantía."**
- [ ] Escribir "Sin garantía" (o el preset equivalente si hay chips) y enviar: esta vez pasa.

## Web-3. Oferta de servicio

**Sesión: proveedor.**

- [ ] El contenedor "Modalidad de precio" (que envuelve los campos de fijo/rango/por hora) tiene
      el mismo borde violeta grueso, en los tres sub-modos.
- [ ] Los campos "Estado" y "Garantía" **no aparecen** en absoluto para una oferta de servicio.
      Enviar una oferta de servicio completa sin que se pidan.

## Web-4. Salir con cambios sin guardar

**Sesión: proveedor.**

- [ ] Con el formulario de oferta vacío, navegar a otra página del sitio (un enlace del menú, por
      ejemplo). **No** debe aparecer ningún aviso.
- [ ] Escribir un precio (o cualquier campo del formulario) y navegar internamente a otra página
      (clic en un enlace/ruta de la app, no cerrar la pestaña). Debe aparecer el mismo diálogo que
      en la app: título **"¿Salir y descartar los cambios?"**, botones **"Seguir editando"** y
      **"Salir y descartar"**. Confirmar los dos caminos (seguir editando se queda; salir y
      descartar navega).
- [ ] Con el formulario sucio, intentar **cerrar la pestaña** (o recargar): el navegador debe
      mostrar su propio aviso nativo de "¿Salir de este sitio?" / "Cambios no guardados" (no hay
      forma de personalizar ese texto, es del navegador — solo confirmar que aparece).
- [ ] Enviar la oferta con éxito y, justo después, navegar a otra página. **No** debe aparecer el
      diálogo. ⚠️ Esta es la casilla que confirma el arreglo de la carrera encontrada en la
      revisión: el aviso podía dispararse justo después de un envío exitoso porque la animación
      de "enviado" apagaba la bandera de "ya se envió" antes de navegar. Repetir el envío 2-3
      veces para tener más chance de pillar la carrera si hubiera vuelto.

## Web-5 / Tarea 17. Mejorar oferta — sin caja de texto libre

**Sesión: proveedor.** Requiere una oferta enviada usando el producto del catálogo (Paso 0).

- [ ] Crear una oferta nueva sobre la solicitud de producto usando el botón **"Cargar desde mi
      tienda virtual"** para traer el producto del Paso 0. Confirmar que el nombre y la
      descripción del producto llenan el mensaje/comentario de la oferta, y enviarla.
- [ ] Abrir esa misma oferta con **"Mejorar oferta"**. El texto del producto se ve **en solo
      lectura** dentro del diálogo (no dentro de un `<textarea>` editable) — no debe haber
      ningún campo en el que se pueda escribir texto libre en este diálogo.
- [ ] El chip de **Estado** (Nuevo/Usado) aparece ya marcado con lo declarado al enviar la
      oferta.
- [ ] Bajar el precio (el campo de precio SÍ sigue editable) y guardar. Confirmar que el mensaje
      guardado —el texto del producto— **llega intacto al cliente**, byte por byte, sin ningún
      prefijo ni duplicado añadido. Revisarlo desde la vista del cliente (chat o detalle de la
      oferta), no solo desde el propio diálogo del proveedor.
- [ ] Si la oferta no tuviera texto de producto (una oferta compuesta a mano, sin catálogo), el
      diálogo debe mostrar **"Sin mensaje adicional."** en vez de una caja vacía.

## Web-6. Solicitud de mayoreo

**Sesión: proveedor.** Mismas dos solicitudes de mayoreo del Paso 0 (la completa y la que no
tiene bullets ni presupuesto), vistas desde `/provider`.

- [ ] La tarjeta "Al por mayor" sale con el ícono y el rótulo grande como encabezado, y dentro los
      datos que tenga cada solicitud (cantidad/división/empaque/detalle) — mismo patrón visual
      que la app.
- [ ] Con la solicitud sin bullets y sin presupuesto: la tarjeta igual muestra su rótulo
      ("Al por mayor" es su identidad). La web no tiene el bug de "INFORMACIÓN" vacía de la app
      (ese encabezado no existe en este componente web), así que aquí no hay una trampa que
      buscar — solo confirmar que la tarjeta no se ve rota ni con huecos raros por falta de
      datos.

---

## Cierre

Anotar el resultado de cada casilla en este mismo fichero al correrlo. Si algo falla, arreglarlo
y volver a correr solo la casilla afectada antes de dar la tanda por cerrada — no hace falta
repetir el guion entero por un fallo puntual, salvo que el arreglo haya tocado código compartido
con otras casillas (por ejemplo, cualquier cambio en `_formSnapshot`/`offerFormDirty` obliga a
re-correr todo el bloque 4 / Web-4).

---

# Registro de ejecución — 2026-08-05

Ejecutado por adb sobre el Xiaomi `23090RA98G` (Android 16), build debug de
`feat/correcciones-ui-08-04` (`c594045`) instalado encima del debug anterior sin
perder la sesión.

## Verificado

- [x] **La rama compila e instala.** `flutter build apk --debug` en verde;
      `adb install -r` sobre el debug previo mantiene la sesión.
- [x] **Arranca sin excepciones.** Sin `E/flutter` ni excepciones en logcat tras
      relanzar; la pantalla de inicio se pinta completa.
- [x] **Crear solicitud de mayoreo funciona de punta a punta** sobre el código de
      la rama: conversación con la IA (4 preguntas), resumen correcto con el chip
      «Al por mayor» y «Cantidad: 500 unidades», rubros, requisito de comprobante
      fiscal, división «Todo junto», empaque «Caja», condición «Nuevo», y
      **«¡Tu solicitud está publicada!»**.

## BLOQUEADO — y por qué, verificado en el dispositivo

**Con una sola cuenta no se puede alcanzar la pantalla de detalle de solicitud
del proveedor**, que es donde viven los puntos 2, 3, 4 y 6.

Comprobado: tras publicar la solicitud, la bandeja del proveedor sigue diciendo
«Ahora mismo no hay solicitudes abiertas» **incluso en el filtro "Todas"**. Es el
guard `user_owns_request` (anti auto-oferta) haciendo su trabajo: el autor de una
solicitud no la ve como proveedor. Correcto por diseño, y bloqueante para el smoke.

Consecuencia por punto:

| Punto | Estado | Qué falta |
|---|---|---|
| 1 · Selector país/provincia/sector | Bloqueado | Vive en el alta de un proveedor **nuevo**; registrar cuenta pide OTP |
| 2 · Marco violeta del precio | Bloqueado | Detalle de solicitud del proveedor |
| 3 · Servicio sin Estado/Garantía | Bloqueado | Ídem |
| 4 · Aviso al salir de la oferta | Bloqueado | Ídem |
| 5 · Estado y garantía obligatorios | Bloqueado | Ídem |
| 6 · Tarjeta de mayoreo + «INFORMACIÓN» | Bloqueado | Ídem |
| 7 · Cotejo verde/gris | Bloqueado | Necesita dos ofertas de **otro** proveedor |

**Lo único que hace falta para desbloquear casi todo: una segunda cuenta.** Con
una cuenta cliente que cree las solicitudes, la cuenta proveedor actual puede
cubrir los puntos 2 a 6. El punto 1 necesita además un alta de proveedor nueva, y
el 7 una oferta desde una tercera parte (o desde la cuenta cliente sobre una
solicitud de la proveedora).

## Hallazgos incidentales (previos a esta tanda, no la bloquean)

1. **La IA extrae la cantidad al resumen pero no rellena el campo obligatorio.**
   El resumen decía «Cantidad: 500 unidades» y `Cantidad que necesitas *` seguía
   vacío; el primer «Enviar solicitud» no hacía nada aparente.
2. **El fallo de validación solo se ve como toast fugaz.** Hubo que capturar la
   pantalla a los ~600 ms del toque para leer «Indica si lo quieres nuevo o
   usado.». Conduciendo por adb con esperas normales, el envío parece
   sencillamente ignorado — el mismo síntoma que ya documenta la nota de memoria
   para el gate de Producto/Servicio.

## Estado del dispositivo al terminar

Orientación fijada temporalmente en vertical para conducir con coordenadas
fiables; **auto-rotación restaurada a 1**. Modo avión en 0. Queda instalado el
build debug de la rama y **una solicitud de mayoreo de prueba publicada** en
producción, útil como fixture para retomar.
