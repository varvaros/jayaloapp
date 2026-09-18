# Ledger — intro «Jayi te recibe» (plan 2026-09-18)

Worktree `C:/Users/ac/Downloads/jayalo-app-intro`, rama `feat/intro-jayi-te-recibe` desde `4d80960` (= `77f77c2` + docs).
Baseline: 38 tests del intro en verde. Full suite al cierre de Task 8: 2097/2097, `flutter analyze` limpio.

## Tareas 0–8

| Tarea | Rango de commits | Resultado de revisión |
|---|---|---|
| 0 | (worktree creado, sin código nuevo) | contraste OK; tabla completa; `IntroRoleStore`/`IntroSeenStore`/`introRoleRedirect`/`RoleStore` no se tocan |
| 1 | `4d80960..f13f768` | clean; Minor: `dart format` reescribió 2 líneas ajenas de `motion.dart` |
| 2 | `f13f768..bd3d7c7` | clean; Minor plan-mandated: `IntroWords` usa `style.fontSize!` — pasar siempre `fontSize` |
| 3 | `bd3d7c7..1c94243` | clean tras fix J+brillo |
| 4 | `1c94243..7c0400b` | clean tras 2 fixes: brazo de la moneda sube solo; reloj se reinicia con reduce-motion |
| 5 | `7c0400b..54e1e7b` | clean; Minor: cadena decimal tipo "5.0" da 0, sin test |
| 6 | `54e1e7b..a44c0e9` | clean tras fix: un solo RPC del bono, tests por opacidad, classic login sin `reveal`, `ExcludeSemantics` |
| 7 | `a44c0e9..d58670a` | clean |
| 8 | `d58670a..d3652f6` | clean; analyze limpio, suite 2097/2097 |

## Rulings y desviaciones del plan

1. **Task 3 fix**: el glifo de la moneda en el plan era una P, corregido a una J; posición de reposo del destello en −26 con reduce-motion.
2. **Task 4**: la bandera `saliente` sustituyó a la `entering` del brief, que no se usaba; el test de píxeles de la transición se reancló a una escena montada directamente en la pose objetivo en el mismo segundo del reloj; el brazo de la moneda sube solo; el giro en reposo se fasea desde el final de la entrada y solo para la moneda entrante; el reloj se reinicia al alternar reduce-motion.
3. **Task 6**: un solo `fetchWelcomeCredits()` por montaje vía `_creditsFuture`; el login clásico conserva `reveal: false`; `ExcludeSemantics` en los controles ocultos de la fila superior; las celdas laterales de `_topRow` a 104 dp.
4. **Task 7**: `NoSplash.splashFactory` en los arneses de test del intro y el helper `settleWithoutClock` (ahora falla de forma ruidosa); los toques de reacción a deslizar en los tests esperan `introHint + 1 ms`.
5. **Task 8**: el brief etiquetó mal dos reglas de lint; se corrigió un 4.º comentario obsoleto en `intro_role_redirect_test.dart`.

## Minors abiertos (para la revisión final)

- Task 1: `dart format` reescribió 2 líneas ajenas de `motion.dart`.
- Task 2: plan-mandated — `IntroWords` usa `style.fontSize!` — pasar siempre `fontSize`.
- Task 3: la etiqueta se despega del brazo al flotar; `saveLayer` incondicional en `_paintThumb`; shader del degradado por frame; camino animado del pintor sin test; barra de la J a ~0.1 del anillo interior.
- Task 4: dos `saveLayer` durante transiciones de la moneda; camino animado del pintor no pixel-testeado; subida de 34 px al aterrizar podría recortarse si la lámina recorta la escena; fix de la moneda saliente sin test propio.
- Task 5: cadena decimal tipo "5.0" da 0, sin test.
- Task 6: celdas laterales fijas de 104 dp y alto 48 en `_topRow` (no escalan con la fuente); `login_screen.dart` ~1200 líneas; bucle de 5 poses en `jayi_scene_test` sin `disableAnimations`; con rol guardado y sin red la pantalla espera hasta 3 s en blanco; 3 infos del analyzer pendientes: `intro_reveal.dart:103,108` e `intro_copy_test.dart:113`.
- Task 7: `settleWithoutClock` rompe en silencio a los 200 pumps; `_back()` apaga `_hintVisible` fuera de `setState`; tres tests montan la app de tres formas; no hay test de que el fantasma sea INERTE antes del segundo.

## Verificador

Informe: `.superpowers/sdd/verificador.md` (2026-09-18). Con evidencia de comandos sobre `d3652f6`:
`flutter analyze` limpio; `flutter test` **2097/2097**; sin `jayi_celebrando` en el intro; copy letra por
letra con el spec §3 (tilde incluida); `bounce` solo en los 4 sitios permitidos; `JayiScene(` montado UNA vez,
hermano del `PageView`; `JayiSceneKind` y el puente borrados. Avisos: `_accessDelay3` 170 en vez de 180 y
`Curves.linear` suelto en `IntroCounter` (los dos corregidos en la ola final).

_(pendiente — lo completa el controlador)_

## Certificador

Informe: `.superpowers/sdd/certificador.md`. Veredicto: **CERRADA CON HUECOS DECLARADOS**, con dos bloqueantes
antes del smoke que la ola final resolvió: el compás «Elegir» (spec §5) no estaba implementado (paso 2 del smoke)
y el paso 5 del smoke contradecía el re-armado de la reacción al volver (se reescribió el paso: cada entrada en
la reacción reinicia su reloj). §4, §6 y §9 trazados a tests. Huecos que quedan por naturaleza para el device:
temblor de antenas, destello, pupila, golpecitos del pulgar, entrada de la moneda, giro de reposo, nacimiento del
4.º punto y los tiempos exactos de cada retardo (cubiertos por el test de píxeles «cambiar de pose ANIMA» y por
razonamiento); `fetchWelcomeCredits` real (timeout y catch) sin test de red.

## Revisión final de rama y ola de fixes

Revisión final (`.superpowers/sdd/final-review.md`, rango `4d80960..d3652f6`): **With fixes**. Importantes:
el contador arrancaba invisible y no contaba 0→5; «Elegir» sin implementar; `IntroWords` partía el titular en
6 nodos para TalkBack; salto de flote al entrar/salir de `free`; hasta 3 s en blanco con rol guardado y sin red;
ningún test a 388 dp con fuente grande. Ola de fixes (`dd45791..d7a0e8b`, 5 commits, informe
`.superpowers/sdd/fix-final-report.md`): los 14 puntos A–N aplicados; suite **2103/2103**, analyze limpio.
Tokens nuevos: `introSkip` 900, `introPick` 220, `salida` 180, `linear`. Re-revisión: `.superpowers/sdd/final-review-2.md`.
_(pendiente — lo completa el controlador)_

Adenda tras la re-revisión (`final-review-2.md`, 14/14 ✅, 0 Critical/Important, 8 Minor): arreglados en `5439e5d` y `97d2899` el `_skip()` sin guarda `_choosing`, la doble subida de las burbujas del `open` entrante y la reserva de cifras del contador. Minors que quedan abiertos (no bloquean): test del reseteo de `_picked` con animaciones ON; el primer tercio de la cuenta cae dentro del fundido; 16/10 px del spec expresados como fracción (2:1); wordmark con `brake` y no `enter`; el test de 388 dp corre con animaciones apagadas; el smoke no avisa de los 900 ms de «Saltar».
