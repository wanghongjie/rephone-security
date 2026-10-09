package com.rephone.security

import android.content.Context
import android.util.Log
import com.bytedance.sdk.openadsdk.TTAdConfig
import com.bytedance.sdk.openadsdk.TTAdSdk
import com.bytedance.sdk.openadsdk.TTCustomController
import com.bytedance.sdk.openadsdk.mediation.init.IMediationPrivacyConfig
import com.bytedance.sdk.openadsdk.mediation.init.MediationPrivacyConfig
import java.util.concurrent.atomic.AtomicBoolean

object MediationSdkInitializer {
    private const val TAG = "MediationSdkInitializer"
    private const val APP_ID = "5879949" //"5819967" 测试
    private const val APP_NAME = "RePhone Security"
    private val initialized = AtomicBoolean(false)
    private val initStarted = AtomicBoolean(false)
    private val callbackLock = Any()
    private val pendingCallbacks = mutableListOf<(Boolean) -> Unit>()

    @JvmStatic
    fun ensureInitialized(context: Context, callback: (Boolean) -> Unit) {
        if (initialized.get()) {
            callback(true)
            return
        }
        // 【隐私合规兜底】用户未点击隐私政策「同意」前，绝不初始化 SDK。
        // 此处不直接失败，而是把初始化动作挂起到闸门打开后重试。
        if (!PrivacyConsentGate.isGranted()) {
            Log.i(TAG, "Mediation SDK init deferred: privacy consent not granted yet")
            PrivacyConsentGate.whenGranted {
                ensureInitialized(context.applicationContext, callback)
            }
            return
        }
        synchronized(callbackLock) {
            if (initialized.get()) {
                callback(true)
                return
            }
            pendingCallbacks.add(callback)
        }
        init(context)
    }

    @JvmStatic
    fun init(context: Context) {
        if (initialized.get()) {
            Log.i(TAG, "Mediation SDK already initialized, skip")
            return
        }
        // 【隐私合规兜底】闸门未打开时直接拒绝，避免读取 OAID / MAC / 传感器列表。
        if (!PrivacyConsentGate.isGranted()) {
            Log.i(TAG, "Mediation SDK init skipped: privacy consent not granted yet")
            return
        }
        if (!initStarted.compareAndSet(false, true)) {
            Log.i(TAG, "Mediation SDK init already started, skip")
            return
        }

        val appContext = context.applicationContext
        Log.i(TAG, "TTAdSdk.init(): appId=$APP_ID, appName=$APP_NAME, ctx=${appContext.javaClass.name}")
        TTAdSdk.init(appContext, buildConfig(appContext))
        Log.i(TAG, "TTAdSdk.start(): begin")
        TTAdSdk.start(object : TTAdSdk.Callback {
            override fun success() {
                initialized.set(true)
                Log.i(TAG, "Mediation SDK init success")
                drainCallbacks(true)
            }

            override fun fail(code: Int, msg: String?) {
                initStarted.set(false)
                Log.e(TAG, "Mediation SDK init failed: code=$code, msg=$msg")
                drainCallbacks(false)
            }
        })
    }

    private fun drainCallbacks(ok: Boolean) {
        val callbacks: List<(Boolean) -> Unit> = synchronized(callbackLock) {
            if (pendingCallbacks.isEmpty()) return
            val copy = pendingCallbacks.toList()
            pendingCallbacks.clear()
            copy
        }
        callbacks.forEach { cb ->
            try {
                cb(ok)
            } catch (e: Exception) {
                Log.w(TAG, "ensureInitialized callback failed: ${e.message}")
            }
        }
    }

    private fun buildConfig(context: Context): TTAdConfig {
        return TTAdConfig.Builder()
            .appId(APP_ID)
            .appName(APP_NAME)
            .useMediation(true)
            .debug(false)
            .themeStatus(0)
            .supportMultiProcess(false)
            .customController(getTTCustomController())
            .build()
    }

    private fun getTTCustomController(): TTCustomController {
        return object : TTCustomController() {
            // 【隐私合规】本应用不提供基于位置/电话状态/WiFi 信息的功能，
            // 因此明确关闭 SDK 对这三类敏感信息的读取：
            // - location：不读取定位；
            // - phoneState：不读取 IMEI/设备电话状态；
            // - wifiState：不读取 WiFi 信息（含 MAC/BSSID 等网络接口信息）。
            override fun isCanUseLocation(): Boolean = false

            override fun isCanUsePhoneState(): Boolean = false

            override fun isCanUseWifiState(): Boolean = false

            override fun isCanUseWriteExternal(): Boolean = true

            // 设备标识（AndroidId / OAID）仅用于广告展示与反作弊，
            // 已在隐私政策「设备信息」中明确告知。
            override fun isCanUseAndroidId(): Boolean = true

            override fun getMediationPrivacyConfig(): IMediationPrivacyConfig {
                return object : MediationPrivacyConfig() {
                    override fun getCustomAppList(): List<String>? = null

                    override fun getCustomDevImeis(): List<String>? = null

                    override fun isCanUseOaid(): Boolean = true

                    override fun isLimitPersonalAds(): Boolean = false

                    override fun isProgrammaticRecommend(): Boolean = true
                }
            }
        }
    }
}
