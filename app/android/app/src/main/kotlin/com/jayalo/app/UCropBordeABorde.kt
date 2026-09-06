package com.jayalo.app

import android.app.Activity
import android.app.Application
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets

/**
 * Mete el recortador de fotos (UCrop, de `image_cropper`) dentro del borde a
 * borde de Android 15+ sin usar ni una sola API obsoleta.
 *
 * ## Por qué existe este fichero
 *
 * Desde `targetSdk 35` Android dibuja TODAS las ventanas de borde a borde: el
 * contenido pasa por DEBAJO de la barra de estado y de la barra de navegación.
 * Las pantallas de Flutter lo resuelven solas (el motor reporta los insets y la
 * app los consume con `SafeArea`), pero UCrop es una Activity de vistas nativas
 * ajena a la app: su `Toolbar` —la que lleva el botón de aceptar el recorte— se
 * quedaba DEBAJO del reloj y la batería (QA PO 2026-07-21).
 *
 * El parche de entonces fue `android:windowOptOutEdgeToEdgeEnforcement` en
 * `Theme.Jayalo.UCrop`: le pedía al sistema el comportamiento clásico. Ese
 * botón de escape **ya no existe**. Android 16 lo IGNORA para las apps que
 * apuntan a `targetSdk 36` (que es justo lo que hace esta, ver
 * `flutter.targetSdkVersion` = 36), así que en cualquier teléfono con Android
 * 16 —el del PO, sin ir más lejos— el recortador salía con la franja de la
 * barra de estado BLANCA y el reloj encima también en blanco: invisible. Y de
 * propina, Play Console marca ese atributo —junto con `android:statusBarColor`—
 * como «APIs o parámetros obsoletos para la pantalla de borde a borde» (aviso
 * sobre la versión 1.0.4+123).
 *
 * ## Qué hace en su lugar
 *
 * Lo que Google pide: en vez de pedirle al sistema que no dibuje bajo las
 * barras, se ACEPTA el borde a borde y se aplican los insets como padding, pero
 * a las vistas correctas en vez de a la ventana entera:
 *
 *   • `toolbar` → padding SUPERIOR. La barra crece hacia arriba y su violeta
 *     pinta también detrás de la barra de estado: se ve como una sola pieza,
 *     no como una franja de color suelto encima.
 *   • `controls_wrapper` (los controles de recorte, abajo) → padding INFERIOR,
 *     con el mismo efecto sobre la barra de navegación.
 *   • Izquierda/derecha → al contenedor raíz, para los teléfonos con muesca en
 *     horizontal.
 *
 * Se hace desde fuera, con un `ActivityLifecycleCallbacks`, porque UCrop se
 * lanza por su nombre de clase desde el plugin: no hay forma de sustituirlo por
 * una subclase propia sin bifurcar `image_cropper`.
 *
 * ## Por qué solo en Android 11+
 *
 * `WindowInsets.Type` es de API 30. Por debajo no hace falta nada: sin borde a
 * borde forzado, el sistema ya coloca la ventana por debajo de la barra de
 * estado y los insets llegan en cero. Poner el listener igual no cambiaría
 * nada, pero exigiría las APIs de insets obsoletas — precisamente lo que este
 * fichero viene a quitar.
 */
object UCropBordeABorde {
    /** UCrop se lanza por nombre; no está en el classpath de compilación. */
    private const val UCROP_ACTIVITY = "com.yalantis.ucrop.UCropActivity"

    /**
     * Se llama desde `MainActivity.onCreate`, que corre de nuevo en CADA
     * recreación (girar el teléfono, cambiar el tema del sistema, volver de un
     * proceso matado). Sin este candado se acumularía un listener por
     * recreación sobre el mismo `Application`.
     */
    private var instalado = false

    fun instalar(app: Application) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (instalado) return
        instalado = true
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            // ⚠️ `onActivityPostCreated` y NO `onActivityCreated`. El segundo se
            // despacha DENTRO de `Activity.onCreate`, y UCrop llama a
            // `super.onCreate()` ANTES de su `setContentView`: ahí el contenido
            // está vacío y todos los `findViewById` devuelven null en silencio.
            // Costó verlo porque el resultado no parecía roto — la toolbar
            // sigue cayendo bastante bien por su cuenta— pero el arreglo no
            // estaba haciendo NADA (medido: `raizHijo=null`).
            // `onActivityPostCreated` corre cuando `onCreate` ya retornó, con
            // el árbol de vistas montado.
            override fun onActivityPostCreated(activity: Activity, savedInstanceState: Bundle?) {
                if (activity.javaClass.name == UCROP_ACTIVITY) aplicar(activity)
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    private fun aplicar(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val raiz = activity.findViewById<View>(android.R.id.content) ?: return
        val toolbar = buscar(activity, "toolbar")
        val controles = buscar(activity, "controls_wrapper")

        // ── Callar a AppCompat antes de escuchar ─────────────────────────────
        // Sin esto los insets llegan RECORTADOS: el andamio de AppCompat
        // (`FitWindowsLinearLayout`, que trae `fitsSystemWindows` en su propio
        // XML) se los come y los convierte en padding de la ventana entera —
        // que es justo lo que dejaba una franja del color de fondo (blanco)
        // bajo los controles oscuros, sobre todo en horizontal.
        //
        // `setDecorFitsSystemWindows(false)` apaga el reparto automático del
        // framework; recorrer los ancestros apaga el de AppCompat. A partir de
        // ahí los insets llegan enteros y se reparten a mano.
        activity.window.setDecorFitsSystemWindows(false)
        var ancestro: View? = raiz
        while (ancestro != null) {
            ancestro.fitsSystemWindows = false
            ancestro = ancestro.parent as? View
        }

        // `controls_wrapper` es un FrameLayout PELADO: el fondo oscuro lo pinta
        // `wrapper_states`, su hijo, y ese tiene el alto FIJO
        // (`ucrop_height_wrapper_states`), así que estirarlo con padding le
        // aplastaría los iconos en vez de crecer. Se pinta entonces el
        // contenedor con ese mismo color, y el padding de abajo queda del color
        // de los controles en vez del fondo blanco de la ventana.
        if (controles != null) {
            val color = activity.resources.getIdentifier(
                "ucrop_color_widget_background",
                "color",
                activity.packageName,
            )
            if (color != 0) {
                controles.setBackgroundColor(activity.resources.getColor(color, activity.theme))
            }
        }

        raiz.setOnApplyWindowInsetsListener { vista, insets ->
            val barras = insets.getInsets(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            toolbar?.setPadding(0, barras.top, 0, 0)
            // Si el usuario pidió `hideBottomControls`, ese contenedor está
            // GONE y no reserva alto: el inset de abajo se lo queda la raíz, o
            // la foto quedaría partida por la barra de navegación.
            val abajo = if (controles != null && controles.visibility == View.VISIBLE) {
                controles.setPadding(0, 0, 0, barras.bottom)
                0
            } else {
                barras.bottom
            }
            // Los laterales van a la raíz: solo aparecen con muesca en
            // horizontal, y ahí da igual qué vista los reciba.
            vista.setPadding(barras.left, 0, barras.right, abajo)
            // Se devuelven SIN consumir: UCrop no mira los insets, pero
            // consumirlos rompería a cualquier vista suya que sí lo haga.
            insets
        }
        raiz.requestApplyInsets()
    }

    /**
     * `getIdentifier` y no `R.id.toolbar`: con el R no transitivo de AGP 8 los
     * ids de UCrop viven en `com.yalantis.ucrop.R`, que es una dependencia
     * `implementation` del plugin y por tanto NO está en el classpath de
     * compilación de la app. En el APK ya empaquetado los recursos sí están
     * fusionados bajo el paquete de la app (verificado con `aapt2 dump
     * resources`: `id/toolbar` = 0x7f0900f5), así que buscarlos por nombre en
     * tiempo de ejecución funciona — y R8 no renombra recursos.
     */
    @Suppress("DiscouragedApi")
    private fun buscar(activity: Activity, nombre: String): View? {
        val id = activity.resources.getIdentifier(nombre, "id", activity.packageName)
        if (id == 0) return null
        // Se busca dentro del contenido y no desde la Activity, para no
        // tropezar con el andamio de AppCompat.
        val raiz = activity.findViewById<ViewGroup>(android.R.id.content) ?: return null
        return raiz.findViewById(id)
    }
}
