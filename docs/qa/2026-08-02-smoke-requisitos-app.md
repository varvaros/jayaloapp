# Smoke — requisitos de la solicitud en la app (2026-08-02)

Un APK de debug **no se instala encima de un release**: desinstalar primero, o el `install` falla
con `INSTALL_FAILED_UPDATE_INCOMPATIBLE` y se pierde media hora.

Nada de esto está cubierto por tests: el detalle del proveedor no tiene costura, y los símbolos en
device dependen de la oleada B, que en los tests siempre viene vacía.

## 1. El cliente marca y lo ve

- [ ] Crear una solicitud de PRODUCTO marcando "Requiere comprobante fiscal" y "Requiere ser
      suplidor del estado".
- [ ] En "Mis solicitudes", la tarjeta muestra dos símbolos teal junto a la hora.
- [ ] Al entrar al detalle, dos chips teal bajo el título: "Requiere comprobante fiscal" y
      "Requiere suplidor del Estado".

## 2. El proveedor se entera (el daño que esto arregla)

- [ ] Con sesión de proveedor del rubro que corresponda, esa solicitud aparece en **"Para ti"** con
      sus dos símbolos. Esta es la verificación clave: aquí los datos vienen de la oleada B, no de
      la fila, porque la RPC del inbox no trae las columnas.
- [ ] Cambiar a **"Todas"**: los símbolos siguen ahí.
- [ ] Entrar al detalle: los dos chips bajo el título, encima de la escalera de cupos.

## 3. Los cinco a la vez, evaluación incluida

- [ ] Crear una solicitud de producto marcando envío, instalación, evaluación, fiscal y Estado.
- [ ] Listado: cinco símbolos, en este orden — envío, instalación, evaluación, fiscal, Estado.
- [ ] Detalle: cinco chips, en el mismo orden. **"Requiere evaluación previa" tiene que estar**:
      es la divergencia deliberada con la web, y si falta, alguien copió la exclusión.

## 4. Sin requisitos, sin rastro

- [ ] Una solicitud sin ninguna casilla marcada: ni símbolos en la tarjeta, ni chips en el detalle,
      ni un hueco vertical de más entre el título y lo que sigue.

## 5. Solicitud ajena

- [ ] "Mis solicitudes" → "Ver solicitudes de usuarios" → tocar una con requisitos: símbolos en la
      tarjeta y chips en el detalle.

## 6. Modo oscuro

- [ ] Repasar las seis superficies en oscuro. El teal tiene que leerse sobre el fondo oscuro y no
      confundirse con el azul de "Oferta aceptada" ni con el verde de "Desbloqueado".

## 7. Escalado de texto

- [ ] Con el tamaño de fuente del sistema al máximo, abrir un detalle con varios requisitos. Los
      chips son las etiquetas más largas de la app ("Requiere suplidor del Estado", 28 caracteres),
      así que si algo se va a cortar, se corta aquí primero. `StatusChip` no está protegido ante
      escalado alto y eso afecta a toda la app, no solo a estos chips: si se ve mal, el arreglo va
      en `StatusChip`, no aquí.
