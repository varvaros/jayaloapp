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
- [ ] Si el GPS no fija o el endpoint no responde: cae al mensaje de "no pudimos captar tu
      ubicación" y el formulario sigue permitiendo escribir la dirección a mano (no se traba, no
      crashea).

---

## Paso 2 — Corregir la dirección desde `/settings/address`

Entrar como el cliente del paso 1. Ajustes → **"Mi dirección"** (`/settings/address`).

- [ ] La pantalla carga con los datos guardados en el alta (dirección, ciudad, sector,
      referencia).
- [ ] Cambiar manualmente el campo **Referencia** (ej. "casa azul al lado del colmado") sin tocar
      "Detectar mi ubicación", y pulsar **Guardar**. Salir de la pantalla y volver a entrar: la
      referencia editada persiste.
- [ ] Pulsar **"Detectar mi ubicación"** de nuevo, en un sitio donde el geocodificador vaya a
      devolver un resultado PARCIAL (por ejemplo, con precisión reducida o mala señal). Comprobar
      que los campos que el geocoder deja vacíos **no borran** lo que ya estaba bien — solo se
      pisan los campos donde sí llegó dato nuevo (arreglo de la Tarea 10, hallazgo del review).
- [ ] La **Referencia** nunca se toca al detectar ubicación, ni con un geocode completo ni con uno
      parcial — es una nota humana que ningún geocodificador reproduce.
- [ ] Guardar tras detectar ubicación y volver a entrar: los cambios (dirección, ciudad, sector)
      persisten.
- [ ] Con **modo avión activado**, pulsar "Detectar mi ubicación": debe fallar con el mensaje de
      error ("no pudimos captar tu ubicación...") y dejar el formulario intacto, permitiendo
      escribir la dirección a mano y guardarla igual.

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
