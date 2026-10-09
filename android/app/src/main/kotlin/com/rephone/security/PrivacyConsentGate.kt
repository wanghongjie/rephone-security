package com.rephone.security

import java.util.concurrent.atomic.AtomicBoolean

/**
 * 隐私政策同意闸门（进程内单例）。
 *
 * 应用上架合规要求：在用户点击隐私政策「同意」按钮之前，
 * 本应用及其集成的任何第三方 SDK 都不得调用系统隐私敏感接口
 * （例如读取 OAID / MAC 地址 / 传感器列表）。
 *
 * 该闸门默认处于「未同意」状态；只有 Flutter 侧在用户点击「同意」后，
 * 通过 MethodChannel 调用 `grantPrivacyConsent` 才会打开。
 * 所有第三方 SDK 初始化入口都必须先校验本闸门：
 * - 已同意：立即执行；
 * - 未同意：[whenGranted] 会把初始化动作挂起，等 [grant] 时再执行，
 *   从而保证即使有遗漏的提前调用点，也不会在同意前真正初始化 SDK。
 */
object PrivacyConsentGate {
    private val granted = AtomicBoolean(false)
    private val waiters = mutableListOf<() -> Unit>()

    /** 用户是否已同意隐私政策。 */
    fun isGranted(): Boolean = granted.get()

    /** 打开闸门，并立即执行所有等待中的初始化任务（幂等）。 */
    fun grant() {
        val pending: List<() -> Unit>
        synchronized(this) {
            if (granted.get()) return
            granted.set(true)
            pending = waiters.toList()
            waiters.clear()
        }
        pending.forEach { action ->
            try {
                action()
            } catch (_: Exception) {
                // 单个等待任务失败不影响其它任务。
            }
        }
    }

    /**
     * 若已同意隐私政策则立即执行 [action]；否则挂起，待 [grant] 时执行。
     */
    fun whenGranted(action: () -> Unit) {
        val runNow: Boolean
        synchronized(this) {
            if (granted.get()) {
                runNow = true
            } else {
                waiters.add(action)
                runNow = false
            }
        }
        if (runNow) action()
    }
}
