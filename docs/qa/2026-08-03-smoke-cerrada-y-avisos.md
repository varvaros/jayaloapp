# Smoke — "Cerrada" y los avisos del servidor

Fecha: 2026-08-03
Estado: **pendiente de ejecutar**.

Es el único gate real de esta tanda: ni la parte A (que vive en SQL) ni el cableado de la parte B
los cubre ningún test de punta a punta. Las suites están verdes (app 776, web 457) pero eso no
prueba que el flujo funcione en la mano.

**Contexto:** la base de producción se reseteó el 2026-08-03 (0 usuarios). Todo hay que construirlo.

---

## Paso 0 — Recuperar el admin

Regístrate como **`varvaros.com@gmail.com`**. El trigger `handle_new_user` le devuelve el rol
`admin` automáticamente (verificado antes del reseteo). Sin esto no hay panel de administración.

---

## Parte A — los avisos del servidor

Necesitas **dos cuentas** (un cliente y un proveedor) y una conversación de oferta abierta entre
ellas. Para llegar ahí: el cliente crea una solicitud → el proveedor oferta → el cliente acepta →
el proveedor desbloquea el contacto (cuesta créditos).

### A1 · Completar un trato

El proveedor pulsa "Marcar como completado". Comprobar **en el device del cliente**:

- [ ] Llega **una** notificación titulada **"Trato marcado como completado"**. NO "Nuevo mensaje".
- [ ] **No** llega ninguna otra notificación por ese mismo hecho.
- [ ] En el chat aparece **un solo** cartel de completado, no dos.
- [ ] El icono de la notificación es un check, no la campana genérica ni un globo de chat.

Y **en el device del proveedor**: llega la misma notificación. Antes no le llegaba nada.

⚠️ **El sonido cambió.** Estos avisos viajaban disfrazados de mensaje y sonaban a chat; ahora suenan
a alerta. Es esperado — anotar si resulta molesto.

### A2 · El mensaje normal no se rompió

En una conversación abierta, mandar un texto, una foto y una dirección. Comprobar que cada uno sigue
generando su "Nuevo mensaje" con el preview correcto (`📷 Foto`, `📍 Dirección`) y que el badge de
mensajes sin leer sube. **Este es el control**: si se rompió, la guarda del trigger es demasiado
ancha.

### A3 · Mejorar oferta

El proveedor baja el precio acordado desde el chat. Comprobar:

- [ ] Al cliente le llega **"El proveedor mejoró su oferta"**, con el precio y el ahorro en el cuerpo.
- [ ] Antes de esta tanda ese aviso **no existía** — el flujo estaba mudo.
- [ ] ⚠️ **Ahora también manda correo, y sin tope diario.** Comprobar que llega y juzgar si el
      volumen es aceptable.

---

## Parte B — la fase "Cerrada"

### Cómo construir el caso (elegir uno)

**Camino rápido — "no concretado":** desde el ⋮ del chat, cualquiera de las dos partes marca la
conversación como no concretada. Deja `conversations.status = 'perdido'` y el trigger pone
`closed_at`. Etiqueta esperada: **"No concretada"**.

**Camino del cron — inactividad:** hay que esperar 72 h, o bajar temporalmente
`app_settings.conversation_autoclose_hours` y esperar a que corra `auto_close_stale_conversations`
(cada hora en punto). Etiqueta esperada: **"Cerrada por inactividad"**.
**Restaurar el valor al terminar.**

### B1 · La lista

- [ ] La solicitud sale en **gris**, con la píldora que dice el motivo correcto, y **sin** banda
      violeta.
- [ ] La miniatura sale desaturada.
- [ ] Una solicitud **completada** sigue en gris **con** su banda violeta "Completado".
- [ ] Las fases vivas (esperando / con ofertas / aceptada / en contacto) no cambiaron.
- [ ] La lista no tarda más en abrir que antes.

### B2 · El detalle

- [ ] Abrir el detalle de la "Cerrada" **no revienta** (había dos mapas leídos con `!` que
      provocaban un crash si faltaba una clave; ahora son funciones exhaustivas, pero conviene
      verlo con los ojos).
- [ ] El título y el subtítulo dicen el mismo motivo que la lista.
- [ ] No aparece el mensaje de cupos ("puedes aceptar N ofertas más").

### B3 · Los permisos

- [ ] Deslizar una "Cerrada": ofrece **Eliminar**, NO ofrece **Editar**.
- [ ] Ejecutar el borrado hasta el final: **funciona**. No sale el toast de
      "un proveedor ya pagó por contactarte". La solicitud desaparece de la lista.
- [ ] Al proveedor le llega "El cliente canceló la solicitud" (decisión del PO: se deja así).
- [ ] Deslizar una **completada**: no ofrece ninguna de las dos, y muestra la franja gris con su
      motivo.
- [ ] Deslizar una **aceptada con chat vivo**: la franja gris dice **"no puede editarse"** (no
      "no puede eliminarse" — eso fue una regresión cazada en revisión).

### B4 · La web dice lo mismo

Con la misma solicitud, abrir en la web:

- [ ] El **detalle** (`/requests/<id>`) muestra el mismo motivo que la app.
- [ ] La **lista** (`/requests?view=mine`) también. Esta es la que se había quedado fuera del
      diseño y se arregló en la revisión final — es el punto más frágil de la tanda.

---

## Lo que NO se puede probar hoy

- **El autofill del OTP.** El SMS lleva el hash de firma de RELEASE (`3LtdoLuN7tU`); este smoke corre
  sobre un build DEBUG, cuya firma da otro hash (`lErR2xpOwcD`). Android solo entrega el SMS a la app
  cuya firma coincide, así que **el código no se autollena y hay que teclearlo**. No es un fallo: se
  confirmó funcionando end-to-end el 2026-07-27 con el build de release. Verificarlo cuando se
  compile el APK para testers. NO cambiar el secreto `SMS_RETRIEVER_HASH` al hash de debug: lo
  arreglaría en un teléfono y lo rompería para todos los testers.

- **El cron de inactividad de verdad** (72 h). Se verificó en `BEGIN`/`ROLLBACK` contra producción
  durante la implementación, pero no en vivo.
- **El caso de 3 finalistas con motivos mezclados** (una conversación autocerrada y otra no
  concretada en la misma solicitud → etiqueta genérica "Cerrada"). Construirlo a mano es caro; la
  lógica está cubierta por tests unitarios en los dos repos.

## Deuda a vigilar durante el smoke

- **`Cerrada por inactividad` son 23 caracteres.** En el device del PO (388 px lógicos) entra; a
  320 px desborda 38 px. Decisión tomada: dejar que trunque. Confirmar que se lee bien.
- **El detalle puede quedar con el dato viejo** si la conversación se cierra con la pantalla
  abierta (`conversations` no está en la publicación de realtime). Se corrige al salir y volver.

---

## Extra — el arreglo de "Corregir algo" (2026-08-04, sin revisar)

- [ ] En el formulario final, pulsar **"Corregir algo"** y luego **"Volver al formulario"**: el
      formulario reaparece intacto (antes no habia forma de volver).
- [ ] **Con el modo avion puesto**, pulsar "Corregir algo", escribir algo y enviar. Debe salir el
      toast de error y **volver a verse el campo de corregir**, con el formulario intacto detras.
      ANTES de este arreglo la pantalla se quedaba vacia y habia que rehacer la solicitud entera.
- [ ] Desmarcar "Nuevo" a mano, corregir cualquier otra cosa, y comprobar que **sigue desmarcado**
      cuando vuelve el formulario.
