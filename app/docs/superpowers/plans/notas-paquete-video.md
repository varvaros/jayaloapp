# Task 12 — paquete de compresión de video: decisión

Fecha: 2026-08-21. Rama `feat/video-portafolio-app`.

## Ganador: `video_compress: 3.1.4`

Compila. Verificado con `flutter build apk --debug` real (no solo `pub get`),
Gradle terminó con:

```
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

Se probó SOLO — sin `video_player` (eso es de otra tarea) — para no confundir
qué rompe qué si algo fallaba.

No se llegó a probar `light_compressor` porque el primer candidato (el más
reciente de los dos, y el que evita una dependencia extra para el póster
gracias a `getFileThumbnail`) compiló. El brief pedía probar el segundo solo
si el primero fallaba.

## Qué hubo que tocar en Gradle

**Nada del paquete en sí.** `video_compress` no rompió el build. Lo que sí
hizo falta para poder ejecutar `flutter build apk --debug` en esta máquina —
y que es enteramente ajeno al paquete, ya existía antes de tocar
`pubspec.yaml` — fueron dos rodeos de infraestructura local:

1. **Gate de firma de release evaluado también en el build debug**
   (`android/app/build.gradle.kts` línea ~102): el bloque `buildTypes { release
   { ... } }` se evalúa en configuración aunque la tarea sea `assembleDebug`, y
   sin `android/key.properties` lanza `GradleException`. Solución: el propio
   proyecto ya documenta la salida — `-PallowDebugSigning=true`. No se tocó el
   `build.gradle.kts`.
2. **`android/app/google-services.json` ausente** (gitignoreado, no viene en
   el repo): sin él, `processDebugGoogleServices` falla. Para obtener un
   veredicto real de Gradle se generó un `google-services.json` FALSO
   (project_id/api_key dummy, mismo `package_name` `com.jayalo.app`) solo para
   pasar la validación de forma del plugin — **no** se copió el real de
   `jayalo-app-playbilling` (repo prohibido para esta tarea). Ese archivo dummy
   se borró después de confirmar el build; no quedó en el árbol de trabajo ni
   se commiteó (está gitignoreado de todas formas).

Ninguno de los dos rodeos es específico de `video_compress` — cualquier build
de este proyecto en esta máquina los pisa. Quedan fuera del alcance de esta
tarea arreglarlos de raíz.

## `WARNING` de Kotlin Gradle Plugin (no bloqueante)

El build imprimió:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): app_badge_plus, package_info_plus, smart_auth, video_compress
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Es un warning de Flutter sobre una migración futura a "Built-in Kotlin", no
un error. `video_compress` está en la lista junto con tres paquetes que YA
estaban en el proyecto antes de esta tarea (`app_badge_plus`,
`package_info_plus`, `smart_auth`), así que no es una señal específica contra
`video_compress`. Anotado como riesgo latente, no como bloqueo.

## Verificación post-cambio

- `flutter analyze` → limpio, igual que el baseline.
- `flutter test` → **1409** pasan, igual que el baseline.
- `pubspec.yaml`: versión fijada `video_compress: 3.1.4` (no rango abierto).

## Huecos declarados

- No se ejecutó la app en un emulador/dispositivo real ni se llamó a ningún
  método de `video_compress` — esta tarea es solo "compila", la implementación
  es la Task 13.
- No se probó `light_compressor` porque no hizo falta (el primero compiló).
  Si en la Task 13 `video_compress` da problemas en tiempo de ejecución
  (bugs conocidos de esa librería, no solo de compilación), `light_compressor`
  + `video_thumbnail` sigue siendo el plan B, sin probar.
- El warning de KGP no se investigó a fondo (no bloquea el build de hoy); si
  Flutter fuerza esa migración en una versión futura, `video_compress` podría
  necesitar reemplazo entonces — riesgo latente, no un hueco de esta tarea.
