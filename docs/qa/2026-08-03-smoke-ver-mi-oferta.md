# Smoke — "Ver mi oferta" (2026-08-03)

Requisitos: proveedor con sesión, una solicitud suya con oferta en `pending` y sin desbloquear.
Gotcha: un APK debug no instala encima del release; desinstala primero.

## 1. Camino principal
- [ ] Entrar a la solicitud ya ofertada.
- [ ] La tarjeta dice "Ya enviaste tu oferta" y el botón dice **"Ver mi oferta"** (singular).
- [ ] Pulsarlo: aparece el formulario EN LA MISMA PANTALLA, con los datos de la oferta cargados
      (precio, y según el tipo: envío/instalación/evaluación, marca, garantía, colores, fotos).
- [ ] No se apiló otra pantalla: no hay una segunda flecha ni un salto visual de navegación.
- [ ] Cambiar el precio y pulsar "Guardar cambios".
- [ ] Sale el toast "Oferta actualizada" y **vuelve la tarjeta, con el precio nuevo**, sin salir de
      la solicitud.
- [ ] Ver mi oferta → añadir una foto → Guardar → volver a entrar: la foto aparece UNA sola vez,
      no dos.

## 2. Cancelar
- [ ] "Ver mi oferta" → cambiar el precio y añadir una foto → "Cancelar".
- [ ] Vuelve la tarjeta con el precio ORIGINAL.
- [ ] "Ver mi oferta" otra vez: la foto añadida no está, y "Nuevo/Usado" no quedó premarcado.

## 3. Regresión: la ruta que estuvo rota
- [ ] Ir a "Mis ofertas" → tocar la misma oferta → editar el precio → "Guardar cambios".
- [ ] Guarda y **sale a la lista de ofertas**, como siempre. NO se queda en el detalle.
- [ ] En esa entrada NO aparece el botón "Cancelar".
- [ ] "Mejorar oferta" sigue guardando (la ruta de la migración `20260803120000`).
- [ ] Tras el guardado en sitio, ir a "Mis ofertas" y confirmar que el precio que se ve ahí es el
      nuevo.

## 4. Regresión: los otros estados de la tarjeta
- [ ] Oferta ACEPTADA sin desbloquear: sigue "🏆 ¡Te aceptaron!" con "Desbloquear contacto".
- [ ] Oferta DESBLOQUEADA o completada: sigue "Contacto desbloqueado" con "Ver contacto".
- [ ] Oferta RECHAZADA: sigue "El cliente eligió otra oferta", sin botón.

## 5. Eliminar
- [ ] Desde "Ver mi oferta" → "Eliminar oferta" → confirmar: va a la lista de ofertas.
- [ ] La oferta ya no está en la lista.

## Resultado
(anotar aquí lo que pasó de verdad, incluidos los fallos)
