package com.rephone.security

import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * 静默刷新系统「应用最后使用时间」(UsageStats.lastTime)。
 *
 * 背景：华为/EMUI 的「不常用应用清理」以 UsageStats 记录的 lastTime 计时，
 * 约 5 天未被前台使用即在夜间息屏+充电窗口执行 force-stop（置 stopped=true，
 * 此时 START_STICKY 也无法自愈）。后台 Service 运行不会刷新 lastTime，
 * 只有 Activity 真正 resume 才会。
 *
 * 对策：每隔一段时间（默认 2 天）在检测到息屏时，启动一个透明 Activity
 * 到前台极短时间后 finish，从而把 lastTime 重置为当前时间，让计时永不达阈值。
 */
object UsageRefreshManager {

    private const val TAG = "UsageRefresh"
    private const val PREFS_NAME = "usage_refresh"
    private const val KEY_LAST_REFRESH = "last_refresh_ms"
    private const val KEY_ENABLED = "auto_start_enabled"
    private const val WORK_NAME = "usage_refresh_periodic"

    /** 隐私同意状态单独持久化：自启动由系统在新进程中拉起，进程内闸门已失效 */
    private const val CONSENT_PREFS_NAME = "privacy_gate"
    private const val KEY_CONSENT_GRANTED = "privacy_consent_granted"

    /** 华为阈值约 5 天，这里提前到 2 天刷新，留足安全边际 */
    private val REFRESH_THRESHOLD_MS = TimeUnit.DAYS.toMillis(2)

    /** 检查周期：12 小时一次，配合息屏判断，5 天内有多达 10 次命中机会 */
    private val CHECK_INTERVAL_HOURS = 12L

    /** 透明 Activity 停留时长，确保 onResume 被系统记录后再退出 */
    const val FINISH_DELAY_MS = 300L

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun consentPrefs(context: Context) =
        context.getSharedPreferences(CONSENT_PREFS_NAME, Context.MODE_PRIVATE)

    /** 用户是否已同意隐私政策（跨进程持久化）。 */
    fun isConsentGranted(context: Context): Boolean =
        consentPrefs(context).getBoolean(KEY_CONSENT_GRANTED, false)

    /** 记录用户已同意隐私政策，并按当前开关状态同步周期任务。 */
    fun setConsentGranted(context: Context, granted: Boolean) {
        consentPrefs(context).edit().putBoolean(KEY_CONSENT_GRANTED, granted).apply()
        Log.i(TAG, "consentGranted=$granted")
        sync(context)
    }

    /** 用户是否允许「后台保活自启动」，未做过选择时默认允许（隐私政策已明示）。 */
    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, true)

    /** 设置自启动开关并同步周期任务（持久化 + 立即注册/取消）。 */
    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        Log.i(TAG, "autoStartEnabled=$enabled")
        sync(context)
    }

    /**
     * 按「隐私政策已同意 && 用户开启自启动」决定注册还是取消周期任务。
     *
     * 【合规】同意前 / 用户关闭后都不会注册，任务被取消后系统不会再拉起本应用。
     */
    fun sync(context: Context) {
        val granted = isConsentGranted(context)
        val enabled = isEnabled(context)
        if (granted && enabled) {
            schedule(context)
        } else {
            cancel(context)
            Log.i(TAG, "auto-start stays off (consent=$granted, enabled=$enabled)")
        }
    }

    /** 取消周期任务，系统不再拉起本应用。 */
    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        Log.i(TAG, "cancelled periodic work")
    }

    fun lastRefreshMs(context: Context): Long =
        prefs(context).getLong(KEY_LAST_REFRESH, 0L)

    fun markRefreshed(context: Context) {
        val now = System.currentTimeMillis()
        prefs(context).edit().putLong(KEY_LAST_REFRESH, now).apply()
        Log.i(TAG, "markRefreshed time=$now")
    }

    /**
     * 判断屏幕是否熄灭。
     *
     * 不用 PowerManager.isInteractive()：JobScheduler 持 CPU 锁运行任务时它可能返回 true，
     * 导致误判为亮屏而跳过刷新。Display.state 直接反映屏幕真实状态，不受 CPU 锁影响。
     */
    fun isScreenOff(context: Context): Boolean {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val state = dm.getDisplay(Display.DEFAULT_DISPLAY)?.state ?: Display.STATE_UNKNOWN
        Log.d(TAG, "display state=$state (STATE_ON=${Display.STATE_ON})")
        return state != Display.STATE_ON
    }

    /**
     * Android 10 (API 29) 起系统限制后台启动 Activity，且前台服务不属于例外。
     * 官方例外之一是已获用户授予 SYSTEM_ALERT_WINDOW，此处据此判断。
     */
    fun canStartActivityFromBackground(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return Settings.canDrawOverlays(context)
    }

    /** 执行一次检查，满足条件则启动透明 Activity 刷新 lastTime */
    fun runCheck(context: Context, trigger: String) {
        // 【合规兜底】任务已被取消时系统仍可能残留一次回调，这里二次校验，
        // 确保未同意隐私政策或用户已关闭开关时绝不产生自启动行为。
        if (!isConsentGranted(context)) {
            Log.i(TAG, "skip: privacy consent not granted")
            return
        }
        if (!isEnabled(context)) {
            Log.i(TAG, "skip: auto-start disabled by user")
            cancel(context)
            return
        }

        val last = lastRefreshMs(context)
        val now = System.currentTimeMillis()
        val elapsed = if (last == 0L) Long.MAX_VALUE else now - last
        val screenOff = isScreenOff(context)

        val elapsedDesc = if (last == 0L) {
            "never"
        } else {
            String.format(Locale.US, "%.2fd", elapsed / TimeUnit.DAYS.toMillis(1).toDouble())
        }
        Log.i(TAG, "check trigger=$trigger elapsed=$elapsedDesc screenOff=$screenOff")

        if (elapsed < REFRESH_THRESHOLD_MS) {
            Log.i(TAG, "skip: threshold not reached (need ${REFRESH_THRESHOLD_MS / 86400000}d)")
            return
        }
        if (!screenOff) {
            Log.i(TAG, "skip: screen is on, wait for screen-off")
            return
        }
        if (!canStartActivityFromBackground(context)) {
            Log.w(TAG, "skip: Android 10+ requires SYSTEM_ALERT_WINDOW to launch from background")
            return
        }

        val intent = Intent(context, UsageRefreshActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        Log.i(TAG, "launched UsageRefreshActivity")
    }

    /** 注册周期检查任务，重复调用安全（已存在则保留原任务） */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<UsageRefreshWorker>(
            CHECK_INTERVAL_HOURS, TimeUnit.HOURS
        ).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
        Log.i(TAG, "scheduled periodic check every ${CHECK_INTERVAL_HOURS}h")
    }
}
