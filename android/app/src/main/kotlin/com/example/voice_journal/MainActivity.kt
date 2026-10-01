package com.example.voice_journal

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.decorView.isForceDarkAllowed = false
        }
    }

    // Kênh `voice_journal/audio` (lib/services/device_context.dart): nguồn micro
    // không qua xử lý của hệ điều hành (WP2 mục 4.2) và thông tin thiết bị cho
    // metadata mục 5.1.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voice_journal/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "supportsUnprocessed" -> result.success(supportsUnprocessed())
                    "deviceInfo" -> result.success(
                        mapOf(
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "os_version" to "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // MediaRecorder.AudioSource.UNPROCESSED có từ API 24, nhưng chỉ dùng được
    // khi máy báo hỗ trợ qua PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED.
    private fun supportsUnprocessed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audio.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
    }
}
