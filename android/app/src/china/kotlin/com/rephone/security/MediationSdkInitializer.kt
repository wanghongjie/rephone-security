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

            // 【隐私合规 · 关键】关闭 SDK 对「已安装应用列表」的采集。
            //
            // alist() 是穿山甲 SDK 的**应用列表采集总开关**：
            // 返回 true（默认）时，SDK 会在初始化/广告请求阶段调用
            // PackageManager.getInstalledPackages() 采集设备上已安装的应用，
            // MIUI 随即弹出系统级「获取安装应用信息 / 应用列表」授权弹窗。
            //
            // 与 getCustomAppList() 的区别：
            //   · getCustomAppList() 只覆盖「上报给服务端的应用列表字段」；
            //   · alist() 覆盖「是否采集」这一行为本身，返回 false 后 SDK 完全不读取。
            // 因此本开关才是消除 MIUI 弹窗的关键，两者需同时设为「不采集」。
            override fun alist(): Boolean = false

            override fun getMediationPrivacyConfig(): IMediationPrivacyConfig {
                return object : MediationPrivacyConfig() {
                    // 【隐私合规 · 关键】禁止 SDK 自行读取设备上的「已安装应用列表」。
                    //
                    // getCustomAppList() 返回 null 时，SDK 会走默认逻辑自行调用
                    // PackageManager.getInstalledPackages() 采集应用安装列表，
                    // 在 MIUI 上会触发系统级「获取安装应用信息 / 应用列表」授权弹窗，
                    // 属于「未以自定义弹窗同步告知目的即索取权限」的违规项。
                    //
                    // 返回**非 null**（此处为空列表）表示由开发者自行提供该数据，
                    // SDK 不再调用系统接口读取；空列表即代表本应用不提供、也不允许
                    // SDK 采集任何应用安装列表信息。
                    override fun getCustomAppList(): List<String>? = emptyList()

                    // 同理：返回非 null 的空列表，禁止 SDK 自行采集 IMEI。
                    override fun getCustomDevImeis(): List<String>? = emptyList()

                    override fun isCanUseOaid(): Boolean = true

                    override fun isLimitPersonalAds(): Boolean = false

                    override fun isProgrammaticRecommend(): Boolean = true
                }
            }
        }
    }
}
