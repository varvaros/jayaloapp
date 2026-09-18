# Intro «Jayi te recibe» — diseño (app)

**Fecha:** 2026-09-18 · **Estado:** aprobado por el PO sobre la propuesta visual
(https://claude.ai/artifact/6TpAxDwJNTyYbGXN17nfLU) · **Alcance:** solo la app Android.

## 1. Objetivo

Sustituir el copy y la puesta en escena del carrusel de primera apertura de la app por el
guion del PO, con una coreografía de nivel premium: **Jayi es uno solo durante todo el
recorrido**, nunca se desmonta entre láminas, solo cambia lo que tiene en la mano. Dos
Jayis nuevos: **pulgar arriba** (la reacción) y **moneda dorada** (los créditos de regalo).

Lo que NO cambia: el intro sigue viviendo dentro de `/login` (sin sesión, toda otra ruta
rebota), sale **una vez por teléfono** (`IntroSeenStore`, PO 2026-08-20), la elección de
lado se guarda efímera en `IntroRoleStore` y la consume el alta, y los accesos finales son
los de siempre (Google registra; correo solo inicia sesión).

## 2. Estado medido antes de diseñar

- El carrusel existe en `app/lib/features/auth/login_screen.dart` (`_LoginScreenState`):
  `PageView.builder`, 1→3 láminas según rol, `_skipped` abre un cierre neutro de 2, PopScope
  retrocede lámina, `_markSeenIfDone` marca al llegar a los accesos.
- El copy vive en `intro_copy.dart` (`IntroSlide{headline, highlight, sub}`, `kIntroCommon`,
  `kIntroSlides`). **Ninguna lámina menciona los créditos de regalo.**
- Las escenas son `JayiScene(kind: JayiSceneKind)` en `jayi_scene.dart`: `CustomPaint` sobre
  un `Ticker`, viewBox 168×132, un Jayi canónico y accesorios por lámina. **Cada lámina
  monta SU JayiScene dentro del PageView**: Jayi se remonta en cada cambio.
- `flutter_animate ^4.5.0` está en el proyecto (6 ficheros) pero no en el intro.
  `lottie` también, con `jayi_celebrando.json`: **⛔ prohibido aquí, es la animación de
  ganar cosas dentro de la app (PO 2026-09-18).**
- Tokens: `JayaloMotion` (`fast` 150, `base` 250, `page` 300, `enter`/`exit`/`emphasized`,
  `brake` = easeOutQuint, `reduced(context)`). No hay duraciones ilustrativas de 400–800 ms.
- Bono de bienvenida: `app_settings.welcome_bonus_credits` = **5** hoy, configurable desde
  el admin. La RPC `public.bonus_config()` devuelve `(welcome_credits, referral_credits,
  referral_max, referral_needs_rnc)` y **`anon` tiene EXECUTE** (medido 2026-09-18). El
  trigger `trg_welcome_bonus` (AFTER INSERT en `provider_wallets`) paga el bono en el alta
  por web y por app.
- Tests vivos que tocan el intro: `intro_copy_test`, `login_intro_carousel_test` (13 casos),
  `login_intro_once_test` (6), `jayi_scene_test` (7 + 5 paramétricos),
  `jayi_scene_pixels_test` (2), `intro_role_store_test`, `intro_role_redirect_test`.
- Fuera del intro nadie consume `JayiSceneKind` ni los símbolos de `intro_copy.dart`
  (inventario: `grep` en `app/lib` y `app/test`, 2026-09-18). «Busco algo / Vendo algo»
  aparece además en TRES comentarios (`session_state.dart:37`, `push_permission.dart:14`,
  `push_service.dart:277`): se actualizan al copy nuevo.

## 3. Guion (copy exacto)

Marca en el titular: **«Jáyalo» con tilde** (como en el pitch). El wordmark pintado
(`_Wordmark`) no cambia.

| Paso | Lámina | Titular | Apoyo | Acción |
|---|---|---|---|---|
| `ask` | 0 (común) | En Jáyalo conectamos clientes con proveedores. | **¿Tú qué eres?** (violeta, línea propia) | Recuadros «Soy un cliente» / «Soy un proveedor» |
| `react` | 1 | grito **¡Genial!** (cliente) / **¡Bien!** (proveedor) | Aquí haces una solicitud y esperas que proveedores te hagan ofertas. / Aquí encontrarás clientes que buscan exactamente lo que vendes. | Avanza sola a los 2,6 s; «Siguiente» fantasma desde el segundo 1 |
| `consumerFree` | 2 (cliente, final) | Para ti, todas las funciones son gratis. | Navega con libertad. | Accesos |
| `providerOffers` | 2 (proveedor) | Hacer ofertas es gratis. | Responde a las solicitudes de tu zona sin gastar ni un crédito. | «Siguiente» (o accesos si no hay bono) |
| `providerCoin` | 3 (proveedor, final) | Tienes **{n}** créditos de regalo para desbloquear clientes. | — | Accesos |
| `neutralClose` | 1 (saltó sin elegir) | En Jáyalo conectamos clientes con proveedores. | Entra y elige tu lado cuando quieras. | Accesos |

Recuadros de rol: título + apoyo pequeño. «Soy un cliente» / «Busco productos o servicios»
con ícono de **lupa**; «Soy un proveedor» / «Vendo productos o servicios» con ícono de
**tiendita**. Íconos lineales **sin fondo** (PO 2026-09-18), violeta sobre la tarjeta blanca.

Apoyos que son propuesta mía, no guion del PO (se quitan sin tocar nada más): el de los
recuadros, el de `providerOffers` y el de `neutralClose`.

## 4. Flujo y estados

Secuencia de pasos, función **pura** (testeable sin widgets):

```
introSteps(role: null,     skipped: false, credits) = [ask]
introSteps(role: null,     skipped: true,  credits) = [ask, neutralClose]
introSteps(role: consumer, skipped: *,     credits) = [ask, react, consumerFree]
introSteps(role: provider, skipped: *,     credits) = [ask, react, providerOffers, providerCoin si credits > 0]
```

- La lámina de **accesos es siempre la última** cuando hay más de una. `_markSeenIfDone`
  marca al llegar a ella, por cualquier camino (igual que hoy).
- **Puntos**: `steps.length`, salvo con 1 sola lámina, donde se pintan 3 (mismo criterio de
  hoy: la lámina de elección no es un carrusel de una). Al elegir proveedor con bono, nace
  un 4.º punto **con escala desde cero**.
- **Saltar**: visible en toda lámina salvo la última; sin rol abre el cierre neutro; con
  rol salta a la última lámina del rol. En `react` NO se muestra «Saltar» (la lámina
  avanza sola y ya tiene «Siguiente»).
- **Atrás** (PopScope y el chevrón nuevo arriba a la izquierda, visible desde la lámina 1):
  retrocede una lámina. Volver a la 0 deja el rol guardado y permite reelegir; reelegir
  vuelve a llamar a `IntroRoleStore.save`. Retroceder desde `react` **cancela** su
  temporizador.
- **Reacción**: al entrar en `react` se arma `Timer(introRead = 2 600 ms)` → `goToPage(2)`
  si sigue siendo la lámina actual y la pantalla sigue montada. A `introHint = 1 000 ms`
  aparece «Siguiente» (fantasma: texto violeta sin relleno). Ambos temporizadores se
  cancelan en `onPageChanged`, en atrás y en `dispose` (si no, los tests de widgets fallan
  por temporizadores pendientes). **Con «reducir movimiento» la lámina también avanza sola
  a los 2,6 s**: es tiempo de lectura, no animación.
- **Restaurar** con rol ya guardado (`_restore`): se aterriza en la última lámina, como hoy.
  El número de páginas sale de `introSteps` con los créditos ya resueltos o, si aún no
  llegaron, se espera a `fetchWelcomeCredits` **antes** de saltar (ver §6).

## 5. Coreografía

Todo sale de `JayaloMotion`. Duraciones ilustrativas **nuevas** en `core/motion.dart`:

| Token | ms | Uso |
|---|---|---|
| `intro` | 420 | palabras del titular, recuadros, frase de la reacción, accesos, la etiqueta |
| `introGesture` | 560 | pulgar, saltito de Jayi, «¡Genial!» |
| `introLand` | 720 | Jayi aterriza; la moneda sube y aterriza |
| `introRead` | 2 600 | la reacción avanza sola |
| `introHint` | 1 000 | aparece «Siguiente» fantasma |
| `bounce` (curva) | `Cubic(.34, 1.45, .64, 1)` | **el ÚNICO rebote del sistema**: pulgar y «¡Genial!» |

Compases (en orden; los tiempos son desde el evento que los dispara):

**Lámina 0.** Wordmark 250 ms `enter`. Titular: cada palabra sube 10 px, 420 ms `brake`,
escalonadas 38 ms desde 120 ms; «¿Tú qué eres?» a 120 + 420·1,4 ms. Jayi aterriza desde
200 ms: cae 34 px, toca piso al 55 %, aplasta (1,06 × 0,93) al 68 %, rebota (0,98 × 1,03) al
84 %, 720 ms `brake`; las antenas tiemblan (−9°, +6°, −2,5°) empezando al 75 % del
aterrizaje. Las dos tarjetas flotantes suben 12 px a 0,8 y 0,9 del aterrizaje, 420 ms.
Recuadros suben 14 px a 560 y 640 ms, 420 ms `brake`. «Saltar» aparece a 900 ms.

**Elegir.** El recuadro tocado crece 4 % con anillo violeta (150 ms `enter`); el otro se
hunde 10 px y se apaga (180 ms `exit`). A 220 ms el elegido sube 16 px y se va (250 ms
`exit`). A 300 ms se pide la página 1 (`page` 300 ms `emphasized`, el deslizamiento del
PageView de siempre). Si el proveedor tiene bono, el 4.º punto nace con `bounce`.

**Reacción.** Al cambiar la pose a `thumbsUp`: el brazo rota de 78° a 0° con `bounce` en
560 ms; el cuerpo salta (aplasta 1,05 × 0,93 al 22 %, sube 10 px al 52 %, aterriza 1,03 ×
0,96 al 78 %) 560 ms `emphasized`; antenas tiemblan al 75 %; la pupila mira al pulgar
(+3, −3) en 420 ms `emphasized`. El grito entra desde 72 % con `bounce` 560 ms, anclado a la
izquierda, 110 ms después del cambio de lámina; la frase sube 10 px a 520 ms, 420 ms. Después
el pulgar da **dos golpecitos** (−6°, 0, −5°, 0) en el último tercio de un ciclo de 2,8 s.

**Cambio de lámina (1→2, 2→3).** El PageView desliza (300 ms `emphasized`). El texto de la
lámina entrante se revela 180·0,6 ms después de empezar. Jayi **cambia de mano**: el
accesorio saliente se apaga en 250 ms `exit` (el pulgar además rota de vuelta a 78°); el
entrante sube 12 px en 420 ms `brake`. Puntos: el activo se estira de 7 a 22 px en 300 ms.

**`consumerFree`.** Jayi flota más alto: 9 px y ±1,2° de balanceo, ciclo 3,4 s. Accesos:
suben 14 px escalonados 90 ms (Google, nota, correo) desde 330 ms, 420 ms `brake`.

**`providerOffers`.** Etiqueta de precio: sube 12 px 420 ms, luego `bob` 3,4 s. Pupila
(+3, −1).

**`providerCoin`.** El brazo sube 420 ms; a 210 ms la moneda sale de detrás de la palma:
translateY 30→−6→2→0 y scaleX 0,15→1 en 720 ms `brake`; al 80 % un destello de 4 puntas
(420 ms, uno solo). En reposo: gira de canto solo en el último tercio de un ciclo de 3,2 s
(0–68 % de frente, 79–86 % a 0,12) y el brillo la cruza una vez por ciclo. El **{n}** cuenta
de 0 a n a 120 ms por cifra desde 360 ms, cada cifra entra a 122 % y baja. Pupila (+4, −2).

**Reducir movimiento** (`JayaloMotion.reduced`): nada se anima ni transiciona; todo se pinta
en su estado final (pulgar arriba, moneda de frente, textos a opacidad 1, sin destello).
El pintor ya sigue esta regla: «estado base, no instante 0».

## 6. Datos: los créditos de regalo

- `fetchWelcomeCredits()` en `app/lib/data/repos.dart`: `supa.rpc('bonus_config')` → lee
  `welcome_credits` con un parser puro `welcomeCreditsFrom(dynamic row)` (fila o lista de
  una fila; entero ≥ 0; cualquier error o forma rara → `0`). Timeout corto (3 s).
- Se dispara en `_restore()` en paralelo con las lecturas de prefs. Mientras no resuelve,
  `_welcomeCredits` es `null`.
- **Se congela al elegir rol**: `_chooseRole` fija `_credits = _welcomeCredits ?? 0`. Que el
  valor llegue después NO cambia el número de láminas (si no, la lámina de accesos se
  movería bajo el dedo del usuario).
- `null`/`0`/error/sin red ⇒ **no existe** la lámina de la moneda: el proveedor ve 3 láminas
  y los accesos van en «Hacer ofertas es gratis». Doctrina: el gancho solo se promete si de
  verdad se paga (misma regla que la web en `ProviderSignupDialog`).
- `LoginScreen` recibe `fetchWelcomeCredits` inyectable (por defecto la función real) para
  que los tests fijen 5 o 0 sin red.

## 7. Jayi: poses

`enum JayiPose { open, thumbsUp, free, priceTag, coin }`. Se retiran `consumerOffers`,
`consumerLock`, `providerTray` y la moneda violeta (`providerCoin`), que ya no tienen lámina.

Anatomía **intocable** (`app/assets/images/mascot.png`): cuerpo cuadrado redondeado violeta
del isotipo (`0xFF6B3FE8`), UN ojo blanco descentrado a la izquierda con pupila
(`0xFF5A2FD6`) abajo-derecha, DOS antenas curvas lisas, sin boca, sin cachetes. Lo nuevo son
brazo y objeto.

- **open**: brazos abiertos (`M33 78 Q24 76 18 70` y `M107 78 Q116 76 122 70`) y las dos
  tarjetas flotantes (izquierda: renglones de solicitud; derecha al 78 %: punto blanco y dos
  renglones, la oferta).
- **thumbsUp**: grupo que rota desde el hombro (104, 78): brazo `M104 78 Q116 72 124 60`,
  puño `RRect(116, 50, 21×17, r 7.5)`, pulgar `RRect(115.5, 35, 8.5×20, r 4.25)` rotado −14°
  sobre (119.75, 53), dos líneas de nudillos en `0xFF5A2FD6` al 55 %.
- **free**: brazos abiertos sin tarjetas; flote amplio.
- **priceTag**: brazo `M104 78 Q114 76 120 68`, etiqueta (path del mockup de agosto), agujero
  blanco (124, 47) r 4, dos renglones blancos.
- **coin**: brazo `M104 78 Q118 76 126 66` + palma `M124 68 Q134 72 146 66` (grosor 7);
  moneda centro (141, 46) r 16 con degradado `#FBD66E→#E5A72A`, borde `0xFFC98D1F` 2,6,
  anillo interior `0xFFFFF0BF` 2 al 90 %, una «J» en `0xFFC98D1F` 2,4; brillo: rect blanco
  7×40 al 55 % rotado 28°, recortado al círculo, que cruza de −26 a +26; destello: estrella
  de 4 puntas `0xFFF2BD4A` en (158, 27). **La moneda es el único elemento no violeta** de
  todo el intro.

Pupila por pose (unidades del viewBox 120 de Jayi): open (−1, +2), thumbsUp (+3, −3),
free (0, 0), priceTag (+3, −1), coin (+4, −2); interpola 420 ms `emphasized`.

## 8. Arquitectura

| Fichero | Responsabilidad |
|---|---|
| `app/lib/core/motion.dart` | + `intro`, `introGesture`, `introLand`, `introRead`, `introHint`, `bounce` |
| `app/lib/features/auth/intro_copy.dart` | `IntroSlide{shout?, headline, highlight?, sub, counter?}`, `IntroStep`, `introSteps()`, `introSlideFor()`, `IntroRoleCard`, todos los copys |
| `app/lib/features/auth/intro_reveal.dart` | **nuevo**: `IntroReveal` (fade + subida con retardo, respeta reduce-motion), `IntroWords` (titular palabra a palabra), `IntroCounter` (cuenta 0→n con golpe por cifra) |
| `app/lib/features/auth/jayi_scene.dart` | `JayiScene(pose:)` persistente: aterrizaje, saltito, cambio de mano animado, poses nuevas, oro |
| `app/lib/features/auth/login_screen.dart` | escenario FUERA del PageView, láminas por `IntroStep`, recuadros nuevos, chevrón atrás, reacción con temporizadores, créditos congelados, puntos con nacimiento |
| `app/lib/data/repos.dart` | + `fetchWelcomeCredits()` y `welcomeCreditsFrom()` |

Decisión clave: **se mantiene el `PageView`** (deslizar, PopScope y `animateToPage` ya
están probados) y se saca de él **solo la escena**. El PageView pasa a llevar copy + acción;
`JayiScene(pose: _poseFor(_page))` vive entre la fila superior y el PageView, y anima el
cambio de pose por su cuenta al recibir un `pose` distinto en `didUpdateWidget`.

`JayiScene` guarda `_pose`, `_prev`, `_changedAt` (segundos del ticker) y pinta: el
aterrizaje (primeros 720 ms desde el montaje), el saltito (primeros 560 ms tras entrar en
`thumbsUp`), la entrada del accesorio nuevo y la salida del anterior (250 ms). Con
`animated == false` no hay ticker: `since = ∞` ⇒ estado final, sin accesorio saliente.

## 9. Pruebas

- `intro_copy_test`: `introSteps` en sus 5 casos; el cliente tiene 3 pasos y el proveedor 4
  con bono y 3 sin bono; el `highlight` es subcadena; ningún copy vacío salvo el `sub` de la
  moneda; el grito solo existe en `react`.
- `intro_reveal_test` (nuevo): con reduce-motion el hijo está a opacidad 1 en el primer
  frame; con animación, opacidad 0 al montar y 1 tras `delay + duration`; `IntroCounter`
  muestra `5` al terminar y un valor intermedio a mitad.
- `jayi_scene_test`: las 5 poses pintan sin lanzar; la lámina 0 pinta `open`, la reacción
  `thumbsUp`, el cliente final `free`, el proveedor `priceTag` y `coin`.
- `jayi_scene_pixels_test`: las 5 poses son distintas entre sí; **la moneda pinta píxeles
  dorados** (canal R alto y B bajo en la zona de la moneda) con reduce-motion; y el cambio
  de pose ANIMA: a 100 ms de `open→thumbsUp` el frame difiere del final a 800 ms.
- `login_intro_carousel_test` (reescritura de los 13): copy nuevo en la lámina 0; los DOS
  recuadros; elegir proveedor con 5 créditos ⇒ 4 puntos y la moneda al final con «5»; con 0
  créditos ⇒ 3 láminas y los accesos en «Hacer ofertas es gratis»; la reacción avanza sola
  a los 2 600 ms (pump 2 599 no, 2 601 sí); «Siguiente» fantasma aparece a 1 000 ms; atrás
  desde la reacción cancela el avance; los dos recuadros seguidos: gana el primero; con rol
  guardado arranca en la última lámina (esperando a los créditos); saltar sin rol ⇒ 2
  láminas con el cierre neutro y sin rol guardado; PopScope igual que hoy; el avance con
  animaciones ANIMA (mitad del recorrido con las dos láminas visibles).
- `login_intro_once_test`: mismos 6 casos con el copy nuevo.
- Comentarios con «Busco algo / Vendo algo» actualizados (no rompen nada, pero mienten).

## 10. Fuera de alcance (tandas siguientes)

- La web (mismo guion como pantalla previa al login).
- El puente a la primera solicitud (abrir el creador al cliente nuevo con 0 solicitudes).
- Repetir el intro desde Ajustes (sigue siendo una vez por teléfono).
- Cambiar el diálogo de permiso de notificaciones que tapa los recuadros en la primera
  apertura (defecto conocido desde el 08-20, se conduce el smoke concediéndolo por adb).

## 11. Riesgos y gotchas heredados

- **Un APK local no se instala encima del de Play** (firmas distintas): el smoke exige
  desinstalar, y al desinstalar se pierde `intro_seen_v1`, que es justo lo que se quiere.
- `pumpAndSettle` no asienta con el ticker perpetuo de `JayiScene`: los tests con animación
  van con pumps explícitos.
- Con `disableAnimations` no se ejercita `animateToPage`: el test del avance animado se
  mantiene.
- `_afterLayout` es obligatorio al cambiar `itemCount` y pedir página en el mismo frame.
- `dart format` reescribe medio repo: formatear solo los ficheros tocados.
- El repo vivo es `C:/Users/ac/Downloads/jayalo-app` (rama `feat/fecha-pautada-app`, HEAD
  `77f77c2`) con `app/pubspec.yaml` sucio (`+130→+132`, de otra sesión): esta tanda va en
  **worktree propio** `C:/Users/ac/Downloads/jayalo-app-intro`, rama
  `feat/intro-jayi-te-recibe`, y no toca ese fichero hasta el bump final (`+133`).

## 12. Decisiones del PO en esta tanda

- Jayis nuevos: pulgar arriba y moneda dorada. ⛔ No usar `jayi_celebrando`.
- Íconos de los recuadros **sin fondo**.
- Orden de tandas: app → web → puente a la primera solicitud.
- Aprobado: reacción que avanza sola, «5» desde configuración (sin lámina si vale 0),
  «Jáyalo» con tilde, apoyos de propuesta, único rebote en pulgar y grito.
