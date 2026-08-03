# Smoke — el cliente ve si la oferta cubre sus condiciones (2026-08-03)

Un APK de debug **no se instala encima de un release**: desinstalar primero.

Nada del cableado está cubierto por tests, en ninguno de los dos frentes: en la app porque
`request_status_screen` no tiene costura, en la web porque el repo no tiene tests de componente.
Todo lo que sigue solo se verifica aquí.

## 0. Los datos, primero

**Sin esto, todo lo demás sale en negativo y parecerá roto.** De las 34 ofertas que existían al
escribir esto, 33 son anteriores a que la pregunta existiera y llevan `false` en las dos columnas.

- [ ] Con la cuenta de cliente, crear una solicitud marcando **"requiere comprobante fiscal"** y
      **"requiere ser suplidor del Estado"**.
- [ ] Con una cuenta de proveedor — llamémosla **proveedor A** —, ofertar en ella **marcando
      comprobante fiscal y NO Estado**.
- [ ] Con otra cuenta de proveedor — **proveedor B** (o tras cambiar el negocio) —, ofertar **sin
      marcar ninguna** — saldrá el aviso de la tanda B; pulsar "Enviar de todos modos".

## 1. La app

- [ ] Como cliente, abrir la solicitud y ver las ofertas.
- [ ] Las ofertas salen **más nueva primero**: como proveedor A ofertó antes que proveedor B, la
      oferta de **proveedor B queda arriba** y la de **proveedor A queda abajo**. No las
      identifiques por posición, identifícalas por quién ofertó.
- [ ] La oferta de **proveedor B** (la de arriba) muestra "Tus condiciones" con las dos en
      "no lo declaró".
- [ ] La oferta de **proveedor A** (la de abajo) muestra **"Comprobante fiscal"** en positivo y
      **"Suplidor del Estado — no lo declaró"**.
- [ ] **En ninguna aparecen las palabras "no cumple" ni "no emite".**
- [ ] En la oferta de proveedor A, las filas salen en orden: comprobante fiscal antes que suplidor
      del Estado.

## 2. La app, sin condiciones

- [ ] Abrir una solicitud que **no** pidiera nada (o crear una sin marcar ninguna casilla) y ver sus
      ofertas.
- [ ] **No aparece el bloque "Tus condiciones" por ningún lado.** La tarjeta se ve como antes.

## 3. La app, solo evaluación

- [ ] Una solicitud que pida **solo** "requiere evaluación", con una oferta cualquiera.
- [ ] **Tampoco aparece el bloque.** La evaluación no es cotejable: que el proveedor no la marque
      significa precio en firme sin visita, y eso favorece al cliente.

## 4. La web, las mismas comprobaciones

- [ ] Abrir la misma solicitud del punto 0 en el detalle de la web, como cliente.
- [ ] Los textos son **exactamente los mismos** que en la app, palabra por palabra. Cualquier
      diferencia es una divergencia entre los dos módulos y hay que reportarla.
- [ ] Solicitud sin condiciones → no aparece el bloque.
- [ ] Solicitud con solo evaluación → no aparece el bloque.
- [ ] Con la cuenta de **proveedor A** (la que ofertó en la solicitud del punto 0), abrir el mismo
      detalle en la web: el bloque "Tus condiciones" **NO** debe aparecer — el posesivo apuntaría al
      lector equivocado, porque las condiciones son del cliente, no del proveedor que ve su propia
      oferta.
- [ ] Volver a abrir ese mismo detalle con la cuenta de cliente dueña de la solicitud y confirmar
      que el bloque **sí** aparece.

## 5. La web sin sesión

- [ ] Abrir el detalle de esa solicitud en una ventana privada, **sin iniciar sesión**.
- [ ] La página carga y las ofertas se ven. Si diera un error de permisos, parar: significaría que
      `anon` perdió el `SELECT` sobre las dos columnas nuevas.

## 6. Una oferta vieja

- [ ] Abrir una solicitud anterior al 1 de agosto que pidiera comprobante fiscal.
- [ ] Sus ofertas dicen "no lo declaró", **nunca** que el proveedor no lo emite. Es justo el caso por
      el que el copy está redactado así.

## 7. Modo oscuro

- [ ] El bloque en oscuro, en la app y en la web.
