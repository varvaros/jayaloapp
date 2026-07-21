allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// image_cropper 9.1.0 fija compileSdk 33 en su propio build.gradle, pero sus
// dependencias androidx exigen 34+ y el checkReleaseAarMetadata rompe el build
// release. Subir a image_cropper 12.x sería un salto de API; el arreglo mínimo
// es forzar el compileSdk del subproyecto al de la app (workaround estándar de
// Flutter). Quitar cuando se actualice image_cropper.
subprojects {
    // Tiene que correr DESPUÉS del android{} del plugin (que fija el 33); si el
    // proyecto ya se evaluó (evaluationDependsOn(":app") adelanta a :app),
    // afterEvaluate revienta — en ese caso se aplica directo.
    fun forceCompileSdk() {
        val ext = extensions.findByName("android")
        if (ext is com.android.build.gradle.BaseExtension) {
            ext.compileSdkVersion(36)
        }
    }
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
