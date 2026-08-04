# Smoke — dirección precisa y enlace al mapa

Fecha: 2026-08-04
Estado: **pendiente de ejecutar**. Este documento solo se escribe en esta tarea; no se corre.

Cierra el plan `2026-08-04-direccion-precisa-y-link-al-mapa` (12 tareas). Ningún test automatizado
cubre el camino real GPS → endpoint de la web → formulario → base de datos → chat: las suites
verifican funciones puras (`applyGeocodedPlace`, `composeAddressLine`, `mapsLinkFor`,
`splitMapLink`, `buildLocationBody`) y el cableado de la UI, pero nadie ha visto el flujo completo
correr en un teléfono. Este guion es el único gate que queda.

**Caso de aceptación de todo el plan:** el PO vive en **Parque del Este** (Santo Domingo Este) y la
app le rellenaba **Las Américas** — el geocoder nativo de Android en RD devuelve la vía grande más
cercana, no el sector real. El paso 1 de este guion reproduce exactamente ese caso.

---

## Paso 0 — El gate de despliegue (hacer esto ANTES que nada)

La app llama a `POST https://jayalo.com/api/app/reverse-geocode`. Ese endpoint lo construyó la
Tarea 2 del plan y vive en la rama web `feat/direccion-precisa`, **que todavía no está
desplegada**.

- [ ] Confirmar si `feat/direccion-precisa` ya está en producción antes de arrancar el smoke.
- [ ] Si **no** lo está: desplegarla primero, o asumir que el geocodificador va a devolver vacío en
      todos los pasos que dependen de él (1, y la mitad de 2). Si eso pasa, la app cae a su
      comportamiento de reserva — el campo de dirección queda editable a mano — **y eso NO es un
      bug**, es el resultado esperado de correr contra el endpoint apagado. No reportar "no
      autorrellena" sin haber comprobado primero si el endpoint está vivo.

⚠️ Este paso es el primero que hay que mirar si cualquier otro paso "falla" con un campo vacío.

---

## Paso 0.1 — Cuentas y datos de prueba

La base está reseteada a 0 usuarios (decisión ya tomada, 2026-08-03): construir todo de cero es lo
esperado, no una deuda.

- [ ] Registrar una cuenta **cliente** (para los pasos 1, 2 y 3).
- [ ] Registrar una cuenta **proveedor** con un negocio en `provider_businesses` (para los pasos 3
      y 5). El botón "Enviar dirección del local" solo funciona si el proveedor ya configuró la
      dirección de su negocio en su perfil.
- [ ] Abrir (o crear) una conversación de oferta entre ambas cuentas — hace falta para los pasos 3
      y 4, que verifican el enlace en el chat. Camino corto: el cliente crea una solicitud, el
      proveedor oferta, el cliente acepta.

---

## Paso 1 — Detectar ubicación en el alta (caso de aceptación del plan)

Con GPS real, en el sitio físico de Parque del Este (o simulando esa posición si el device lo
permite), completar el onboarding del cliente y pulsar **"Usar mi ubicación"**.

- [ ] El campo de dirección se autorrellena con una vía real (calle/avenida), no con "Autopista
      Las Américas" ni otra vía grande genérica.
- [ ] El campo de **sector** queda en **"Parque del Este"**.
- [ ] ⚠️ "Parque del Este" **no está** en el catálogo `LOCATIONS` (`locations.dart` /
      `locations.ts`) — el campo de sector es de **texto libre** justamente por esto. Que el
      sector aparezca escrito ahí, aunque no coincida con ninguna opción del autocompletar, **es
      el éxito**, no un fallo ni un typo.
- [ ] El campo de ciudad queda en "Santo Domingo Este".
- [ ] Si el GPS no fija (sin permiso, sin señal): sale el mensaje de error "No pudimos captar tu
      ubicación" y el formulario sigue permitiendo escribir la dirección a mano.
- [ ] Si el GPS SÍ fija pero el endpoint de geocodificación no responde (caído, timeout, sin red):
      **no sale ningún mensaje de error.** ⚠️ Corregido tras la revisión final de rama — el
      guion original prometía aquí el mismo aviso de "no pudimos captar tu ubicación", y es
      **falso**: `GeocodeClient.lookup` (`lib/core/geocode_client.dart`) está diseñado para
      **NUNCA lanzar** — rellenar la dirección es una ayuda, no un requisito. Si falla, devuelve
      un resultado vacío EN SILENCIO y los campos de dirección/ciudad/sector simplemente se
      quedan como estaban (vacíos, si es la primera vez), sin aviso, sin trabarse, sin crashear.
      **Esto es el comportamiento diseñado, no un bug** — y es justo el estado en que correrá
      este smoke si `feat/direccion-precisa` (repo web) todavía no está desplegada (ver Paso 0).

---

## Paso 1B — Detectar ubicación en el alta de PROVEEDOR

**Sección agregada tras la revisión final de rama** — faltaba por completo. Las Tareas 6 y 9 del
plan tocaron a fondo el onboarding de proveedor (`lib/features/onboarding/provider_onboarding_screen.dart`):
mismo geocodificador nuevo que el Paso 1, `LocationAccuracy.high` (antes `medium`, que en este
device declara ~100 m de precisión — suficiente para enganchar la avenida de al lado en vez de la
calle real), y se quitaron `street`/`street_number` del payload que arma la RPC de cierre.

Con una cuenta nueva (o reutilizando el registro), completar el onboarding de **proveedor** hasta
el paso "Qué vendes y dónde" y pulsar **"Usar mi ubicación"**.

- [ ] El campo de dirección se autorrellena con una vía real, mismo criterio que el Paso 1 —no un
      resultado vago tipo "Autopista Las Américas".
- [ ] Ciudad y sector detectados se agregan como chips seleccionados (no como texto en un campo
      simple — el onboarding de proveedor permite varias ciudades/sectores).
- [ ] Si el GPS no fija: mensaje "No pudimos captar tu ubicación — escribe tu ciudad y sector." y
      el formulario sigue permitiendo completar todo a mano.
- [ ] Si el GPS fija pero el endpoint de geocodificación no responde: **mismo silencio diseñado
      que en el Paso 1** — ningún aviso, los chips de ciudad/sector y el campo de dirección
      simplemente no se autorrellenan; `lat`/`lng` sí quedan guardados (se fijan ANTES de llamar
      al geocodificador).
- [ ] Terminar el alta (RPC `complete_provider_onboarding`) y confirmar en la BD
      (`provider_businesses`) que el negocio quedó con `address`/`city`/`sector`/`lat`/`lng`
      correctos.
- [ ] ⚠️ **Confirmar que la RPC NO recibió `street`/`street_number` y no falló por eso** —
      `provider_businesses` no tiene esas columnas; el payload de cierre las omite a propósito
      (comentario en el código: "la RPC `complete_provider_onboarding` no lee esas claves"). Si
      algún día se agrega esa lógica de vuelta sin agregar las columnas, la RPC fallaría o las
      ignoraría en silencio — vigilar que no se reintroduzca sin la migración correspondiente.

---

## Paso 2 — Corregir la dirección desde `/settings/address`

Entrar como el cliente del paso 1. Ajustes → **"Mi dirección"** (`/settings/address`).

- [ ] La pantalla carga con los datos guardados en el alta (dirección, ciudad, sector,
      referencia).
- [ ] Cambiar manualmente el campo **Referencia** (ej. "casa azul al lado del colmado") sin tocar
      "Detectar mi ubicación", y pulsar **Guardar**. Salir de la pantalla y volver a entrar: la
      referencia editada persiste.
- [ ] La **Referencia** nunca se toca al detectar ubicación, ni con un geocode completo ni con uno
      parcial — es una nota humana que ningún geocodificador reproduce.
- [ ] Guardar tras detectar ubicación y volver a entrar: los cambios (dirección, ciudad, sector)
      persisten.
- [ ] Con **modo avión activado**, pulsar "Detectar mi ubicación": el resultado depende de dónde
      falle, y **no siempre hay un mensaje de error** — ⚠️ corregido tras la revisión final de
      rama, el guion original prometía aquí un mensaje garantizado, y es falso por el mismo
      motivo que en el Paso 1:
      - Si el GPS mismo no fija (sin señal, sin permiso, o el device apaga la localización junto
        con la red): sale "No pudimos captar tu ubicación..." y el formulario queda intacto.
      - Si el GPS SÍ fija (puede pasar — el GPS satelital no depende de la red) pero el endpoint
        de geocodificación no puede responder por falta de red: **no sale ningún aviso** —
        `GeocodeClient.lookup` traga el error en silencio (mismo diseño del Paso 1); `lat`/`lng`
        quedan guardados pero dirección/ciudad/sector no cambian.
      - En ningún caso debe trabarse ni crashear; siempre se puede escribir la dirección a mano y
        guardarla igual.

> **Nota, no casilla accionable** (corregido tras la revisión final de rama): el guion original
> pedía provocar aquí un geocode PARCIAL "con precisión reducida o mala señal" — no es
> reproducible a voluntad por el tester. Ese comportamiento ("un resultado parcial no borra lo
> que ya estaba bien") ya lo fija el test unitario `applyGeocodedPlace` en
> `test/address_screen_test.dart`, campo por campo. No hace falta forzarlo en el smoke.

---

## Paso 3 — Compartir "Mi ubicación" en el chat (perfil del cliente)

Con la conversación abierta del paso 0.1, como **cliente**: menú **"+"** del chat →
**"Enviar mi ubicación"**.

- [ ] El mensaje sale con la dirección guardada en el perfil (`profiles`), la línea de
      sector/ciudad y, al final, un botón **"Abrir en el mapa"** (el enlace crudo no debe verse
      como texto).
- [ ] En el device del **otro participante** (el proveedor), el mensaje llega igual, con el mismo
      botón.
- [ ] Pulsar "Abrir en el mapa": abre Google Maps (app nativa si está instalada, navegador si no)
      centrado en las coordenadas correctas — comparar contra la ubicación real del cliente.
- [ ] ⚠️ **Probarlo con el pulgar, no con la uña.** El área táctil del botón mide unos 16–18 px de
      alto, por debajo de los 44–48 dp recomendados para un objetivo táctil (hallazgo de la
      revisión de la Tarea 11). Anotar si con el dedo cuesta acertar el toque. Si falla, el
      arreglo (fuera de esta tarea) es envolver el `InkWell` en un `Padding` simétrico — pero la
      decisión de si hace falta se toma con el dedo, no leyendo el código.
- [ ] Si el perfil del cliente no tiene dirección guardada, el botón debe fallar con el aviso
      "Agrega tu dirección en tu perfil primero" en vez de mandar un mensaje vacío o crashear.

---

## Paso 4 — Compartir "Enviar dirección del local" en el chat (perfil del proveedor)

Misma conversación, ahora como **proveedor**: menú **"+"** → **"Enviar dirección del local"**.

- [ ] El mensaje sale con el **nombre del negocio arriba** (primera línea), luego la dirección,
      luego sector/ciudad, y el mismo botón **"Abrir en el mapa"** al final.
- [ ] El enlace abre el mapa en las coordenadas correctas del negocio (`provider_businesses.lat` /
      `.lng`).
- [ ] Repetir la prueba del pulgar sobre "Abrir en el mapa" (mismo hallazgo del Paso 3).
- [ ] ⚠️ **Calle y número NO aparecen en este mensaje, y eso es a propósito.** El camino de
      proveedor modela la dirección en `provider_businesses` como `address` + `city` + `sector`
      únicamente; no hay columnas de calle/número en esa tabla. Que no salgan por separado no es
      un bug — la dirección completa igual va dentro del campo `address`.
- [ ] Si el proveedor no configuró la dirección de su negocio: el botón falla con "Configura la
      dirección de tu local en tu perfil de proveedor" en vez de mandar algo vacío.
- [ ] Confirmar que este camino (proveedor) y el del Paso 3 (cliente) son **caminos de datos
      distintos** — uno lee `provider_businesses`, el otro `profiles` — así que un bug en uno no
      garantiza que el otro esté sano. Los dos deben probarse, no basta con uno.

---

## Paso 5 — Un texto normal no confunde el enlace con una dirección

En la misma conversación, mandar un mensaje de texto normal que **contenga** una URL de Google
Maps pegada a mano (por ejemplo copiada de otra app).

- [ ] Ese mensaje se pinta como texto plano tal cual, **sin** el botón "Abrir en el mapa" — la
      burbuja solo separa el enlace cuando `kind == 'address'` (mensajes de texto normal no pasan
      por `splitMapLink`).

---

## Paso 6 — Frente WEB (repo `jayalo-main`, rama `feat/direccion-precisa`)

**Sección agregada tras la revisión final de rama** — faltaba por completo. Este plan fusiona
DOS repos, y la cirugía más delicada de la revisión final está en la web, no en la app: los
`Select` cerrados de `/profile` y de la sección "Zona" en `/profileprovider` pasaron a
`input + datalist`, y el chat de la web ahora tiene que pintar el enlace al mapa que manda la
app (I-3) en vez de una URL cruda. Nada de esto lo cubre ningún paso de arriba, que es 100% app.
Probar en el preview de la rama (o `jayalo.com` si ya está desplegada) con las mismas dos cuentas
del Paso 0.1.

### Selects → input + datalist

- [ ] `/profile` (cliente) — campos Ciudad/Sector: escribir una ciudad que NO esté en el catálogo
      `LOCATIONS` (ej. "Boca Chica Village", inventada). El datalist no debe ofrecer nada raro y
      el valor escrito debe conservarse al perder el foco.
- [ ] `/profileprovider`, sección "Zona" — mismo patrón pero con el centinela `__all__` de por
      medio: elegir "Todas las ciudades" / "Todos los sectores" y confirmar que el Input muestra
      la etiqueta legible ("Todas las ciudades"), nunca el valor interno `__all__`. Cambiar a una
      ciudad específica y confirmar que el sector se resetea.

### I-1 — Sector ya no se bloquea con una ciudad fuera de catálogo (`/profile`)

- [ ] Escribir a mano una ciudad que no exista en `LOCATIONS`. El campo **Sector** debe quedar
      HABILITADO (antes se deshabilitaba y vaciaba — justo el caso para el que existe el campo de
      texto libre) y debe permitir escribir un sector a mano.
- [ ] Cargar un perfil con sector ya guardado y editar la ciudad letra por letra: el sector NO
      debe borrarse en cada tecla — solo al salir del campo (blur), y solo si la ciudad cambió de
      verdad Y el sector viejo ya no es válido para la nueva.
- [ ] El toast de "Detectar" ("No identificamos el sector, puedes escribirlo") debe corresponder
      con la realidad: en ese estado el campo debe estar escribible, no deshabilitado.

### I-2 — La dirección escrita a mano en la app sobrevive a un guardado en la web

- [ ] Con la cuenta cliente del Paso 0.1: en la **APP**, ir a "Mi dirección"
      (`/settings/address`) y escribir una dirección a mano (texto libre) **sin** usar "Detectar
      mi ubicación". Guardar.
- [ ] Entrar a `/profile` en la **WEB** con esa misma cuenta. **Sin tocar** los campos
      Calle/Número, cambiar cualquier otra cosa (ej. el switch de notificaciones por correo) y
      pulsar "Guardar cambios".
- [ ] Volver a la app → "Mi dirección": el texto escrito a mano debe seguir **intacto** — no debe
      haberse recompuesto a partir de calle/sector/ciudad/país (antes SIEMPRE se recomponía, y
      volvía vaga la dirección que el usuario había corregido a mano).
- [ ] Repetir, pero esta vez sí tocando Calle o Número en la web antes de guardar: ahora **sí**
      debe recomponerse `address` desde las partes — comportamiento esperado, no un bug.

### I-3 — El chat de la web pinta el enlace al mapa como botón, no como URL cruda

- [ ] Con la conversación del Paso 0.1: desde la app, enviar "Mi ubicación" o "Dirección del
      local" (Pasos 3/4 de arriba).
- [ ] Abrir esa misma conversación en `/messages` en la **web**: el mensaje debe mostrar el texto
      de la dirección arriba y un enlace real **"Abrir en el mapa"** abajo — no la URL cruda de
      ~60 caracteres. El texto del enlace debe decir exactamente "Abrir en el mapa" (mismo copy
      que la app). Clic → abre Google Maps en pestaña nueva.
- [ ] Mandar, desde la web, un mensaje de texto normal que contenga una URL de Google Maps pegada
      a mano: debe verse como texto plano, **sin** convertirse en botón — el helper
      (`src/lib/addressMessage.ts`) solo actúa sobre `kind === 'address'`.

### Registro de cliente (paridad — confirmar que no se rompió)

- [ ] `/auth/signup/consumer` (o el flujo equivalente de la web): completar un registro nuevo y
      confirmar que no hay errores de consola ni de guardado. Este flujo no lo tocó este plan,
      pero comparte `src/mocks/locations.ts` con los campos de ciudad/sector que sí se tocaron.

---

## Lo que NO se puede probar hoy

- **Un cliente registrado por la web** compartiendo su dirección en la app. El camino de registro
  `signup.consumer.tsx` de la web nunca persiste `address`/`lat`/`lng`, así que no hay ningún
  usuario de origen web con datos que llevar al chat — ver la sección de deuda abajo.
- **El geocodificador (Nominatim) caído de verdad.** Es gratuito y sin SLA; no se puede forzar su
  caída para el smoke. El código no distingue "endpoint apagado" de "Nominatim caído": en ambos
  casos el resultado es el mismo camino de reserva (dirección vacía, escribir a mano), así que
  probar el Paso 0 con el endpoint vivo ya cubre el comportamiento observable.
- **Notación científica en coordenadas cercanas a 0,0** en `mapsLinkFor`. Irrelevante en la
  práctica: todas las coordenadas reales de RD rondan lat≈18, lng≈−69, lejos de ese caso límite.

## Deuda a vigilar durante el smoke

- **El catálogo de sectores está duplicado** en `src/mocks/locations.ts` (web) y
  `app/lib/domain/locations.dart` (app). Van a divergir con el tiempo porque la app no puede
  importar TypeScript. Si durante el smoke se nota que un sector aparece en una plataforma y no en
  la otra, no es una regresión de esta tanda — es el riesgo ya aceptado. El siguiente paso, si
  molesta, es servir el catálogo desde `app_settings` y cachearlo.
- **La dirección de los usuarios que ya existían antes de este plan no se arregla sola.** Se
  quedan con el texto vago hasta que entren a `/settings/address` y la corrijan a mano. No hay
  migración de datos: muchos perfiles viejos no tienen `lat`/`lng` guardados, así que no hay forma
  fiable de re-geocodificarlos.
- **`splitMapLink` usa `lastIndexWhere`** sobre la última línea del cuerpo del mensaje. Si algún
  día el campo de referencia (única línea, ver `address_screen.dart`) dejara de estar limitado a
  una línea, un usuario podría escribir algo que empiece con `https://www.google.com/maps/` en su
  referencia y colarse como enlace falso. Hoy el campo está restringido a una sola línea
  justamente para evitar esto (comentario en `address_screen.dart`, revisión de la Tarea 8).

## Fuera de este plan — hallazgo de producto pendiente (Task 3, preexistente)

El camino de registro `signup.consumer.tsx` de la web manda `address`/`lat`/`lng` en la metadata
de `auth.signUp`, pero el trigger `handle_new_user` (migración `20260801160000`, líneas 89-99) no
los inserta: solo copia `user_id`, `email`, `first_name`, `last_name`, `phone`, `account_type`,
`business_name`. Un cliente que se registre por la web se queda **sin dirección y sin
coordenadas**, y por tanto **sin enlace al mapa** cuando comparta su ubicación en el chat de la
app.

No es una regresión de este plan — es preexistente y ninguna de las 12 tareas lo toca. Necesita su
propia migración (agregar `address`/`lat`/`lng` al `INSERT` del trigger, o un paso posterior que
los copie desde la metadata de auth). Queda como pendiente a decidir con el PO, no como parte de
este smoke.
