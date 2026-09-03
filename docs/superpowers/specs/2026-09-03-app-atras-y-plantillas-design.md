# App Android: «Atrás» en el creador de solicitudes + registro de la conversación + modo plantilla

**Fecha:** 2026-09-03 · **Aprobado por el PO** en chat (alcance, orden y gesto Android).
**Repo:** `jayalo-app` (Flutter), carril base `feat/fecha-pautada-app`, rama `feat/atras-y-plantillas-app`.
**Paridad con la web:** `jayalo-main` — spec `docs/superpowers/specs/2026-09-02-plantillas-por-rubro-fase1-design.md`
(§6 turno `template`, §6.4 cliente, §13 «Atrás»), `src/lib/aiTurns.ts`, `src/lib/templateRun.ts`,
`src/lib/requestTranscript.ts`, `src/routes/requests/new.tsx`.

## 1. Contexto

La app crea solicitudes con el MISMO endpoint que la web (`/api/ai/chat-stream`, un POST por turno,
`core/ai_client.dart`), parsea los turnos en `domain/ai_turns.dart` y pinta la conversación en
`features/client/create_request_screen.dart` (2578 líneas). Hoy:

- No hay «Atrás» dentro de la conversación: un toque equivocado obliga a salir y empezar de cero.
- El gesto ATRÁS de Android sale de la pantalla (con el diálogo de «perder lo escrito» del
  `BackGuard` + `unsaved_guard.dart`).
- Las respuestas se guardan en el historial como texto suelto (`AiMessage('user', text)`); la web
  las guarda como `Pregunta: <q>\nRespuesta: <a>`.
- La app NO guarda la transcripción (`request_ai_transcripts`): sus solicitudes no alimentan la
  biblioteca de patrones. El parser de `ready` descarta `attributes` y `meta`.
- La app no manda `useTemplates` y no conoce el turno `template`: lo desplegado en la web el
  2026-09-03 no la afecta.

## 2. Objetivos

1. «Atrás» en cada turno de la conversación, sin llamadas al servidor, con el gesto de Android
   deshaciendo un paso.
2. La app registra la conversación como la web (fase 0), en el mismo formato, para que el
   constructor nocturno pueda leerla.
3. Modo plantilla en la app calcado de la web, DORMIDO detrás del mismo interruptor del servidor.

## 3. No objetivos

iOS (decisión de producto), panel de administración, promoción del AAB +100 en Play, cambios en el
servidor (todo el contrato ya está vivo), cambiar el diseño visual del creador más allá del botón.

## 4. Orden de entrega

Dos carriles sobre la misma rama, cada uno con APK en el teléfono del PO para smoke:

- **Carril 1:** «Atrás» + formato de respuestas + transcripción (§5-§7).
- **Carril 2:** modo plantilla (§8).

## 5. «Atrás»

### 5.1 Lógica pura (`domain/ai_turns.dart`)

- `turnToJson(AiTurn)` sale de la pantalla al dominio (hoy `_turnToJson` privado): el historial
  tiene que ser rehidratable desde el dominio. `AiReady` gana `attributes: Map<String,String>` y
  `meta: ({String model, String promptVersion})?`, y `turnToJson` los conserva (`attributes` y
  `meta` solo si vienen). `AiQuestion` gana `attribute: String?` (lo manda el prompt 2026-09-03.1).
- `parseAssistantTurn(String content) → AiTurn?`: `null` si no es JSON o no es un turno conocido
  (NUNCA lanza; `parseAiTurn` sigue lanzando `FormatException` para el turno recién recibido).
- `const secondPhotoMsg = 'Aquí tienes otra foto para más contexto.'` y
  `keepsSecondPhoto(List<AiMessage>)`: la segunda foto sigue mientras ese mensaje siga en el
  historial. (Hoy la app manda la 2ª foto con su propio texto: pasa a usar este literal, que es el
  de la web, para que el servidor la adjunte al mismo mensaje.)
- `StepBack stepBack(List<AiMessage> messages)` → `({List<AiMessage> messages, AiTurn? turn})`, MISMA
  semántica que la web:
  1. quita todos los turnos `assistant` del final (puede haber varios seguidos: routing + ready);
  2. quita los `user` del final (la respuesta que los provocó);
  3. el último `assistant` que parsee es el turno al que se vuelve; si no parsea se sigue hacia
     atrás; si no queda ninguno ⇒ `messages: []`, `turn: null` (= compositor con texto y foto).
- `int answeredCount(List<AiMessage>)`: número de mensajes `user` que responden a un `question` o
  `kind_switch` (los que van justo después de uno de esos turnos). Sustituye a los contadores
  sueltos `_answers`/`_aiAnswered`: con «Atrás» un contador incremental se desincroniza.

### 5.2 Pantalla

- Botón «Atrás» (texto, icono `arrow_back`, mismo estilo que «Otra opción») en los turnos
  `question`, `kind_switch`, `image_request`, `routing` y `ready`. Oculto mientras `_busy` y
  mientras `_correcting`. No existe en el compositor inicial.
- `_goBack()`: `stepBack(_messages)` → si `turn == null`: `_messages.clear()`, `_current = null`,
  `_ready = null`, `_categories/_rubros` a vacío, se vuelve al compositor con `_input` y `_photos`
  intactos (la 1ª foto NUNCA se suelta: viaja en cada POST, no en el historial). Si `turn != null`:
  `_messages` = los devueltos, `_current = turn`, `_ready = turn is AiReady ? turn : null`,
  `_categories/_rubros` = los del último `routing` que quede en el historial (o vacío). En ambos
  casos: si `!keepsSecondPhoto(_messages)` y hay 2 fotos, se quita la 2ª. Sin llamadas.
- «Pregunta N» y la barra de progreso leen `answeredCount(_messages)`; `_answers` desaparece y
  `_hasUnsavedWork` usa `_messages.isNotEmpty || _input.text.isNotEmpty || _photos.isNotEmpty`.
- Las correcciones tras la ficha (`_correcting`) no cambian: siguen añadiendo `user` + `assistant`,
  y «Atrás» las deshace como cualquier otro paso.

### 5.3 Gesto ATRÁS de Android

`unsaved_guard.dart` gana un segundo gancho en la misma pila: `takeBackStep(owner, bool Function()
step)` / `releaseBackStep(owner)` y `bool tryBackStep()` (llama al `step` del TOPE; `true` = consumió
el gesto). `BackGuard` (`features/shell/back_guard.dart`) llama `tryBackStep()` ANTES de
`hasUnsavedChanges()`: si consumió, no hace nada más; si no, sigue el flujo de hoy (diálogo si hay
cambios, salir si no). El creador registra `step: () { if (_messages.isEmpty || _busy) return false;
_goBack(); return true; }` en `initState` y lo suelta en `dispose`. La navbar (`home_shell`) NO
consulta `tryBackStep`: cambiar de pestaña no es «un paso atrás».

## 6. Formato de las respuestas

Al responder a un `question` la app guarda `Pregunta: <question>\nRespuesta: <texto>` (web
`new.tsx` L781). Al responder «No» a un `kind_switch`: `Pregunta: <message>\nRespuesta: No, sigo
como <kind>.` (web L1950); el «Sí, cambiar» reinicia el historial con el primer mensaje, como hoy.
El auto-«ok» del routing, la foto y las correcciones no cambian. El modelo ya recibe este formato
desde la web; el constructor lo exige (`request_template_qa_pairs` lee `\nRespuesta:`).

## 7. Transcripción (fase 0 en la app)

- `data/repos.dart` `submitRequest` devuelve el `id` de la fila (`.insert(...).select('id')
  .single()`; la política «Requests: select» del dueño ya lo permite).
- `domain/request_transcript.dart`: `buildTranscript(requestId, messages, {attributes, model,
  promptVersion, source, templateId, templateVersion}) → Map<String,dynamic>?` calcado de
  `requestTranscript.ts`: `question_count` = turnos `question` del historial; `other_count` =
  respuestas a `question` que no calzan (sin mayúsculas/acentos/espacios) con ninguna opción del
  turno; `null` si `messages` vacío o `jsonEncode(messages)` supera 60 000 bytes; `source`
  `'template'` sin `templateId` se degrada a `'ai'` (el CHECK de la BD lo exige).
- Tras publicar, best-effort y SIN bloquear el «Publicada»: `supa.from('request_ai_transcripts')
  .insert(row)`; el error va a `reportError`, nunca a la UI. Columnas exactas del grant:
  `request_id, messages, attributes, question_count, other_count, model, prompt_version, source,
  template_id, template_version` (CHECK #26 de la web las lista).
- `model`/`prompt_version` salen de `AiReady.meta` (null si el servidor no los mandó);
  `attributes` de `AiReady.attributes`.

## 8. Modo plantilla

### 8.1 Contrato (ya vivo en el servidor)

- Body del PRIMER turno: `useTemplates: true` (junto a `wantReadyNext`). Solo con
  `messages.length == 1` el servidor mira plantillas; si el interruptor está apagado o no hay activa
  para el ámbito, responde el turno de siempre. Las apps viejas no mandan el flag ⇒ nada cambia.
- Turno `template`: `{type:'template', template:{id, version, scope, questions:[{key, label,
  question, options:[...]}]}, routing:{categories, rubros}, known_attributes:{k:v}, aiTicket}`.
  Cualquier forma inesperada ⇒ `null` (nunca lanza) ⇒ se trata como turno de IA fallido: toast
  «Algo falló» + el usuario reintenta, que es el fallback natural (el servidor volverá a mandar la
  plantilla; si vuelve a fallar el parseo, el flag se deja de mandar en esa conversación).

### 8.2 Lógica pura (`domain/template_run.dart`, calcada de `templateRun.ts`)

`AiTemplate` (nuevo `AiTurn`), `parseTemplateTurn(Map) → AiTemplate?`, `pendingQuestions(t,
answers)`, `const otherOption = 'Otra opción'`, `templateQuestionTurn(q) → AiQuestion` (opciones +
«Otra opción», `allowOther: true`, `attribute: key`), `isOther(q, answer)`, `answerMsgs(q, answer)`
(mismo par `assistant`+`user` que la web, con el formato de §6), `buildTemplateReady(t, answers,
scopeLabel) → (ready, routing)`: respuestas recortadas y vacías fuera, título `tipo ?? scopeLabel`
+ `marca` + `modelo` (120 máx., «Solicitud» si queda vacío), bullets `label: valor` en el orden de
la plantilla + los conocidos sin pregunta con `initcap`, `meta {model:'template',
promptVersion:'<scope>@v<version>'}`, `wholesale: false`.

### 8.3 Pantalla

- Estado `_templateRun` `{id, version, scope, answers, otherCount, fellBack, fallbackKey, runId}`.
- Al recibir `AiTemplate`: se crea el run (`runId` = uuid v4 local), se pinta la primera pregunta
  pendiente con la UI de `question` de siempre, y DESPUÉS (fire-and-forget, `reportError` si falla)
  `INSERT request_template_runs (id, user_id, template_id, template_version)` — exactamente esas
  columnas: cualquier otra tumba la petición con 42501.
- Cada respuesta: `answerMsgs` al historial, `answers[key] = texto`, `otherCount++` si `isOther`;
  siguiente pendiente o, si no quedan, `buildTemplateReady` ⇒ `routing` + `ready` locales al
  historial (mismos JSON que `turnToJson`) y `_handleTurn(ready)` sin POST. `scopeLabel` = nombre
  de la categoría del routing si la app lo tiene cargado, si no el `scope` tal cual.
- «No es esto» (en la ficha) y cualquier corrección (`_correcting`) en modo plantilla ⇒
  `_fallBackToAi(handoff, fallbackKey)`: marca `fellBack`, `UPDATE request_template_runs SET
  outcome='fallback', fallback_key, answered_count, other_count, ended_at WHERE id=runId`
  (best-effort), y manda al servidor el historial COMPLETO (primer mensaje + pares de plantilla +
  el handoff) SIN `useTemplates`; la respuesta se trata como turno de IA normal. `fallbackKey` =
  la key de la pregunta en curso o `null` desde la ficha.
- «Atrás» en modo plantilla: `stepBack` sobre el historial y `answers` se recalcula desde los
  pares que queden (los `assistant` con `attribute`); si el historial queda en el primer mensaje
  se vuelve a mostrar la primera pregunta pendiente (sin POST).
- `kind_switch` «Sí, cambiar» limpia `_templateRun` (run `abandoned` best-effort si no había caído)
  y reinicia con `useTemplates: true`.
- Publicar: transcripción con `source: fellBack ? 'fallback' : 'template'`, `templateId`,
  `templateVersion`; run `UPDATE outcome='published', answered_count, other_count, title_edited:
  false, request_id, ended_at` (la app no edita el título en la ficha; queda `false`).
- `useTemplates` se manda SOLO cuando `_messages.length == 1` (primer turno y reinicio por
  `kind_switch`).

## 9. Errores

Todo lo nuevo es best-effort excepto la propia solicitud: runs y transcripción nunca bloquean ni
enseñan error (`reportError`). `stepBack` no puede fallar (puro). Un turno `template` malformado no
rompe: toast + reintento. Un servidor viejo ignora `useTemplates`. La app vieja ignora `template`
porque nunca lo pide.

## 10. Tests

`flutter test` (existen `test/ai_turns_test.dart`, `ai_client_test.dart`, `back_intent_test.dart`).
Nuevos, de dominio puro y TDD: `stepBack` (desde question, desde ready tras routing, historial con
JSON roto, hasta el inicio, segunda foto), `answeredCount`, `turnToJson` round-trip con
`attributes`/`meta`, `buildTranscript` (los 10 casos de la web), `template_run` (los casos de
`templateRun.test.ts`), `unsaved_guard` (`tryBackStep` consume/no consume, pila). `ai_client_test`:
el body lleva `useTemplates` solo en el primer turno. Widget test mínimo del botón «Atrás» si la
pantalla admite montarse sin Supabase; si no, se documenta y el smoke lo cubre.

## 11. Entrega y smoke

APK `1.0.4+101` desde la rama, con el sello de build en Ajustes → «Esta versión». Instalación por
adb en el teléfono del PO. Smoke del carril 1: pregunta → «Atrás» → vuelve la anterior; gesto
Android ×N → compositor con texto y foto; publicar → fila en `request_ai_transcripts` con
`Pregunta:/Respuesta:` y `attributes`. Carril 2 sin smoke visible hasta que exista una plantilla
activa; se certifica con tests + una sonda del body.

## 12. Minas conocidas

- Worktree hermano sucio = diseño que desaparece del APK: commitear antes de compilar.
- El carril vivo es `feat/fecha-pautada-app`; compilar desde otro quita fecha pautada y contador.
- `aapt` tipa los `meta-data`: el sello de build ya lo resuelve Gradle.
- Los grants por columna de `request_template_runs` y `request_ai_transcripts` son la frontera: un
  campo de más en el payload = 42501 en la petición entera.

## 13. Contraste con el código (2026-09-03, tras leer la app; manda el código)

Refinamientos aprobados al escribir el plan; donde chocan con §5-§8, vale esto:

1. `AiMessage` vive en `core/ai_client.dart`: se MUEVE a `domain/ai_turns.dart` y se re-exporta.
2. `AiTurn` es `sealed`: `AiTemplate`, `parseTemplateTurn` y `TemplateQuestion` se declaran en
   `ai_turns.dart`; `template_run.dart` los re-exporta.
3. No hay paquete `uuid`: `runId` usa `newRequestClientId()` (`data/repos.dart`, v4 con `Random.secure()`).
4. `reportError(Object error, StackTrace? stack)` existe en `core/error_reporter.dart`.
5. La app admite DOS fotos en el compositor: «Atrás» solo suelta la 2ª si entró por el chat
   (`_secondPhotoFromChat`). El literal `secondPhotoMsg` pasa a ser el de la web.
6. «Sí, cambiar» de `kind_switch` HOY no reinicia el historial en la app: pasa a reiniciarlo
   (paridad web; §8.3 lo necesita para volver a mandar `useTemplates`).
7. «No es esto» no existía: la ficha tiene «Corregir algo». En modo plantilla la corrección ES el
   handoff, y se añade «No es esto» solo en modo plantilla.
8. `_hasUnsavedWork` conserva la regla de la siembra; solo se quita `_answers.isNotEmpty`.
9. La flecha de la cabecera sigue SALIENDO de la pantalla; solo el gesto de Android deshace un paso.
10. `submitRequest` devuelve `String?`: en el reintento 23505 no hay id y la transcripción se salta.
11. El auto-«ok» del routing sigue siendo `'ok'` en el flujo de IA; el cierre local del modo
    plantilla usa el literal de la web.
