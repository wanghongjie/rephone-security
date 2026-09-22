# china flavor 已通过 Gradle 配置剔除 com.google.android.gms / com.google.firebase / com.android.billingclient 等海外
# 原生依赖；但 Flutter 插件（google_mobile_ads / firebase_* / in_app_purchase）的 Java/Kotlin 侧代码仍会进入 R8，
# 导致大量 Missing class 的 warn。这些路径国内版不会实际运行，因此降级为 ignore。
#
# Pangle/字节侧的 Missing class 一般来自 AAR 间字节码增强/注解（非关键运行时类），这里也一并 dontwarn，
# 保证国内 flavor 的 minifyRelease 能编过；如后续发现线上崩溃，可收敛到具体类再精细调优。

-keepattributes **
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# ------------------------------------------------------------------------------
# 反射入口必须 keep：MainActivity 通过 Class.forName + Class.getMethod 调用它们，
# R8 看不到静态引用，release 会把方法名混淆 → NoSuchMethodException
#   · MainActivity.configureFlutterEngine → PangleBannerPlatformViewPlugin.registerWith(...)
#   · MethodChannel initMediationAdSdk  → MediationSdkInitializer.init(Context)
# 现象：debug 正常，release 下 Pangle 广告完全不初始化（进程不崩，静默失败）。
# ------------------------------------------------------------------------------
-keep class com.rephone.security.MediationSdkInitializer { *; }
-keep class com.rephone.security.pangle.** { *; }

# WorkManager：Worker 由框架反射实例化，release 混淆需保留其构造器
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Google / Firebase / Play billing
-dontwarn com.google.ads.mediation.admob.**
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.gms.tasks.**
-dontwarn com.google.firebase.**
-dontwarn com.android.billingclient.**
-dontwarn io.flutter.plugins.googlemobileads.**
-dontwarn io.flutter.plugins.firebase.core.**
-dontwarn io.flutter.plugins.firebase.crashlytics.**
-dontwarn io.flutter.plugins.firebase.messaging.**
-dontwarn io.flutter.plugins.inapppurchase.**

# Pangle / 字节 & okhttp3（Pangle 传递依赖常见 warning）
-dontwarn com.bytedance.**
-dontwarn com.bytedance.component.sdk.**
-dontwarn com.bytedance.embed_dr.**
-dontwarn com.bytedance.framwork.core.sdkmonitor.**
-dontwarn com.bytedance.keva.**
-dontwarn com.byazt.**
-dontwarn ms.bz.bd.**
-dontwarn okhttp3.**
-dontwarn okio.**
