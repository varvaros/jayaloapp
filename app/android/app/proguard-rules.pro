# ---------------------------------------------------------------------------
# Reglas R8/ProGuard para el build de release de Jayalo.
#
# R8 SOLO procesa la capa Kotlin/Java del APK. El código Dart (toda la lógica
# de negocio) va compilado a nativo en libapp.so y NO lo toca R8; para ofuscar
# Dart se usa `flutter build --obfuscate` (ver scripts/build-release-apk.ps1).
# Por eso Supabase (supabase_flutter = Dart puro sobre HTTP/JSON/WebSocket) no
# necesita NINGUNA regla aquí: R8 nunca ve ese código.
# ---------------------------------------------------------------------------

# --- Flutter deferred components / Play Core --------------------------------
# El engine de Flutter referencia estas clases para split installs, pero la app
# NO empaqueta Play Core. Sin este -dontwarn, R8 en modo full aborta el build
# con "Missing class com.google.android.play.core...". Este es el punto de
# quiebre #1 al activar R8 en un proyecto Flutter.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# --- integration_test -------------------------------------------------------
# Está en `dependencies` (no dev_dependencies) a propósito: el
# GeneratedPluginRegistrant lo referencia y sin él `flutter build --release`
# no compila (ver comentario en pubspec.yaml). Sus clases de test no se usan en
# producción; silenciamos la infra de test que arrastra para que R8 no falle.
-dontwarn androidx.test.**
-dontwarn org.junit.**
-dontwarn org.hamcrest.**

# --- Firebase Cloud Messaging -----------------------------------------------
# Los AAR de Firebase ya traen sus consumer ProGuard rules (se aplican solas),
# así que FCM funciona con R8 sin esto. Se deja como defensa en profundidad
# sobre los componentes de mensajería.
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.**

# --- image_cropper (UCrop) --------------------------------------------------
# La UCropActivity se declara en el AndroidManifest (R8 conserva las clases
# referenciadas por el manifest), pero mantenemos el paquete completo por las
# clases auxiliares que UCrop instancia por reflexión.
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# --- Anotaciones @Keep ------------------------------------------------------
-keep,allowobfuscation @interface androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
