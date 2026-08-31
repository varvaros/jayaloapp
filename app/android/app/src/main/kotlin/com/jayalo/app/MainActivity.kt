package com.jayalo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // El sello de build (rama y commit) lo hornea Gradle en el manifest; aqui
    // solo se lee y se pasa a Dart. Se lee del manifest y no de un fichero
    // generado porque el manifest ya viaja DENTRO del APK: lo que responde este
    // canal es, literalmente, de donde salio el binario que esta corriendo.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUILD_STAMP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "leer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(leerSello())
            }
    }

    private fun leerSello(): Map<String, String> = try {
        val meta = packageManager
            .getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData
        mapOf(
            "rama" to leerMeta(meta, "com.jayalo.app.BUILD_RAMA"),
            "sha" to leerMeta(meta, "com.jayalo.app.BUILD_SHA"),
            "sucio" to leerMeta(meta, "com.jayalo.app.BUILD_SUCIO"),
        )
    } catch (e: Exception) {
        // Sin sello se muestra "desconocido": es informacion, nunca un motivo
        // para que la pantalla de Ajustes reviente.
        emptyMap()
    }

    // El sonido de una notificación en segundo plano es propiedad del CANAL
    // (Android 8+), no del push, por eso se define aquí. Hay DOS canales para
    // que se distingan de oído y el usuario pueda silenciar los chats sin
    // perder los avisos de dinero (decisión PO 2026-07-28):
    //
    //   • ALERTS_CHANNEL_ID → ofertas, billetera y avisos de cuenta (campana).
    //     Es el default del manifest, así que recibe todo lo que send-push no
    //     marque explícitamente.
    //   • CHAT_CHANNEL_ID   → mensajes de chat (pop de burbuja). send-push lo
    //     pide por `android.notification.channel_id` en los `message_new`.
    //
    // ⚠️ El sonido de un canal es INMUTABLE una vez creado: para cambiarlo hay
    // que estrenar un CHANNEL_ID nuevo (de ahí los sufijos) y —esto es lo que se
    // olvidó en `f16199d` y dejó el sonido custom MUDO desde el 2026-07-22—
    // actualizar el `default_notification_channel_id` del manifest para que
    // coincida. Los canales viejos quedan huérfanos y son benignos.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        ensureChannel(
            manager,
            ALERTS_CHANNEL_ID,
            "Avisos de Jayalo",
            "Ofertas, billetera y avisos de tu cuenta",
            R.raw.notif_bell,
        )
        ensureChannel(
            manager,
            CHAT_CHANNEL_ID,
            "Mensajes",
            "Mensajes nuevos de tus conversaciones",
            R.raw.msg_bubble,
        )
    }

    private fun ensureChannel(
        manager: NotificationManager,
        id: String,
        name: String,
        description: String,
        soundRes: Int,
    ) {
        // Si ya existe se respeta: recrearlo no cambia el sonido de todos modos,
        // y el usuario pudo haberlo ajustado a mano en los Ajustes del sistema.
        if (manager.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
        channel.description = description
        val attrs = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        channel.setSound(Uri.parse("android.resource://$packageName/$soundRes"), attrs)
        manager.createNotificationChannel(channel)
    }

    // ⚠️ `aapt` TIPA el valor de un <meta-data>: "1" se empaqueta como ENTERO,
    // no como cadena, y ahi `getString` devuelve null. Lo destapo revisando el
    // manifest del APK ya construido — los tests de Dart no lo pueden ver, porque
    // solo pasa al empaquetar. Se lee sin asumir tipo, o el aviso de «cambios sin
    // commitear» —el dato mas importante del sello— muere en silencio.
    private fun leerMeta(meta: android.os.Bundle?, clave: String): String =
        meta?.get(clave)?.toString() ?: ""

    companion object {
        const val ALERTS_CHANNEL_ID = "jayalo_alerts_v2"
        const val CHAT_CHANNEL_ID = "jayalo_chat_v1"
        const val BUILD_STAMP_CHANNEL = "com.jayalo.app/sello_build"
    }
}
