# El cliente ve si la oferta cubre sus condiciones (tanda C)

Fecha: 2026-08-03
Estado: aprobado por el PO, listo para plan de implementación

## El problema

El cliente marca condiciones al crear la solicitud. Desde la tanda A el proveedor las ve; desde la
tanda B las declara en su oferta y recibe un aviso si se queda corto. **Y ahí el dato muere.**

`provider_offers.has_fiscal_receipt` e `is_state_supplier` son hoy de **solo escritura en los dos
frentes**: nadie los lee, ni la web ni la app. El cliente que exigió comprobante fiscal recibe seis
ofertas y no puede distinguir cuál lo cubre. Le pedimos que declare una condición y no le devolvemos
nada.

No es un caso raro: **11 de 43 solicitudes piden comprobante fiscal** y 3 piden suplidor del Estado.

## Alcance

Dentro:

- La pantalla donde el cliente ve las ofertas de su solicitud, una por frente:
  `app/lib/features/client/request_status_screen.dart` y
  `jayalo-main/src/routes/requests/$requestId.tsx`.
- Una función de cotejo nueva en cada módulo de dominio, con el mismo nombre y la misma forma.
- Un componente de presentación por frente, en su propio fichero, probado aislado.

Fuera, **a propósito**:

- `MyRequestsView.tsx` de la web, que también lee ofertas. Se escribe aquí para que ninguna revisión
  lo reporte como olvido.
- El inbox del proveedor y el perfil público del negocio.
- Filtrar u ordenar ofertas por requisitos. Eso es matching, no visibilidad, y sería otra tanda.
- **Cualquier cambio de base de datos.** Ni migraciones ni grants.

## Lo que ya está puesto y C no repite

1. **Cero base de datos.** Las columnas existen desde las migraciones del 1 y 2 de agosto.
   Verificado contra `information_schema` el 2026-08-03: `anon` **y** `authenticated` tienen
   `SELECT` sobre las 45 columnas de `provider_offers`, las dos incluidas. Ampliar el `select` de la
   web no puede tumbar la consulta ni para un visitante sin sesión.
2. **Cero regla nueva de negocio.** `activeRequirements`, `OfferCapabilities`, `covers` y el orden
   canónico existen y están probados en los dos frentes con API idéntica
   (`app/lib/domain/request_requirements.dart`, `jayalo-main/src/lib/requestRequirements.ts`).
3. **La app no necesita ninguna lectura nueva.** `request_status_screen` ya carga
   `$requestRequirementCols` (tanda A) y `offerCols` ya trae las dos capacidades — se dejaron puestas
   en la tanda B precisamente para esto, y el comentario de `repos.dart` lo dice.

Lo único de datos en toda la tanda: añadir `has_fiscal_receipt,is_state_supplier` al `select` de
ofertas de la web, en `requests/$requestId.tsx` (~línea 388).

## Qué ve el cliente

Un bloque dentro de cada tarjeta de oferta, **solo si el cliente marcó al menos una condición
cotejable**. Si no marcó ninguna, la tarjeta se ve como hoy: sin ruido añadido en el ~60% de las
solicitudes. Si marcó **solo evaluación**, tampoco sale nada — la evaluación no es cotejable, y ese
carve-out ya está escrito y razonado en los dos módulos.

```
Tus condiciones
  ✓  Envío
  ✓  Comprobante fiscal
  ·  Suplidor del Estado — no lo declaró
```

Una fila por condición del cliente, en orden canónico (envío → instalación → fiscal → Estado), con
las etiquetas `short` que ya existen y **no se reescriben**.

## Decisiones del PO

- **La fila negativa dice "no lo declaró"**, nunca "no cumple" ni "no emite". Es la doctrina de B
  invertida: allí se avisaba de más sin afirmar nada en nombre del proveedor; aquí se informa de
  menos por la misma razón.

  Y hoy es lo único cierto. Las columnas son `NOT NULL DEFAULT false`, así que `false` significa dos
  cosas incompatibles: "el proveedor vio la casilla, y hasta el aviso de la tanda B, y aun así no la
  marcó" (ofertas desde el 1 de agosto) y "se ofertó antes de que la pregunta existiera". A
  2026-08-03 son **33 de 34 ofertas** las del segundo caso. Se descartó distinguirlas por fecha de
  creación: sería más preciso, pero mete una fecha mágica en el código que habría que explicar para
  siempre.

- **Tono neutro y apagado** en la fila negativa. Sin ámbar ni ícono de alarma. El cliente ve el hueco
  y decide; no se acusa a un proveedor que quizá sí cumple y solo no lo declaró.

- **La lista completa sale siempre**, aunque la oferta cubra todo. Se descartó colapsarla a una línea
  ("Cubre tus 2 condiciones"): el formato único es más predecible para el cliente y más fácil de
  probar, y el coste es unas pocas líneas en tarjetas de solicitudes que sí pedían algo.

- **Una superficie por frente y los dos a la vez.** Hacer solo uno dejaría al cliente viendo el dato
  en un sitio y no en el otro, que es peor que no tenerlo.

## Arquitectura

### La costura nueva, espejada en los dos frentes

```
requirementCoverage(req, cap) → [(condición, la cubre)]  en orden canónico
```

Pura, sin Flutter ni React, probada aparte. Es la **única** lógica que C añade. `activeRequirements`
ya sabe qué marcó el cliente y `covers` ya sabe qué declaró la oferta; esto los cruza y **conserva
los dos resultados**, en vez de quedarse solo con los fallos como hace `unmetRequirements`.

Vive junto a `unmetRequirements` en el mismo módulo, a propósito: separar las dos mitades invitaría a
que cada una redactara sus etiquetas por su cuenta.

### El componente de presentación

Uno por frente, en su propio fichero, que recibe la lista ya calculada y no vuelve a decidir nada.

En la app hay un precedente **en el mismo fichero** que hay que seguir: `_OfferCard` es privado, y por
eso en su día se extrajo `OfferCardProviderHeader` como widget **público** para poder probarlo. El
componente de C se extrae igual, y `_OfferCard` lo compone.

`RequestStatusScreen` recibe solo un `requestId` y carga en `initState` sin fuente inyectable: **no
tiene costura**. Como en la tanda B, no se inventa una: el componente se prueba aislado y el cableado
se verifica en device.

## Pruebas

**`requirementCoverage`, los mismos casos en los dos frentes:**

- Sin condiciones marcadas → vacío.
- Solo evaluación marcada → vacío (nunca es cotejable).
- Las cuatro marcadas y la oferta sin declarar nada → cuatro filas, todas en falso.
- Mezcla: unas cubiertas y otras no.
- Ofrecer de más (la oferta declara algo que el cliente no pidió) no añade filas.
- El orden lo fija la declaración del enum, no el de los campos.

**El componente, aislado:**

- Pinta la lista completa aunque estén todas cubiertas.
- Dice "no lo declaró" y **nunca** las palabras "no cumple" ni "no emite" — un test lo blinda, igual
  que en la tanda B un test blinda que el copy del proveedor no prometa lo que no ocurre.
- Sin condiciones cotejables activas, no pinta nada.
- Modo oscuro (app).

**Nota sobre un test existente:** `offer_requirements_warning_test.dart` afirma que el copy del aviso
al proveedor no contiene "el cliente verá". **Se queda como está.** C hace que el cliente lo vea, pero
el copy del proveedor sigue sin prometerlo, y prometerlo abriría la puerta a que alguien lo cambie sin
comprobar que sigue siendo verdad.

## Riesgos

1. **El copy es lo único nuevo, y es donde los dos frentes pueden divergir.** Las etiquetas que
   existen están redactadas para el proveedor ("Requiere comprobante fiscal") y no sirven para
   decirle al cliente que su condición está cubierta. Mitigación: `requirementCoverage` devuelve
   claves, y cada frente compone con los `short`, que ya son idénticos en los dos módulos.
2. **El cableado de la pantalla de la app no lo cubre ningún test**, por la falta de costura. Se
   verifica en device, con guion de smoke, como en la tanda B.
3. **Los datos reales están casi todos en `false` por antigüedad.** Un smoke que solo mire ofertas
   viejas verá todas las filas en negativo y parecerá roto. El guion debe crear una oferta nueva
   declarando algo.
