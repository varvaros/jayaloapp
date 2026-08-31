import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciales de firma del release, cargadas desde android/key.properties
// (gitignoreado — NUNCA se commitea). Si el archivo no existe (una máquina de
// dev sin el keystore de subida), el build de release cae a las debug keys para
// que `flutter run --release` siga funcionando sin romperse. La firma real solo
// aplica cuando key.properties está presente (CI de publicación / máquina del PO).
// Ver docs/build-release.md para generar el keystore y el key.properties.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Sin key.properties el release caía a las DEBUG KEYS EN SILENCIO. Play rechaza
// ese artefacto en la subida, así que no es explotable — pero
// `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` es `protectionLevel="signature"`, y
// un binario "de release" firmado con la clave de debug (que es pública y la
// misma en todas las máquinas de dev) deja de estar protegido por la firma.
// Ahora hay que PEDIRLO: `-PallowDebugSigning=true` para `flutter run --release`
// en una máquina sin keystore. Sin el flag, el build falla en voz alta.
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?) == "true"

// ── SELLO DE BUILD ────────────────────────────────────────────────────────────
// Rama y commit de los que salio ESTE binario, horneados dentro. Nace del APK
// 1.0.4+87 (2026-08-30): se compilo desde una rama hermana y le quito al
// telefono 26 commits de trabajo. Nadie podia saberlo mirando el aparato — solo
// haciendo arqueologia de git — y por eso tardo en verse.
//
// Va aqui, en Gradle, y NO en un `--dart-define`: un dart-define hay que
// acordarse de pasarlo, y lo que falla es justamente acordarse. Gradle corre
// SIEMPRE que se compila, asi que el sello no se puede olvidar.
//
// Degrada sin romper: fuera de un repo git, o sin `git` en el PATH, queda
// "desconocido" y el build sigue. Un sello es informacion, no un guardia.
fun gitOut(vararg args: String): String = try {
    val p = ProcessBuilder(listOf("git") + args)
        .directory(rootProject.projectDir)
        .redirectErrorStream(true)
        .start()
    val out = p.inputStream.bufferedReader().readText().trim()
    if (p.waitFor() == 0 && out.isNotEmpty()) out else ""
} catch (e: Exception) {
    ""
}

val gitRama = gitOut("rev-parse", "--abbrev-ref", "HEAD").ifEmpty { "desconocida" }
val gitSha = gitOut("rev-parse", "--short", "HEAD").ifEmpty { "desconocido" }
// `--porcelain` vacio = arbol limpio. Si hay algo sin commitear el binario NO
// corresponde a ningun commit, y eso es lo mas importante que puede decir el
// sello: es la situacion en la que el codigo que corre no esta en ninguna parte.
val gitSucio = if (gitOut("status", "--porcelain").isNotEmpty()) "1" else "0"


android {
    namespace = "com.jayalo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requisito de flutter_local_notifications (notificación de chat con
        // acción "Responder"): sin esto el build de release falla con
        // "requires core library desugaring to be enabled".
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // applicationId PERMANENTE: atado a los OAuth clients Android de Google
        // Cloud (proyecto jayalo-501005). No cambiar.
        //
        // Estado verificado el 2026-07-30 en Google Cloud Console:
        //   - "Jayalo Android (debug)"   → SHA-1 del debug.keystore local.
        //   - "Jayalo Android (release)" → SHA-1 86:0A:76:41:30:B4:FB:01:9F:5C:
        //     01:9C:4C:B3:19:32:E4:A6:86:A3, que coincide con el keystore de
        //     subida (jayalo-upload.jks, alias `upload`).
        //
        // ⚠️ FALTA EL TERCERO: con Play App Signing, Google RE-FIRMA el AAB con
        // un certificado propio cuyo SHA-1 es distinto de los dos de arriba. Ese
        // hay que registrarlo como un OAuth client Android más, o Google Sign-In
        // fallará con ApiException 10 para TODOS los usuarios que instalen desde
        // Play — y como el login por Google es el único camino de entrada, la app
        // queda inutilizable. Se lee en Play Console → Prueba y lanzamiento →
        // Integridad de la app → Firma de apps de Play, y solo existe DESPUÉS de
        // crear la ficha y subir el primer AAB.
        applicationId = "com.jayalo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Llegan al manifest como <meta-data> y de ahi a Ajustes → «Esta
        // version». El versionName se deja LIMPIO a proposito: es lo que ve el
        // usuario en Play y no debe llevar sufijos de rama.
        manifestPlaceholders["buildRama"] = gitRama
        manifestPlaceholders["buildSha"] = gitSha
        manifestPlaceholders["buildSucio"] = gitSucio
    }

    signingConfigs {
        // Solo se declara si hay key.properties; si no, no existe la config
        // "release" y el buildType cae a debug (abajo).
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // ⚠️ El keystore de release tiene un SHA-1 DISTINTO al de debug:
            // hay que registrarlo en Firebase + Google Cloud Console o
            // Google Sign-In deja de funcionar en el APK firmado de producción.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else if (allowDebugSigning) {
                logger.warn(
                    "⚠️  Build de RELEASE firmado con las DEBUG KEYS (-PallowDebugSigning=true). " +
                        "Este artefacto NO es publicable: Play lo rechaza y los permisos " +
                        "protectionLevel=\"signature\" quedan sin protección."
                )
                signingConfigs.getByName("debug")
            } else {
                throw GradleException(
                    "No existe android/key.properties: el build de release NO puede firmarse. " +
                        "Antes caía a las debug keys en silencio. Crea el key.properties " +
                        "(ver docs/build-release.md) o, si solo quieres correr en local, " +
                        "reconstruye con -PallowDebugSigning=true."
                )
            }

            // R8 (ofusca + optimiza la capa Kotlin/Java) + shrink de recursos.
            // No toca el código Dart: eso se ofusca con `flutter build
            // --obfuscate` (ver scripts/build-release-apk.ps1). Las reglas de
            // keep están en proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backport de APIs de Java 8+ (java.time, etc.) para minSdk bajos. Lo exige
    // flutter_local_notifications; va de la mano con isCoreLibraryDesugaringEnabled.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
