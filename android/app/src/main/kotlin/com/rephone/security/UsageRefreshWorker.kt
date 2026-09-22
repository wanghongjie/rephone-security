package com.rephone.security

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * 周期性检查是否需要刷新 UsageStats.lastTime。
 * 由 UsageRefreshManager.schedule() 调度，每 12 小时执行一次。
 */
class UsageRefreshWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {

    override fun doWork(): Result {
        return try {
            UsageRefreshManager.runCheck(applicationContext, "workmanager")
            Result.success()
        } catch (e: Exception) {
            Log.e("UsageRefresh", "worker failed", e)
            Result.retry()
        }
    }
}
