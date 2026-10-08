package com.opentune.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureAudioChannel()
        super.onCreate(savedInstanceState)
    }

    /**
     * audio_service creates its notification channel with IMPORTANCE_LOW.
     * On some OEM skins (notably near-stock Android 12 builds like the
     * Moto G40 Fusion) a LOW-importance media channel is degraded in the
     * shade — the entry renders without transport buttons. Pre-create the
     * channel at IMPORTANCE_DEFAULT (audio_service only creates it when
     * absent, so it then uses ours as-is), and delete the stale LOW
     * channel left by earlier installs so it is recreated properly.
     * Channel importance is otherwise immutable once created.
     */
    private fun ensureAudioChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val id = "com.opentune.app.channel.audio"
        val existing = nm.getNotificationChannel(id)
        if (existing != null &&
            existing.importance == NotificationManager.IMPORTANCE_LOW
        ) {
            nm.deleteNotificationChannel(id)
        }
        if (nm.getNotificationChannel(id) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    id,
                    "Audio playback",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
    }
}
