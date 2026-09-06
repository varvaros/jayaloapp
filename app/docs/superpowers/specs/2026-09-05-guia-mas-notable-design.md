# Guías spotlight más notables (botón `+` y resto de anclas)

**Fecha:** 2026-09-05 · **Estado:** aprobado por el PO sobre mockup
(https://claude.ai/code/artifact/38d3e210-844d-41cd-8074-26b65faefc83) · **Ámbito:** solo app Flutter,
presentación de `OnboardingGuide` + dos comportamientos del toque. Sin backend, sin store nuevo.

## Problema (medido en `onboarding_guide.dart`)

- El anillo del hueco es `cs.primary`, el mismo violeta que el botón `+`: no lo separa.
- El hueco es un `RRect` radio 12 alrededor de un botón redondo.
- Velo negro al 55 % (`0x8C000000`): el resto sigue casi igual de visible.
- La tarjeta es un `Card` suelto a 8 px del hueco, sin cola ni flecha; el copy «Aquí…» no apunta a nada.
- Tocar el velo llama `markDone`: un toque instintivo quema la guía para siempre.

## Diseño

1. **Hueco con la forma del ancla.** Sobre el rect MEDIDO: círculo si `|w-h| <= 4`, si no estadio
   (radio = alto/2). El hueco sigue siendo `rect.inflate(6)`. Anillo blanco 3 px + halo `primary` al
   35 % de 6 px. Dos aros que laten (escala 1→1.8, opacidad .9→0, ciclo `JayaloMotion.pulseCycle`),
   solo cuando hay hueco; con `JayaloMotion.reduced` o bajo `FLUTTER_TEST` el ticker se PARA.
2. **Velo** `Color(0xC71A1230)` (violáceo al 78 %, sin negro puro).
3. **Burbuja** blanca radio 20 con cola hacia el hueco (alineada al centro X del ancla, acotada al
   ancho de la burbuja) y chevron blanco entre burbuja y hueco que se mueve 8 px en bucle de 1,1 s
   (parado con reduced/test). Cola y chevron son `Positioned` propios, FUERA del widget con
   `Key('onboardingCard')`. No existen en modo `welcome` ni en la rama centrada (`hole == null`).
   `_kMinCardSpace` sube para que quepan.
4. **«Paso n de N»** con puntos, vía `tourIndex`/`tourLength` opcionales. Solo en `client.plus.v1`
   (1/3), `client.my_requests.v1` (2/3) y `client.others_requests.v1` (3/3). Se acepta el salto 1→3
   cuando la lista no está vacía (un cliente nuevo la tiene vacía).
5. **Copy** «Aquí…» → «Con este botón… / En esta pestaña…» en `client.plus.v1`,
   `client.others_requests.v1`, `client.request_photo.v1`, `chat.quick_replies.v1`,
   `chat.attach.client.v1`, `chat.attach.provider.v1`. Sin subir claves: es un matiz de redacción
   que solo importa junto al diseño nuevo, que de todas formas solo ven quienes no la han visto.
6. **Tocar fuera no quema la guía.** Tap en el velo → `_snoozed` (entra en `_shouldShow`), cierre
   animado, libera el turno, SIN `markDone`. Se limpia cuando `enabled` pasa false→true, al
   «Reiniciar tutorial» y al remontar. «Saltar» y «Entendido» siguen marcando vista.
7. **`tapThrough`** (default false; true solo en `client.plus.v1`). El toque dentro del hueco pasa al
   widget real (el `GestureDetector` del velo no hace hit-test dentro del hueco) y un `Listener`
   translucent sobre el hueco marca la guía como vista y la cierra. `markDone` se dispara ANTES de
   esperar la animación de cierre (hoy se pierde si el widget se desmonta a mitad).

## Tests

Nuevos: tap en velo → `isDone == false` y reaparece al remontar; `tapThrough` → corre el `onPressed`
real Y `isDone == true`; forma del hueco; «Paso 1 de 3». Existentes: deben seguir verdes
(`flutter test` completo), sin `pumpAndSettle` colgado por los bucles.

## Reversión

Un commit aislado por diseño. Volver atrás = `git revert <sha>`.
