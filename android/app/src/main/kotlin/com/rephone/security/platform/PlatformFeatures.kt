package com.rephone.security.platform

import android.content.Context
import com.rephone.security.BuildConfig

/** 平台侧通用能力集合：国内 flavor 不硬依赖 GMS，统一通过反射兜底。 */
object PlatformFeatures {

    /** 当前市场：china / global（来自 BuildConfig，对应 flavor 维度）。 */
    @JvmStatic
    val market: String get() = BuildConfig.APP_MARKET

    /** 检查 Google Play services 是否可用；国内 flavor 即便 GMS 类在 classpath 也视为不可用。 */
    @JvmStatic
    fun isGooglePlayServicesAvailable(context: Context): Boolean {
        if (market.equals("china", ignoreCase = true)) return false
        return runCatching {
            val availabilityCls =
                Class.forName("com.google.android.gms.common.GoogleApiAvailability")
            val instance = availabilityCls.getMethod("getInstance").invoke(null)
            val status = availabilityCls
                .getMethod("isGooglePlayServicesAvailable", Context::class.java)
                .invoke(instance, context) as Int
            val successCls = Class.forName("com.google.android.gms.common.ConnectionResult")
            val success = successCls.getField("SUCCESS").get(null) as Int
            status == success
        }.getOrDefault(false)
    }
}
