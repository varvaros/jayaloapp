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

## Resultado — 2026-08-03, device 23090RA98G (Android 16), build release firmado

**Pasa.** Ejecutado en device por el PO, que dio el conjunto por bueno.

La preparación costó más que el smoke, y conviene dejarlo escrito para la próxima:

- La cuenta solo tenía una oferta `accepted`, estado con el que este guion es casi entero
  inalcanzable: ese brazo de la tarjeta no lleva "Ver mi oferta". Se fabricó una `pending` ofertando
  en una solicitud abierta. **Empezar por ahí la próxima vez.**
- El device tenía un release firmado. En vez de desinstalar —que cuesta la sesión y un OTP— se
  compiló un release con la misma llave (`flutter build apk --release`, sin `--obfuscate` para no
  cegar las trazas si algo revienta) y se instaló con `adb install -r`. La sesión sobrevivió.

Confirmado directamente:

- §1: "Ver mi oferta" abre el formulario en la misma pantalla con los datos cargados; guardar
  devuelve la tarjeta sin salir de la solicitud; la foto aparece **una sola vez** al reabrir.
- §1, por captura: el espaciado quedó bien —hueco tras "Guardar cambios", "Cancelar", hueco,
  "Eliminar oferta"— y las dos capacidades salen apagadas y bloqueadas con "Quedó fijado al enviar
  tu oferta".
- §3: desde "Mis ofertas" sigue guardando y saliendo a la lista, y ahí NO aparece "Cancelar".

**No se recorrieron paso a paso §2, §4 ni §5.** El PO dio el conjunto por bueno. Si más adelante
aparece una regresión en esta pantalla, empezar por esas tres.

Falso positivo descartado por el camino: el badge "Ya ofertaste" no salía en la bandeja justo tras
ofertar, pero aparece al refrescar. No es de este cambio — el diff de `repos.dart` son solo
comentarios y no toca la bandeja ni su consulta; el badge se alimenta de una lectura cacheada.
