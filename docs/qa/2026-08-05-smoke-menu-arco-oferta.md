# Smoke — menú en arco del botón central al ofertar (2026-08-05)

Estado: **ejecutado parcialmente el 2026-08-06** sobre el APK 1.0.2+12 (rama temporal de device con la Fase 2). Resultados por casilla al final.

## Contexto

Rama `feat/menu-arco-oferta`. Cierra el plan
`docs/superpowers/plans/2026-08-05-menu-arco-boton-central-oferta.md` (7 tareas, TDD): el ＋
central de la barra flotante se convierte en un menú en arco ("Cargar": Cámara / Galería / Mi
tienda / Trabajos) mientras el proveedor tiene abierto el formulario de oferta en
`/provider/request/:id`; dentro de crear-solicitud sigue siendo la cámara de siempre; en
cualquier otra pantalla sigue diciendo "Crear solicitud". Se toca la barra flotante
(`floating_nav_bar.dart`, `center_action.dart`, `center_action_shell.dart`, `center_arc_menu.dart`
nuevo) y la pantalla de oferta del proveedor (`request_detail_screen.dart`,
`offer_center_menu.dart` nuevo).

La Tarea 7 (esta) corrió la suite completa (852 tests, 0 fallos) y `flutter analyze` (0 errores
nuevos) antes de escribir este guion, pero **ninguna suite prueba lo que se ve y se siente en
pantalla real**: el arco desplegándose, el frame exacto en que el centro vuelve a "Crear
solicitud" tras enviar, o si las cuatro etiquetas caben sin solaparse en el dispositivo más
estrecho disponible. **Este guion es el único gate real de la tanda.**

Conducir el device por `adb` según la nota de memoria `jayalo-conducir-device-por-adb`: factor
×1.36 entre la captura y lo que se ve en pantalla, sondeo de estabilidad por tamaño de PNG en vez
de sleeps a ojo.

---

## Casillas

- [ ] 1. Proveedor entra a una solicitud **sin ofertar** → el centro dice "Cargar", no "Crear
      solicitud".
- [ ] 2. Tocarlo → arco de cuatro con la gota; el centro es una ✕.
- [ ] 3. Cierra por ✕. Cierra por velo. Cierra por **atrás del sistema** (y no sale de la
      pantalla).
- [ ] 4. Cada satélite hace lo mismo que su botón gemelo del formulario (los cuatro).
- [ ] 5. "Mi tienda" autocompleta y lo autocompletado **queda editable**.
- [ ] 6. Con 5 fotos: Cámara, Galería y Trabajos atenuados y avisan "Ya tienes 5 fotos"; "Mi
      tienda" vivo.
- [ ] 7. **Enviar la oferta → aparece la tarjeta y el centro vuelve a "Crear solicitud".** Es la
      casilla con más probabilidad de fallar: hay un desfase de un frame entre el
      `dispose`/`release` y el rebuild del shell que `home_shell.dart` ya documenta. Si parpadea,
      el arreglo va en el guard de ruta del shell, no en la pantalla.
- [ ] 8. Volver a entrar → "Ver mi oferta" → edición en sitio → el menú vuelve.
- [ ] 9. **No regresión:** dentro de crear solicitud el ＋ sigue siendo la cámara y sigue
      añadiendo fotos.
- [ ] 10. Con "reducir animaciones" del sistema: el arco aparece sin escalonar, y el háptico
      **sigue**.
- [ ] 11. **Las cuatro etiquetas caben** en la pantalla más estrecha disponible, sin solaparse.
      Los tests no pueden firmarlo: en `flutter test` el texto mide ~2× lo real.
- [ ] 12. La gota se ve como en la referencia del PO. Si queda sosa, los tres mandos son `2.2`,
      `1.2` y `.6` en `_bridge` (`center_arc_menu.dart`) — no hay ningún test peleando contra
      ellos.

---

## Cierre

Anotar el resultado de cada casilla en este mismo fichero al correrlo. Si algo falla, arreglarlo
y volver a correr solo la casilla afectada antes de dar la tanda por cerrada.


---

## Resultado de la ejecucion (2026-08-06, device 23090RA98G, APK 1.0.2+12)

Conducido por adb desde la cuenta getto (proveedor). Solicitud usada: "Nevera de 11 pies",
sin ofertar.

- [x] **1. VERDE.** Al entrar a la solicitud, SIN desplazar, el centro ya dice "Cargar" con el
      icono de biblioteca. No hace falta llegar al formulario: basta con que este montado.
- [x] **2. FALLABA — ARREGLADO Y RE-VERIFICADO** (commit ). El arco desplegaba bien, pero **el centro se veia como un ＋**.
      Causa: el giro de 45 grados estaba pensado para un simbolo + (+ girado 45 = x) y el glifo
      TAMBIEN cambiaba a  — dos transformaciones que dicen "conviertelo en equis" se
      cancelan. Pasa a un cuarto de vuelta en los dos sitios ( y
      ); la equis es simetrica a 90 grados. **Ningun test lo veia**: los dos
      que habia afirmaban el TOKEN del icono, no el angulo. Se anadio uno que mira el giro.
- [~] **3. PARCIAL.** El **atras del sistema** cierra el arco y NO sale de la pantalla (verde).
      Falta comprobar el cierre por la propia ✕ y por el velo.
- [ ] 4. Sin ejecutar: Camara y Galeria abren selectores del sistema.
- [ ] 5. **No ejecutable hoy**: getto no tiene productos, asi que "Mi tienda" no tiene que
      autocompletar. Hace falta sembrar al menos un producto.
- [ ] 6. Sin ejecutar: exige cargar 5 fotos primero.
- [ ] 7. Sin ejecutar (**la mas probable de fallar segun el propio guion**): enviar la oferta y ver
      si el centro vuelve a "Crear solicitud" sin parpadeo.
- [ ] 8. Sin ejecutar.
- [ ] 9. Sin ejecutar (no regresion dentro de crear solicitud).
- [ ] 10. Sin ejecutar (reducir animaciones del sistema).
- [x] **11. VERDE.** Las cuatro etiquetas —Camara, Galeria, Mi tienda, Trabajos— caben sin
      solaparse en este device (1220x2712).
- [ ] 12. **Es juicio del PO**, no mio: si la gota queda sosa, los mandos son 2.2 / 1.2 / .6 en
      .
