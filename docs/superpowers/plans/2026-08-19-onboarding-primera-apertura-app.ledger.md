# SDD ledger — plan: docs/superpowers/plans/2026-08-19-onboarding-primera-apertura-app.md

Repo: C:/Users/ac/Downloads/jayalo-app-playbilling (worktree VIVO; jayalo-app está congelado)
Rama: feat/play-billing · BASE inicial: c625e87
Spec: ../jayalo-main/integracion/docs/superpowers/specs/2026-08-19-onboarding-tres-pasos-design.md (autoridad)
⚠️ Árbol SUCIO con trabajo del PO sin commitear (duración de oferta, 10 ficheros). NO tocarlos, NUNCA `git add -A`.

## Escaneo previo de conflictos

### Pares que comparten fichero o interfaz
| Par | Produce → consume | Hallazgo |
|---|---|---|
| 1 → 2 | `IntroRole` | OK (import desde intro_role_store.dart) |
| 1 → 3 | `IntroRoleStore.save/read`, `kKey` | OK |
| 1 → 4 | `IntroRoleStore.read/clear`, `IntroRole` | OK |
| 2 → 3 | `kIntroCommon`, `kIntroSlides`, `IntroSlide` | OK |
| 3 → 4 | ninguna directa (3 guarda, 4 lee) | OK |
| 3 ↔ tests existentes | password_login_error_test y cualquier test que monte /login | ⚠️ previsto por el plan: se arreglan sembrando rol en setUp, no borrándolos |

### Coherencia interna
| Task | Hallazgo |
|---|---|
| 1 | OK. 6 tests = implementación del brief |
| 2 | ⚠️ `kIntroCommon.highlight='quien pide'` cubre solo la primera de las dos frases violetas de la maqueta («quien pide» y «quien vende»). El modelo de datos tiene UN highlight. Ver Ruling A3 |
| 3 | Prose-based (sin código completo, deliberado: login_screen tiene 300+ líneas resueltas que no deben reescribirse) → implementador de más juicio |
| 4 | OK; función pura `introRoleRedirect` con 4 casos |
| 5 | Smoke en device = del PO. Parte automatable: gates + compilación. Ver Ruling A4 |

## Rulings previos
Ruling A1: **Árbol sucio del PO se respeta**: cada implementador stagea SOLO sus ficheros, prohibido `git add -A` y prohibido tocar los 10 ficheros de la duración de oferta. — Coste si me equivoco: ninguno; es la doctrina.
Ruling A2: **Commits locales sí, push no** (igual que el plan web).
Ruling A3: **El realce de la lámina común queda en «quien pide» (un solo highlight)** — ampliar el modelo a dos realces es YAGNI para una lámina; la maqueta pintaba ambos pero el dato admite uno. Anotado para el PO en la revisión final. — Coste: una palabra sin violeta; se amplía luego si al PO le importa.
Ruling A4: **La Task 5 se parte**: gates + `flutter build apk --debug` (verificación de compilación SIN release, el PO pidió NO construir el AAB) los corre un agente; el smoke en device queda documentado para el PO. — Coste: nada irreversible.
Ruling A5: comandos `flutter` se corren desde `app/`.

## Progreso
Task 1: complete (commits c625e87..e21680e, review clean; 6/6, analyze 0, commit aislado del árbol sucio del PO)
Task 2: minor (deferred): dart format reenvolvería ambos ficheros (venía así del brief; sin CI que lo exija)
Task 2: complete (commits e21680e..508f66b, review clean; copys byte-idénticos verificados programáticamente)
Task 3: implementado (3fa604e, 1353/1353). Revisión (opus): cumplimiento ✅ 13/13, calidad con 1 Crítico + 2 Important + 7 minors.
Ruling A6 (por el C-1): **la elección de rol FUGA si quien se autentica ya tiene rol resuelto** — el clear() del plan solo cubría el camino needsOnboarding. La Task 4 se AMPLÍA: además de consumir en el redirect de /onboarding, debe BORRAR la elección guardada cuando una autenticación termina con rol ya resuelto (consumer/provider), para que el siguiente usuario del mismo teléfono no herede lámina 3 + alta ajena. El comentario invertido de _restoreRole se corrige en el fix de la Task 3. — Coste si me equivoco: un clear de más; inocuo.
Task 3: minors (deferred): M-1 parpadeo de 1 frame al restaurar rol; M-2 guardas hasClients sin plan B; M-3 sombra de JayaloCard conmuta con tema oscuro sobre tarjetas de relleno claro fijo; M-4 PortadaJayi perdió const; M-5 sin PopScope (atrás sale de la app en láminas 2-3 → smoke); M-6 sin padding inferior en pantalla corta; M-7 _Dots pinta 3 con itemCount 1 (intencional).
Ruling A7: el cambio de bottomReserve a min(300, h*.45) SE ACEPTA aunque la portada era «no se toca»: cierra un assert real preexistente (cacheWidth 0); candidato nº1 a ajuste en el smoke del PO.
Task 3: fix round 1/5 EN CURSO (3 open: test del camino animado con pumps explícitos; guarda de reentrada + bloqueo de swipe con _busy; comentario invertido de _restoreRole)
Task 3: fix round 1/5 (3 addressed, 0 open — test animado con assert de mitad de recorrido validado por mutación; guarda _choosing por Completer; physics con _busy; comentario corregido; commits 3fa604e..034a114, suite 1355/1355)
Task 3: complete (commits 508f66b..034a114, review clean tras 1 fix round)
Task 4: complete (commits 034a114..f3099af, review clean; 10 tests nuevos, suite 1365/1365; orden global→ruta verificado contra el fuente de go_router 17.3.0)
Task 4: minors (deferred): clear() de A6 sin test directo (sin costura de mock para myProfile); doble clear() inocuo en alta nueva; unawaited fire-and-forget (patrón del repo)
Task 5: complete (commit 16d7f0f; analyze 0, 1365/1365, apk --debug compila con solo warnings preexistentes; NO se construyó AAB/release por orden del PO; smoke en docs/qa/2026-08-20-smoke-intro-app.md)

## Revisión final de rama (opus) + ola de arreglos
- Cumplimiento del spec (sección App): completo salvo 2 matices de copy para el PO.
- Arreglados: I-2 PopScope (atrás retrocede lámina); I-1 «Saltar» sin rol → cierre neutro con kIntroCommon (carrusel de 2); F-cabecera claim de cliente oculto en láminas 2-3 (showClaim, reversible); plan trackeado; versionCode 54 (12b9d10).
- Re-revisión cazó rotura nueva del propio fix: _skip() clavado a página 1 → arreglado con _pageCount-1 + _Dots con count real (5cc39dd), validado con test que discrimina.
Ruling A8: el commit ajeno 9053b7a (AiClient, otra sesión en el mismo worktree) se deja intacto y fuera de toda revisión mía.
Ruling A9: la línea de privacidad queda con DOS PUNTOS («privados: solo…») aunque el PO escribió coma — es byte-idéntica a la web ya implementada; la paridad entre plataformas gana. Decisión reversible del PO.
- Gates finales: analyze 0 · suite 1386/1386 (con los ficheros sucios de otras features en el árbol) · apk --debug compila · AAB NO construido (orden del PO).

FINAL: 5/5 tasks + 2 olas de arreglo. Rama c625e87..5cc39dd (mía: 9 commits; 1 ajeno interpuesto). versionCode 54 listo para el próximo AAB. Pendiente del humano: smoke docs/qa/2026-08-20-smoke-intro-app.md; decisiones de copy (A3 «quien vende» en violeta, A9 coma vs dos puntos); construir el AAB cuando decida.
