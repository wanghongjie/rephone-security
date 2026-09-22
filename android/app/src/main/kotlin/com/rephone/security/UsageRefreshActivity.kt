package com.rephone.security

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager

/**
 * 透明、无感知的一次性 Activity。
 *
 * 唯一作用：让自己 resume 到前台，使系统 UsageStats 记录的
 * 「应用最后使用时间」被刷新为当前时间，随后立即退出。
 *
 * 必须运行在独立 task（见 AndroidManifest 的 taskAffinity），
 * 否则会把主 task 的相机页面一起带到前台。
 */
class UsageRefreshActivity : android.app.Activity() {

    companion object {
        private const val TAG = "UsageRefresh"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 不拦截触摸、不获取焦点、不点亮屏幕，做到对用户完全无感
        window.setFlags(
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        )
        Log.i(TAG, "activity onCreate")
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "activity onResume -> UsageStats lastTime refreshed")
        UsageRefreshManager.markRefreshed(this)

        Handler(Looper.getMainLooper()).postDelayed({
            finish()
            overridePendingTransition(0, 0)
        }, UsageRefreshManager.FINISH_DELAY_MS)
    }

    override fun onDestroy() {
        Log.i(TAG, "activity destroyed")
        super.onDestroy()
    }
}
