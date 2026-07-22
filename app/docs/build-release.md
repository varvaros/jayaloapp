# Build de release (firma + R8 + ofuscacion)

Endurecimiento del APK/AAB de produccion. Cubre firma de subida, R8/shrink y
ofuscacion de Dart. **Play Integrity queda diferido a pre-lanzamiento (ADR-0032)**
— no esta implementado a proposito.

## 1. Keystore de subida (una sola vez)

El release ya **no** debe firmarse con las debug keys. Genera un keystore de
subida y guardalo FUERA del repo:

```powershell
keytool -genkey -v -keystore C:\Users\ac\keys\jayalo-upload.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Luego copia la plantilla y rellena los valores reales:

```powershell
Copy-Item android/key.properties.example android/key.properties
# editar android/key.properties con la ruta del .jks y las passwords
```

`android/key.properties` y `*.jks` estan **gitignoreados** — nunca se commitean.
Si `key.properties` no existe, el build de release cae a debug keys (sirve para
`flutter run --release` en dev, pero NO es publicable).

### ⚠️ Registrar el SHA-1/SHA-256 del keystore de release

Google Sign-In y las features de Firebase gateadas por huella **dependen del
SHA-1 de la llave de firma**. El keystore de subida tiene un SHA-1 DISTINTO al
de debug, asi que hay que registrarlo o Google Sign-In se rompe en produccion:

1. Obten las huellas:
   ```powershell
   keytool -list -v -keystore C:\Users\ac\keys\jayalo-upload.jks -alias upload
   ```
2. Agrega SHA-1 y SHA-256 en **Firebase Console → Project settings → tu app
   Android** y en **Google Cloud Console → Credenciales → OAuth client Android**.
3. Si publicas por Play Store con **Play App Signing**, agrega tambien el SHA-1
   de la llave de firma de la app que muestra Play Console (Google re-firma el
   AAB con su propia llave).

## 2. Build ofuscado

Usa el script (aplica R8/shrink via build.gradle.kts + ofuscacion de Dart):

```powershell
./scripts/build-release-apk.ps1            # APK
./scripts/build-release-apk.ps1 -Bundle    # AAB para Play Store
```

Equivale a:

```powershell
flutter build apk --release --obfuscate --split-debug-info=symbols/<version>
```

## 3. Simbolos de des-ofuscacion (NO perder)

`--split-debug-info` extrae los simbolos Dart a `symbols/<version>/`. **Archiva
esa carpeta por cada release publicado**: sin ella los stack traces ofuscados
del error-tracking (capa #12) no se pueden leer. Estan fuera de git.

Para des-ofuscar un stack trace guardado:

```powershell
flutter symbolize -i <crash.txt> -d symbols/<version>/app.android-arm64.symbols
```

## Que NO rompe R8 (verificado)

- **Supabase** (`supabase_flutter`): Dart puro, R8 no procesa Dart. Cero reglas.
- **Firebase / FCM**: los AAR traen sus consumer rules; el canal nativo de
  `MainActivity.kt` lo referencia el manifest (R8 lo conserva). Keep extra en
  `proguard-rules.pro` por defensa en profundidad.
- **Riesgo real cubierto**: `com.google.android.play.core.**` (deferred
  components del engine) → `-dontwarn` en `proguard-rules.pro`.
