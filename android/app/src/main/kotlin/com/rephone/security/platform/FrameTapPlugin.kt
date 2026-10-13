package com.rephone.security.platform

import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoTrack

/**
 * `rephone_frame_tap` MethodChannel 的宿主（Android）。
 *
 * 通过 flutter_webrtc 暴露给 embedder 的 `FlutterWebRTCPlugin.getLocalTrack()`
 * 拿到本地 VideoTrack，再交给 [FrameTap] 常驻取样。
 */
class FrameTapPlugin(private val engine: FlutterEngine) {

    private var tap: FrameTap? = null

    fun register() {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attach" -> {
                        val trackId = call.argument<String>("trackId")
                        val width = call.argument<Int>("width") ?: 300
                        val height = call.argument<Int>("height") ?: 300
                        val videoTrack = findVideoTrack(trackId)
                        if (videoTrack == null) {
                            result.error("NO_TRACK", "video track not found: $trackId", null)
                            return@setMethodCallHandler
                        }
                        // 先摘旧 sink 再挂新的：restartVideo() 会换 track，
                        // 漏掉 detach 会让旧 VideoTrack 一直强引用 FrameTap。
                        tap?.detach()
                        val created = FrameTap(width, height)
                        created.attach(videoTrack)
                        tap = created
                        result.success(true)
                    }

                    "detach" -> {
                        tap?.detach()
                        tap = null
                        result.success(true)
                    }

                    "latest" -> result.success(tap?.take())

                    "stats" -> result.success(
                        tap?.stats() ?: mapOf<String, Any?>("attached" to false)
                    )

                    else -> result.notImplemented()
                }
            }
    }

    private fun findVideoTrack(trackId: String?): VideoTrack? {
        if (trackId.isNullOrEmpty()) return null
        // sharedSingleton 由 FlutterWebRTCPlugin 构造时赋值，避免依赖
        // FlutterEngine.plugins 的泛型查找。
        val plugin = FlutterWebRTCPlugin.sharedSingleton ?: run {
            Log.w(TAG, "flutter_webrtc plugin not registered yet")
            return null
        }
        val track = plugin.getLocalTrack(trackId)?.track ?: return null
        return track as? VideoTrack
    }

    companion object {
        const val CHANNEL = "rephone_frame_tap"
        private const val TAG = "FrameTapPlugin"
    }
}
