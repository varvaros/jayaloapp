# Hallazgo — "Ver mis ofertas" debería ser "Ver mi oferta" y llevar a ESA oferta

Fecha: 2026-08-03
Reportado por: el PO, usando la app
Estado: **sin diseñar**. Este documento es el punto de partida, no una solución aprobada.

## Qué pasa

El proveedor entra a una solicitud en la que **ya ofertó**. El panel de estado dice "Ya enviaste tu
oferta · Tu oferta: RD$X" y ofrece un botón **"Ver mis ofertas"** que lo saca a la lista completa de
sus ofertas.

Desde ahí tiene que volver a buscar, entre todas sus ofertas, la de la solicitud en la que ya
estaba. El contexto que tenía se pierde.

## Qué debería pasar (petición del PO)

El botón debería decir **"Ver mi oferta"**, en singular, y llevar directamente a **la oferta que hizo
en esa solicitud**.

## Dónde está, exactamente

**El botón:** `app/lib/features/provider/request_detail_screen.dart:942-950`. Es el brazo `_`
(comodín) de un `switch` sobre el estado de la oferta — el caso "enviada y todavía pendiente":

```dart
      _ => (
          dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
          Icons.check_circle,
          'Ya enviaste tu oferta',
          'Solo puedes ofertar una vez por solicitud. Tu oferta: $label. '
              'Si el cliente la acepta, te avisaremos para desbloquear el contacto.',
          'Ver mis ofertas',
          () => context.go('/provider/offers'),
        ),
```

Los otros brazos del mismo `switch` (`accepted`, y el de ya desbloqueada) tienen sus propios CTA y
**no** están afectados: solo cambia este.

**Cómo se abre una oferta concreta hoy:** `app/lib/features/provider/my_offers_screen.dart:455-462`.
Es el dato clave, porque ya existe la convención:

```dart
  void _openOffer(Map<String, dynamic> o) {
    ...
    context.push('/provider/request/${o['request_id']}?edit=${o['id']}')
```

Es decir: **"ver mi oferta" ya significa "abrir el detalle de la solicitud en modo edición"**. No hay
una pantalla de oferta suelta que haya que crear.

**El id de la oferta está a mano:** ese `switch` ya recibe la oferta `o` y usa `o` para componer
`$label`, así que `o['id']` está disponible sin ninguna consulta nueva.

## El nudo, y por qué no lo resuelvo aquí

La pantalla desde la que se pulsa el botón **es la misma** a la que habría que navegar. Copiar el
patrón de `my_offers_screen` tal cual —`context.push('/provider/request/<id>?edit=<offerId>')`—
apilaría una segunda copia de la misma pantalla encima de sí misma. Funcionaría, pero deja dos
instancias en la pila y un "atrás" que devuelve a la misma solicitud en modo lectura.

La alternativa es que la pantalla **entre en modo edición sobre sí misma**, sin navegar. Es más
limpio de pila, pero toca el estado de `request_detail_screen.dart`, que son 1654 líneas y **no tiene
costura de tests** (ver el spec de la tanda B). Cualquier cosa que se haga ahí se verifica en device.

Esa es la decisión de diseño que hay que tomar antes de escribir código, y por eso esto no es un
plan todavía.

## Qué comprobar antes de dar por bueno el arreglo

- El texto en singular: **"Ver mi oferta"**.
- Que lleve a la oferta de ESA solicitud, con sus datos cargados y editables.
- Que el botón "atrás" desde ahí deje al proveedor en un sitio razonable y no en un bucle.
- Que los otros brazos del `switch` (aceptada, desbloqueada) sigan intactos.
- Que "mejorar oferta" siga guardando — ver el punto 1 del smoke de la tanda B y la migración
  `20260803120000`, que arregló que esa ruta llevaba 5 días rota.

## Alcance

**Solo la app.** Se comprobó que en la web ese literal solo existe como CTA de correos de
notificación (`src/lib/email/notification-templates.ts:73,75`), donde llevar a la lista sí tiene
sentido porque el lector no viene de ninguna solicitud concreta. Esa parte no se toca.
