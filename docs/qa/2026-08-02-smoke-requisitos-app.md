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

"Para ti" filtra por los rubros que el negocio del proveedor tiene declarados. Antes de crear la
solicitud de la sección 1, mira qué rubros tiene la cuenta de proveedor de prueba (o al revés:
crea primero la cuenta de proveedor y anota sus rubros) y usa uno de ellos al crear la solicitud.
Si no hay coincidencia de rubro, la solicitud simplemente no va a aparecer en "Para ti" — y eso no
es un fallo de los requisitos, es el filtro haciendo su trabajo.

- [ ] Con sesión de proveedor cuyo negocio tenga declarado el mismo rubro que la solicitud de la
      sección 1, esa solicitud aparece en **"Para ti"** con sus dos símbolos. Esta es la
      verificación clave: aquí los datos vienen de la oleada B, no de la fila, porque la RPC del
      inbox no trae las columnas. **Si no aparece, antes de reportar un bug de requisitos, descarta
      primero la falta de coincidencia de rubro** — confirma en el detalle del negocio de prueba
      que el rubro cubre el de la solicitud.
- [ ] Cambiar a **"Todas"**: los símbolos siguen ahí. Esto NO sustituye la comprobación anterior:
      en "Todas" los datos llegan por otra vía y no ejercitan la oleada B, que es todo el sentido
      de esta sección.
- [ ] Entrar al detalle: los dos chips bajo el título, encima de la escalera de cupos.
- [ ] La ruta con MENOS cobertura de toda la rama: con el proveedor de la sección anterior, oferta
      a una solicitud de OTRO rubro (una a la que ese negocio no calificaría por "Para ti" normal).
      Esa solicitud debe colarse igual en "Para ti" — no por el filtro de rubro sino porque el
      proveedor ya le ofertó (`myOfferedOpenRequests`, vía distinta a `allOpenRequests`). Confirma
      que también trae sus símbolos de requisitos. Esta fila NUNCA trae las columnas en su propia
      consulta: depende por completo de que la oleada B la alcance en el merge, y ningún test
      automatizado ejercita este camino.

**Degradación silenciosa (por qué es aceptable):** si la oleada B falla (best-effort, ver
`loadInboxData`), la tarjeta no muestra ningún símbolo — y eso es indistinguible de "esta solicitud
no exige nada". Lo que hace esto tolerable es que la tarjeta del listado solo lleva al detalle;
nunca se oferta desde ahí. Ofertar obliga a pasar por el detalle (`request_detail_screen.dart`),
que carga sus propios datos por `requestById` — ahí los requisitos SIEMPRE llegan, con oleada B o
sin ella. Es decir: en el peor caso el proveedor ve una tarjeta "limpia" de más, pero nunca oferta a
ciegas sobre un requisito que no vio.

## 3. Los cinco a la vez, evaluación incluida

- [ ] Crear una solicitud de producto marcando envío, instalación, evaluación, fiscal y Estado.
- [ ] Listado: cinco símbolos, en este orden — envío, instalación, evaluación, fiscal, Estado.
- [ ] Detalle: cinco chips, en el mismo orden. **"Requiere evaluación previa" tiene que estar**:
      es la divergencia deliberada con la web, y si falta, alguien copió la exclusión.
- [ ] **Tarjeta saturada** (sin revisar hasta ahora): en la bandeja del proveedor, esta misma
      solicitud con varias ofertas recibidas Y ofertada por ti — cinco símbolos de requisitos MÁS
      "3 ofertas" MÁS "Ya ofertaste" en la misma fila. No debería desbordar (es un `Wrap`, envuelve
      a otra línea), pero confirma que la tarjeta simplemente crece de alto y que nada se corta ni
      se superpone.

## 4. Sin requisitos, sin rastro

- [ ] Una solicitud sin ninguna casilla marcada: ni símbolos en la tarjeta, ni chips en el detalle,
      ni un hueco vertical de más entre el título y lo que sigue.

## 5. Solicitud mayorista

- [ ] Crear una solicitud AL POR MAYOR marcando al menos un requisito. En el detalle propio
      (`request_detail_sheet.dart` / `other_request_screen.dart`), confirma la posición relativa:
      el chip "Al por mayor" alineado a la DERECHA, y los chips de requisitos justo debajo,
      alineados a la IZQUIERDA. No deben superponerse ni invertir el orden.
- [ ] En "Mis solicitudes", sobre una tarjeta CON símbolos de requisitos, arrastra un
      `SwipeToActions` empezando el gesto justo ENCIMA de un símbolo (no al lado). El `Tooltip` de
      `RequestRequirementBadges` mete un reconocedor de pulsación larga donde antes no había
      ninguno: confirma que el swipe igual se reconoce y no se lo traga el tooltip (ni abre el
      tooltip en vez de arrastrar la fila).

## 6. Solicitud ajena

- [ ] "Mis solicitudes" → "Ver solicitudes de usuarios" → tocar una con requisitos: símbolos en la
      tarjeta y chips en el detalle.

## 7. Modo oscuro

- [ ] Repasar las seis superficies en oscuro. El teal tiene que leerse sobre el fondo oscuro y no
      confundirse con el azul de "Oferta aceptada" ni con el verde de "Desbloqueado".

## 8. Escalado de texto

- [ ] Con el tamaño de fuente del sistema al máximo, abrir un detalle con varios requisitos. Los
      chips son las etiquetas más largas de la app ("Requiere suplidor del Estado", 28 caracteres),
      así que si algo se va a cortar, se corta aquí primero. `StatusChip` no está protegido ante
      escalado alto y eso afecta a toda la app, no solo a estos chips: si se ve mal, el arreglo va
      en `StatusChip`, no aquí.
