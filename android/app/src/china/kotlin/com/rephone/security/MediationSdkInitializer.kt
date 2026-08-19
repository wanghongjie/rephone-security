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
    private const val APP_ID = "5819967"
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
            override fun isCanUseLocation(): Boolean = true

            override fun isCanUsePhoneState(): Boolean = true

            override fun isCanUseWifiState(): Boolean = true

            override fun isCanUseWriteExternal(): Boolean = true

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
