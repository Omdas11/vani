package com.opentune.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureAudioChannel()
        super.onCreate(savedInstanceState)
    }

    /**
     * v1.6.4: "vani/share_log" channel for Developer options → "Share log
     * file". Writes go to the app's temp dir (Dart side); here we expose
     * the file through a FileProvider URI on an ACTION_SEND chooser so
     * the user can send the diagnostics text anywhere.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vani/share_log"
        ).setMethodCallHandler { call, result ->
            if (call.method == "shareFile") {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("ARG", "missing path", null)
                    return@setMethodCallHandler
                }
                try {
                    val uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        File(path)
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(
                        Intent.createChooser(intent, "Share log file"))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
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
