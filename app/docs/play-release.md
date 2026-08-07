# Publicar en Google Play — runbook

Complementa `docs/build-release.md`, que cubre la firma y el build. Esto es el
orden en que hay que hacer las cosas y las trampas que ya nos mordieron.

Estado al 2026-08-06: **no existe cuenta de Play Console**. Todo lo demás de
esta lista está listo o es ejecutable.

## Datos de la app (no cambiar a la ligera)

| Dato | Valor |
|---|---|
| `applicationId` | `com.jayalo.app` — **PERMANENTE**: está atado a los OAuth clients Android |
| Versión en `pubspec.yaml` | `1.0.2+9` (el `+9` es el `versionCode`) |
| Keystore de subida | `C:\Users\ac\keys\jayalo-upload.jks`, alias `upload`, fuera del repo |
| SHA-1 del keystore | `86:0A:76:41:30:B4:FB:01:9F:5C:01:9C:4C:B3:19:32:E4:A6:86:A3` |
| Proyecto de los OAuth clients | Google Cloud **`jayalo-501005`** (NO el de Firebase) |

## 1. Crear la cuenta de Play Console — SOLO EL PO

`play.google.com/console`, pago único de 25 USD. **No es la misma cuenta que
Google Cloud Console**: tener `jayalo-501005` no habilita publicar.

⚠️ **La decisión que marca el calendario**: si la cuenta se registra como
**persona física**, Google exige una **prueba cerrada con 12 testers durante 14
días continuos** antes de dejar solicitar acceso a producción. Como
**organización** (con su documentación) no aplica. Son dos semanas de camino
crítico: conviene crearla aunque el resto no esté listo.

## 2. Versionado

`versionCode` debe crecer en cada subida y **nunca puede bajar**. Sale de
`pubspec.yaml` (`1.0.2+9` → versionCode 9). Reglas:

- Una subida a Play **quema** ese número para siempre, aunque se descarte.
- Los builds de device hechos a mano con `--build-number` (llegamos a 12 durante
  el smoke del 2026-08-06) **no cuentan**: nunca tocaron Play. Pero si el primer
  AAB va con un número menor que el del APK instalado en un teléfono de pruebas,
  ese teléfono no podrá actualizarse desde Play sin desinstalar.
- Subir el `+N` del `pubspec` es parte de preparar el release, no algo que se
  improvise en el `flutter build`.

## 3. Construir el AAB

```powershell
./scripts/build-release-apk.ps1 -Bundle
```

Sale en `build/app/outputs/bundle/release/app-release.aab` (~59 MB) con R8,
shrink y ofuscación de Dart. **Verificado el 2026-08-06**: el bundle está
firmado por `CN=Jayalo` (`jarsigner -verify` → `jar verified`), no con debug
keys.

**Archivar `symbols/<version>/` de CADA versión publicada.** Sin esa carpeta los
stack traces ofuscados de esa versión son ilegibles. Está fuera de git.

## 4. La trampa del login de Google con Play App Signing

Ya nos mordió una vez con el APK de release (`ApiException: 10`,
DEVELOPER_ERROR). Con Play App Signing **Google re-firma el AAB con SU propia
llave**, así que la app en producción tiene un **SHA-1 distinto** al del
keystore de subida. Si no se registra, el login con Google falla **solo para
quien instale desde la tienda** — no se reproduce con el APK local.

Después de subir el primer AAB:

1. Play Console → Configuración → Integridad de la app → copiar el **SHA-1 del
   certificado de firma de la app** (el de Google, no el de subida).
2. Google Cloud Console → proyecto **`jayalo-501005`** → Credenciales → crear
   **otro** OAuth client Android con `com.jayalo.app` + ese SHA-1. Un client
   Android admite UNA sola huella, así que debug, subida y Play conviven como
   tres clients del mismo paquete.
3. Añadirlo también en Firebase (`jayalo-350bc`) para las features gateadas por
   huella.
4. La propagación tarda de 5 minutos a horas. Reintentar el login después.

## 5. Ficha de la tienda y formularios

- **Seguridad de los datos**: declarar la URL de eliminación de cuenta, que ya
  existe y es pública: `https://jayalo.com/eliminar-cuenta`.
- Política de privacidad: `https://jayalo.com/privacidad`.
- Clasificación de contenido, público objetivo, declaración de anuncios.
- Ficha: ícono, gráfico destacado, capturas, descripción corta y larga.

## 6. Antes de abrir al público

Ver `docs/launch-checklist.md` del repo web. Lo que sigue abierto ahí no lo
bloquea Play, pero sí bloquea cobrar de verdad.

## Cosas que parecen bugs y no lo son

- **`integration_test` está en `dependencies`, no en `dev_dependencies`**, a
  propósito y documentado en `pubspec.yaml`: como dev_dependency, el
  `GeneratedPluginRegistrant` lo sigue referenciando y `flutter build apk
  --release` no compila. En producción es inerte.
- El AAB pesa ~59 MB, más que el APK: Play lo reparte por dispositivo, el
  usuario descarga bastante menos.
