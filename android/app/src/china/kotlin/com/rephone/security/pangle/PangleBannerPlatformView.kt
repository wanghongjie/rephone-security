package com.rephone.security.pangle

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import com.bytedance.sdk.openadsdk.AdSlot
import com.bytedance.sdk.openadsdk.TTAdDislike
import com.bytedance.sdk.openadsdk.TTAdNative
import com.bytedance.sdk.openadsdk.TTAdSdk
import com.bytedance.sdk.openadsdk.TTNativeExpressAd
import com.rephone.security.MediationSdkInitializer
import io.flutter.plugin.platform.PlatformView

class PangleBannerPlatformView(
    context: Context,
    params: Map<String, Any?>?,
) : PlatformView {
    private val tag = "PangleBannerView"
    private val container = FrameLayout(context)
    private var bannerAd: TTNativeExpressAd? = null
    private val activity = findActivity(context)

    init {
        val codeId = params?.get("codeId") as? String ?: "104032066"
        val widthPx = (params?.get("widthPx") as? Number)?.toInt()?.coerceAtLeast(1) ?: 100
        val heightPx = (params?.get("heightPx") as? Number)?.toInt()?.coerceAtLeast(1) ?: 30
        Log.i(
            tag,
            "Create PlatformView: codeId=$codeId, widthPx=$widthPx, heightPx=$heightPx, context=${context.javaClass.name}, base=${(context as? ContextWrapper)?.baseContext?.javaClass?.name}, activity=${activity?.javaClass?.name}",
        )
        try {
            MediationSdkInitializer.ensureInitialized(context.applicationContext) { ok ->
                val act = activity
                if (!ok) {
                    Log.w(tag, "Skip banner load: Mediation SDK init failed")
                    return@ensureInitialized
                }
                if (act == null) {
                    Log.w(tag, "Skip banner load: activity is null")
                    return@ensureInitialized
                }
                act.runOnUiThread {
                    Log.i(tag, "Mediation SDK ready, start banner load")
                    loadBannerAd(codeId, widthPx, heightPx)
                }
            }
            Log.i(tag, "Triggered MediationSdkInitializer.ensureInitialized()")
        } catch (e: Exception) {
            Log.w(tag, "Mediation SDK ensureInitialized failed: ${e.message}")
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        Log.i(tag, "dispose() called")
        try {
            bannerAd?.setExpressInteractionListener(null)
            bannerAd?.destroy()
        } catch (_: Exception) {
        }
        bannerAd = null
        container.removeAllViews()
    }

    private fun buildBannerAdslot(act: Activity, codeId: String, widthPx: Int, heightPx: Int): AdSlot {
        val density = act.resources.displayMetrics.density.coerceAtLeast(1f)
        val widthDp = widthPx / density
        val heightDp = heightPx / density
        Log.i(
            tag,
            "buildBannerAdslot: codeId=$codeId, imageAcceptedSize=${widthPx}x$heightPx(px), expressAcceptedSize=${widthDp}x$heightDp(dp), density=$density",
        )
        return AdSlot.Builder()
            .setCodeId(codeId)
            .setImageAcceptedSize(widthPx, heightPx)
            .setExpressViewAcceptedSize(widthDp, heightDp)
            .build()
    }

    private fun loadBannerAd(codeId: String, widthPx: Int, heightPx: Int) {
        val act = activity
        if (act == null) {
            Log.w(tag, "Cannot load banner: context is not Activity")
            return
        }
        Log.i(tag, "loadBannerAd: start, codeId=$codeId")
        val adNativeLoader: TTAdNative = try {
            TTAdSdk.getAdManager().createAdNative(act)
        } catch (e: Exception) {
            Log.w(tag, "Cannot load banner: TTAdSdk not ready: ${e.message}")
            return
        }
        Log.i(tag, "loadBannerAd: call loadBannerExpressAd()")
        adNativeLoader.loadBannerExpressAd(
            buildBannerAdslot(act, codeId, widthPx, heightPx),
            object : TTAdNative.NativeExpressAdListener {
                override fun onNativeExpressAdLoad(ads: MutableList<TTNativeExpressAd>?) {
                    Log.i(tag, "onNativeExpressAdLoad: size=${ads?.size ?: 0}")
                    if (ads.isNullOrEmpty()) {
                        Log.w(tag, "onNativeExpressAdLoad: empty list")
                        return
                    }
                    val ad = ads[0]
                    bannerAd = ad
                    Log.i(tag, "onNativeExpressAdLoad: pick first ad, mediationManager=${ad.mediationManager != null}")
                    showBannerView(act, ad)
                }

                override fun onError(code: Int, message: String?) {
                    Log.w(tag, "loadBannerExpressAd failed: code=$code, message=$message")
                }
            },
        )
    }

    private fun findActivity(context: Context): Activity? {
        if (context is Activity) return context
        var current: Context = context
        var depth = 0
        while (current is ContextWrapper && depth < 20) {
            val base = current.baseContext
            if (base is Activity) return base
            current = base
            depth++
        }
        return null
    }

    private fun showBannerView(act: Activity, ad: TTNativeExpressAd) {
        Log.i(tag, "showBannerView: start")
        ad.setExpressInteractionListener(object : TTNativeExpressAd.ExpressAdInteractionListener {
            override fun onAdClicked(view: View?, type: Int) {
                Log.i(tag, "Banner clicked")
            }

            override fun onAdShow(view: View?, type: Int) {
                Log.i(tag, "onAdShow: type=$type, view=${view?.javaClass?.name}")
                val manager = ad.mediationManager
                val ecpm = manager?.showEcpm
                if (ecpm != null) {
                    Log.i(
                        tag,
                        "Banner shown: ecpm=${ecpm.ecpm}, sdk=${ecpm.sdkName}, slotId=${ecpm.slotId}",
                    )
                } else {
                    Log.i(tag, "onAdShow: showEcpm is null")
                }
            }

            override fun onRenderFail(view: View?, msg: String?, code: Int) {
                Log.w(tag, "Banner render fail: code=$code, msg=$msg, view=${view?.javaClass?.name}")
            }

            override fun onRenderSuccess(view: View?, width: Float, height: Float) {
                Log.i(tag, "Banner render success: ${width}x$height, view=${view?.javaClass?.name}")
                if (bannerAd !== ad) return
                val bannerView = ad.expressAdView
                if (bannerView != null) {
                    container.removeAllViews()
                    if (bannerView.layoutParams == null) {
                        bannerView.layoutParams = FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.MATCH_PARENT,
                            FrameLayout.LayoutParams.MATCH_PARENT,
                        )
                    } else {
                        bannerView.layoutParams.width = FrameLayout.LayoutParams.MATCH_PARENT
                        bannerView.layoutParams.height = FrameLayout.LayoutParams.MATCH_PARENT
                    }
                    container.addView(bannerView)
                    Log.i(tag, "Banner view attached: ${bannerView.javaClass.name}, childCount=${container.childCount}")
                    container.post {
                        Log.i(
                            tag,
                            "Layout info: container=${container.width}x${container.height}, bannerView=${bannerView.width}x${bannerView.height}",
                        )
                    }
                } else {
                    Log.w(tag, "Banner render success but expressAdView is null")
                }
            }
        })

        ad.setDislikeCallback(
            act,
            object : TTAdDislike.DislikeInteractionCallback {
                override fun onShow() {}

                override fun onSelected(position: Int, value: String?, enforce: Boolean) {
                    Log.i(tag, "Dislike selected: position=$position, value=$value, enforce=$enforce")
                    container.removeAllViews()
                }

                override fun onCancel() {}
            },
        )
        try {
            Log.i(tag, "Call ad.render()")
            ad.render()
        } catch (e: Exception) {
            Log.w(tag, "Banner render() failed: ${e.message}")
        }
    }
}
