package com.rephone.security.pangle

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformViewRegistry

object PangleBannerPlatformViewPlugin {
    @JvmStatic
    fun registerWith(
        context: Context,
        messenger: BinaryMessenger,
        registry: PlatformViewRegistry,
    ) {
        registry.registerViewFactory(
            "pangle_banner_view",
            PangleBannerViewFactory(context, messenger),
        )
    }
}
