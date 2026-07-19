package com.jayalo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Canal de notificaciones con el sonido custom (res/raw/coin.mp3). El
    // sonido es una propiedad del CANAL en Android 8+, por eso se define aquí;
    // el manifest apunta este canal como el default de FCM, así los avisos en
    // segundo plano suenan con él. Los canales persisten una vez creados: basta
    // con haber abierto la app una vez.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Avisos de Jayalo",
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = "Ofertas, mensajes y avisos de tu cuenta"
        val sound = Uri.parse("android.resource://$packageName/${R.raw.coin}")
        val attrs = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        channel.setSound(sound, attrs)
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "jayalo_alerts"
    }
}
