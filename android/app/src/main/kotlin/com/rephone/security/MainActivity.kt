package com.rephone.security

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "camera_wakelock"
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    try {
                        enableWakeLock()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", "Failed to enable wakelock: ${e.message}", null)
                    }
                }
                "disable" -> {
                    try {
                        disableWakeLock()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", "Failed to disable wakelock: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun enableWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RePhoneCamera:WakeLock"
            )
        }
        if (wakeLock?.isHeld != true) {
            wakeLock?.acquire()
        }
    }

    private fun disableWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
    }

    override fun onDestroy() {
        disableWakeLock()
        super.onDestroy()
    }
}
