# Smoke — onboarding de primera apertura, app (2026-08-20)

Estado: **sin ejecutar** (pendiente, PO en device). Este guion es la parte NO automatizable de la
Task 5 del plan `docs/superpowers/plans/2026-08-19-onboarding-primera-apertura-app.md`
(`.superpowers/sdd/2026-08-19-onboarding-primera-apertura-app/task-5-brief.md`, Ruling A4). La
parte automatizable (gates + verificación de compilación) ya corrió — ver
`task-5-report.md` en la misma carpeta.

## Contexto

Rama `feat/play-billing`, HEAD verificado `f3099af`. Tasks 1-4 completas (láminas dentro de
`LoginScreen`, sin tocar el router de sesión; elección de rol en `SharedPreferences` bajo
`intro_role_choice`, consumida y borrada en `introRoleRedirect`). Ficheros involucrados:
`app/lib/features/auth/login_screen.dart`, `app/lib/features/auth/intro_copy.dart`,
`app/lib/features/auth/intro_role_store.dart`, `app/lib/core/router.dart`,
`app/lib/core/session_state.dart`, `app/lib/features/onboarding/choose_role_screen.dart`.

**Gotcha de instalación:** `flutter install` **no recompila**; hay que `flutter build apk
--release` (o `--debug` para pruebas rápidas) **antes**. La ruta del APK para `adb` va en formato
Windows (`C:/...`), no `/c/...`. Un APK debug **no** instala sobre un release instalado — desinstalar
primero. Conducir el device por `adb` según la nota de memoria
`jayalo-conducir-device-por-adb` (factor ×1.36 entre captura y pantalla real; sondear estabilidad
por tamaño de PNG, no por sleeps a ojo).

**Prohibido para este agente, no para el PO:** construir el AAB o el APK release. El PO decide
cuándo y con qué build corre este guion.

---

## Paso 1 — Compilar e instalar (lo hace el PO)

- [ ] `flutter build apk --release` (o `--debug`) desde `app/`.
- [ ] Si había un build anterior de signo distinto instalado (debug↔release), desinstalar antes.
- [ ] Instalar y confirmar que abre.

## Paso 2 — Recorrido de cliente, con cuenta nueva

- [ ] 1. Instalación limpia (o sesión cerrada) → sale la lámina 1 con los **dos recuadros**
      («Busco algo» / «Vendo algo»); tocarlos NO navega por sí solo, solo bifurca la lectura.
- [ ] 2. «Busco algo» → láminas 2 y 3 de **cliente**. El titular de la lámina común tiene el
      realce violeta en «quien pide» (Ruling A3: un solo realce, no dos).
- [ ] 3. En la lámina 3 están **los dos accesos**: Google en pill y el enlace de correo.
- [ ] 4. Google → cae **directo** en el alta de cliente, **sin pasar por `ChooseRoleScreen`**.
- [ ] 5. Completar el alta: el **OTP de WhatsApp sigue siendo bloqueante**, igual que antes de
      este cambio.

## Paso 3 — Recorrido de proveedor

- [ ] 1. «Vendo algo» → láminas 2 y 3 de **proveedor** (copy distinto al de cliente, mismo
      armazón).
- [ ] 2. Google (o correo) → cae en `/onboarding/provider`.
- [ ] 3. El realce violeta de la lámina común sigue en «quien pide», no cambia por rol.

## Paso 4 — Casos borde

- [ ] 1. **Elegir «Vendo algo» con una cuenta de Google que YA es cliente** → debe ir a su panel
      de cliente, **no** al alta de proveedor. Es el caso que más fácil se rompe (rol real gana
      sobre la elección guardada).
- [ ] 2. **Matar la app tras elegir rol, antes de autenticar** → al reabrir, NO repite el intro
      (arranca en la lámina 3) y el acceso lleva a la alta ya elegida.
- [ ] 3. **«Saltar»** desde la lámina 1 → llega al cierre normal (Google + correo) y, tras Google,
      cae en `ChooseRoleScreen` — es la red de seguridad para quien no eligió rol.
- [ ] 4. **Segundo usuario en el mismo teléfono:** cerrar sesión, registrar otra cuenta con el rol
      contrario al del primer usuario. Si hereda el rol del anterior, el `clear()` de la Task 4
      (Ruling A6) NO está corriendo — es un fallo real, no cosmético.
- [ ] 5. **Reduce-motion** encendido en accesibilidad del sistema → sin animaciones (o mínimas),
      todo el texto de las tres láminas legible y sin recorte.

## Paso 5 — Atención especial (candidatos a ajuste conocidos, no bloqueantes por sí solos)

- [ ] 1. **Reparto vertical de la portada con el carrusel.** El cálculo es
      `math.min(300.0, box.maxHeight * .45)` en `login_screen.dart:283` (Ruling A7: se aceptó
      aunque la portada era "no se toca", porque cierra un assert real preexistente de
      `cacheWidth 0`). Es el **candidato nº1** a ajuste visual — mirar en pantalla corta y en
      pantalla alta si el carrusel se ve aplastado o el texto se pega al borde.
- [ ] 2. **Botón atrás de Android en las láminas 2-3.** Hoy **sale de la app** (no hay
      `PopScope` en `login_screen.dart` — confirmado, minor M-5 del ledger). Anotar como
      comportamiento a evaluar por el PO, no como bug a arreglar de oficio: puede ser aceptable
      si "atrás" en la lámina 2/3 es equivalente a "salir del alta".
- [ ] 3. **Gotcha de instalación** (repetido aquí a propósito): `flutter install` no recompila;
      un APK debug no instala sobre un release sin desinstalar primero. Si el smoke "no ve" un
      cambio reciente, sospechar esto antes que el código.

---

## Cierre

Anotar el resultado de cada casilla en este mismo fichero al correrlo. Si algo falla, decidir con
el PO si se arregla antes de dar la Task 5 por cerrada o se registra como pendiente aparte.
**No pushear**: el push lo autoriza el PO (Ruling A2 del ledger — commits locales sí, push no).
