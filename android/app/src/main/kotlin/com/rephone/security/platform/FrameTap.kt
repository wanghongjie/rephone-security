package com.rephone.security.platform

import android.os.SystemClock
import android.util.Log
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoTrack

/**
 * 常驻帧取样器：往 [VideoTrack] 上挂一个长期存在的 [VideoSink]，在 `onFrame` 里
 * 把当前帧降采样成模型输入尺寸的 RGB 缩略图并缓存，Dart 侧按需取「最新一帧」。
 *
 * ### 为什么不用 `MediaStreamTrack.captureFrame()`
 * flutter_webrtc 的 `FrameCapturer` 每次调用都执行 `track.addSink(this)`，
 * 只有收到第一帧才 `removeSink`；轨道无帧（被 monitor 的 WebRTC 占用 / 后台 /
 * 已停止）时既不注销也不回调，10s 一次的检测会持续堆积 sink，且 Android 旋转
 * 分支还会泄漏两张全分辨率 Bitmap（~7MB/次）。本类只 add/remove 一次，全程不碰
 * Bitmap / 文件 / MethodChannel.Result，从根上消除该泄漏。
 *
 * ### 三条使用约束（违反任何一条都会引入新的泄漏）
 * 1. `VideoFrame.Buffer.toI420()` 的结果必须在 finally 里 `release()`；
 * 2. [detach] 必须在页面销毁 / 释放资源 / **重建流之前** 调用，否则 VideoTrack
 *    会一直强引用本对象；
 * 3. VideoTrack 被更换（`Signaling.restartVideo()`）后必须重新 [attach]，
 *    否则拿不到新轨道的帧（表现为检测静默失效，不报错）。
 */
class FrameTap(
    private val outWidth: Int,
    private val outHeight: Int,
    /** 取样节流间隔。相机通常 30fps，没必要每帧都做 I420 转换。 */
    private val minIntervalMs: Long = 500L,
    /** 相邻两次取样的平均灰度差阈值（0-255），低于此值认为画面没变化。 */
    private val changeThreshold: Float = 3.0f,
) : VideoSink {

    private val lock = Any()

    @Volatile
    private var track: VideoTrack? = null

    @Volatile
    private var latestRgb: ByteArray? = null

    @Volatile
    private var latestWidth = 0

    @Volatile
    private var latestHeight = 0

    @Volatile
    private var hasUpdate = false

    @Volatile
    private var lastProcessMs = 0L

    /** 上一次取样（而非上一次入库）的灰度，用作下一帧的比较基线。 */
    @Volatile
    private var prevGray: ByteArray? = null

    /** 仅用于验证：收到的总帧数 / 实际更新缓存的次数。 */
    @Volatile
    private var frameCount = 0L

    @Volatile
    private var updateCount = 0L

    fun attach(videoTrack: VideoTrack) {
        detach()
        synchronized(lock) {
            latestRgb = null
            prevGray = null
            hasUpdate = false
        }
        track = videoTrack
        videoTrack.addSink(this)
        Log.i(TAG, "attached: track=${videoTrack.id()} out=${outWidth}x${outHeight}")
    }

    fun detach() {
        val current = track
        track = null
        if (current != null) {
            try {
                current.removeSink(this)
            } catch (t: Throwable) {
                Log.w(TAG, "removeSink failed", t)
            }
        }
        synchronized(lock) {
            latestRgb = null
            prevGray = null
            hasUpdate = false
        }
        Log.i(TAG, "detached")
    }

    /**
     * 取最新一帧。`hasUpdate == false` 时返回 null —— 表示画面没有变化，
     * Dart 侧应直接跳过本次推理（这正是「有变化才检测」的落点）。
     */
    fun take(): Map<String, Any?>? {
        if (!hasUpdate) return null
        synchronized(lock) {
            val rgb = latestRgb ?: return null
            hasUpdate = false
            return mapOf(
                "width" to latestWidth,
                "height" to latestHeight,
                "rgb" to rgb,
            )
        }
    }

    fun stats(): Map<String, Any?> = mapOf(
        "attached" to (track != null),
        "frames" to frameCount,
        "updates" to updateCount,
    )

    override fun onFrame(frame: VideoFrame) {
        frameCount++

        // onFrame 回调在 WebRTC 的视频线程上，这里必须快速返回，只做节流。
        val now = SystemClock.elapsedRealtime()
        if (now - lastProcessMs < minIntervalMs) return
        lastProcessMs = now

        // 注意：不要 frame.retain()。我们只在回调内使用帧，用完即弃；
        // retain 之后忘记 release 就是新的泄漏。
        // toI420() 在本版本 SDK 中返回可空类型；为 null 直接放弃本次取样。
        val i420 = frame.buffer.toI420() ?: return
        try {
            val rgb = sampleRgb(i420, frame.rotation)
            val gray = toGray(rgb)
            val baseline = prevGray
            // 基线每次取样都更新：这样缓慢变化（有人走近）会累积到超过阈值，
            // 不会因为「每帧变化都很小」而永远检测不到。
            prevGray = gray
            val diff = if (baseline == null) Float.MAX_VALUE else meanAbsDiff(baseline, gray)
            if (baseline == null || diff >= changeThreshold) {
                synchronized(lock) {
                    latestRgb = rgb
                    latestWidth = if (frame.rotation == 90 || frame.rotation == 270) outHeight else outWidth
                    latestHeight = if (frame.rotation == 90 || frame.rotation == 270) outWidth else outHeight
                    hasUpdate = true
                    updateCount++
                }
            }
        } catch (t: Throwable) {
            // onFrame 抛异常会让 WebRTC 后续帧投递异常，务必吞掉。
            Log.w(TAG, "onFrame sampling failed", t)
        } finally {
            // 关键：toI420() 返回的是新 buffer（flutter_webrtc 0.8.6 修的就是漏了这行）
            i420.release()
        }
    }

    /**
     * 把 I420 帧按 [outWidth]x[outHeight] 采样成 RGB 三通道。
     * 全手工采样，不依赖 YuvHelper / YuvImage / Bitmap —— 后者正是旧方案的泄漏源。
     */
    private fun sampleRgb(i420: VideoFrame.I420Buffer, rotation: Int): ByteArray {
        val srcW = i420.width
        val srcH = i420.height
        if (srcW <= 0 || srcH <= 0) return ByteArray(0)

        val swap = rotation == 90 || rotation == 270
        val dstW = if (swap) outHeight else outWidth
        val dstH = if (swap) outWidth else outHeight
        val out = ByteArray(dstW * dstH * 3)

        val y = i420.dataY
        val u = i420.dataU
        val v = i420.dataV
        val sy = i420.strideY
        val su = i420.strideU
        val sv = i420.strideV

        var o = 0
        for (dy in 0 until dstH) {
            val ny = (dy + 0.5f) / dstH
            for (dx in 0 until dstW) {
                val nx = (dx + 0.5f) / dstW
                // rotation = 显示前需要顺时针旋转的角度，这里反推源坐标。
                val (sxN, syN) = when (rotation) {
                    90 -> ny to (1f - nx)
                    180 -> (1f - nx) to (1f - ny)
                    270 -> (1f - ny) to nx
                    else -> nx to ny
                }
                val sx = clampIndex((sxN * srcW).toInt(), srcW - 1)
                val syi = clampIndex((syN * srcH).toInt(), srcH - 1)

                val yv = y.get(syi * sy + sx).toInt() and 0xFF
                val cu = u.get((syi / 2) * su + (sx / 2)).toInt() and 0xFF
                val cv = v.get((syi / 2) * sv + (sx / 2)).toInt() and 0xFF

                // BT.601 full-range YUV -> RGB
                val c = yv - 16
                val d = cu - 128
                val e = cv - 128
                out[o++] = ((298 * c + 409 * e + 128) shr 8).coerceIn(0, 255).toByte()
                out[o++] = ((298 * c - 100 * d - 208 * e + 128) shr 8).coerceIn(0, 255).toByte()
                out[o++] = ((298 * c + 516 * d + 128) shr 8).coerceIn(0, 255).toByte()
            }
        }
        return out
    }

    private fun clampIndex(value: Int, max: Int): Int = when {
        value < 0 -> 0
        value > max -> max
        else -> value
    }

    private fun toGray(rgb: ByteArray): ByteArray {
        val gray = ByteArray(rgb.size / 3)
        var i = 0
        var j = 0
        while (i + 2 < rgb.size) {
            val r = rgb[i].toInt() and 0xFF
            val g = rgb[i + 1].toInt() and 0xFF
            val b = rgb[i + 2].toInt() and 0xFF
            gray[j++] = ((r * 77 + g * 150 + b * 29) shr 8).toByte()
            i += 3
        }
        return gray
    }

    private fun meanAbsDiff(a: ByteArray, b: ByteArray): Float {
        if (a.size != b.size || a.isEmpty()) return Float.MAX_VALUE
        var sum = 0
        for (i in a.indices) {
            sum += kotlin.math.abs((a[i].toInt() and 0xFF) - (b[i].toInt() and 0xFF))
        }
        return sum.toFloat() / a.size
    }

    companion object {
        const val TAG = "FrameTap"
    }
}
