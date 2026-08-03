# Smoke — capacidades del proveedor y aviso de cotejo (2026-08-02)

Un APK de debug **no se instala encima de un release**: desinstalar primero.

Nada de esto está cubierto por tests. `request_detail_screen.dart` no tiene costura, así que el
cableado entero —premarcado, interruptores, aviso y guardado— solo se verifica aquí.

## 1. Lo que más puede romperse: "mejorar oferta"

Se comprueba PRIMERO porque es lo que se rompería si los dos campos nuevos se colaran en el payload
compartido, y el fallo no se ve por ningún otro lado.

- [ ] Enviar una oferta cualquiera desde la app.
- [ ] Entrar a esa oferta y editarla: cambiar el precio y guardar.
- [ ] **Tiene que guardar sin error.** Si aparece un error de permisos, parar: los campos se
      colaron en el payload de edición.

## 2. Premarcado desde el negocio

- [ ] En la web, en el negocio de la cuenta de proveedor de prueba, marcar "emite comprobante
      fiscal" y dejar sin marcar "suplidor del Estado".
- [ ] En la app, abrir una solicitud y mirar el formulario de oferta: "Emito comprobante fiscal"
      aparece encendido y "Soy suplidor del Estado" apagado.
- [ ] Desmarcar el primero y comprobar que se deja desmarcar: es premarcado, no imposición.

## 3. El aviso

- [ ] Crear una solicitud (con la cuenta de cliente) marcando "requiere comprobante fiscal" y
      "requiere ser suplidor del estado".
- [ ] Con la cuenta de proveedor, ofertar en ella **sin** marcar ninguna de las dos capacidades y
      pulsar enviar.
- [ ] Sale el aviso, con los dos requisitos, cada uno con su explicación, y la frase que los
      enumera ("comprobante fiscal y suplidor del Estado").
- [ ] **Editar** cierra el aviso, no envía nada y deja ver los interruptores.
- [ ] Marcar las dos capacidades y enviar: **no sale ningún aviso** y la oferta se envía.

## 4. La evaluación no dispara el aviso

- [ ] Una solicitud de producto que pida SOLO "requiere evaluación". Ofertar sin marcar evaluación.
- [ ] **No debe salir ningún aviso.** Que el proveedor no la marque significa que da precio en
      firme sin visita, y eso favorece al cliente.

## 5. Servicios

- [ ] Una solicitud de SERVICIO que pida comprobante fiscal. Ofertar en ella.
- [ ] Los dos interruptores están presentes (son transversales; envío e instalación no aparecen en
      servicios, y eso es correcto).
- [ ] Sin marcar comprobante fiscal, al enviar sale el aviso mencionando solo ese requisito.

## 6. Modo edición

- [ ] Entrar a "mejorar oferta" de una oferta ya enviada.
- [ ] Los dos interruptores se ven, **apagados y no tocables**, con la nota "Quedó fijado al enviar
      tu oferta", y muestran lo que se declaró al enviarla.
- [ ] Al guardar cambios **no sale el aviso de cotejo**.

## 7. Fallo de red al abrir

- [ ] Poner el teléfono en modo avión justo antes de abrir el detalle de una solicitud, y volver a
      conectarlo.
- [ ] Los interruptores quedan apagados, no encendidos. Falla del lado seguro: se avisa de más,
      nunca se afirma algo que el proveedor no declaró.

## 8. Modo oscuro

- [ ] Los dos interruptores y el diálogo del aviso, en oscuro.
