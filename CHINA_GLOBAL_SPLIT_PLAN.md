# RePhone Security China / Global 拆分阶段性任务规划

- 文档版本：v1.0
- 适用范围：RePhone Security 国内版 / 海外版 差异化工程化改造
- 目标：让国内版从 Dart 代码、Pub 依赖、Android 原生依赖、iOS Pod 与配置四个层面**真正剔除** Firebase / IAP (GMS Billing / StoreKit 仅留海外) / Google Mobile Ads / GMS 相关库，同时保留海外版完整能力；两条版本线共享一套业务代码与一套构建矩阵。
- 文档锚点：当前项目工程结构与历史文件见 [README.md](file:///Users/wanghongjie/Desktop/workspace/rephone-security/README.md)、[BUILD_INFO.md](file:///Users/wanghongjie/Desktop/workspace/rephone-security/BUILD_INFO.md)。

---

## 目录 (TOC)

- [0. 背景、问题、目标](#0-背景问题目标)
- [1. 关键术语约定](#1-关键术语约定)
- [2. 构建矩阵（先立规范再动代码）](#2-构建矩阵先立规范再动代码)
- [3. 总体改造策略与依赖关系](#3-总体改造策略与依赖关系)
- [4. Phase 0 — 构建矩阵固化与 market 单一事实来源](#4-phase-0--构建矩阵固化与-market-单一事实来源)
- [5. Phase 1 — AppEnv 注入体系落地（能力门面化）](#5-phase-1--appenv-注入体系落地能力门面化)
- [6. Phase 2 — Dart 层编译期隔离（国内入口不 import 海外 SDK）](#6-phase-2--dart-层编译期隔离国内入口不-import-海外-sdk)
- [7. Phase 3 — 平台构建隔离（Android/iOS 原生链接不进海外 SDK）](#7-phase-3--平台构建隔离androidios-原生链接不进海外-sdk)
- [8. Phase 4 — Pub 依赖治理（可选深度治理）](#8-phase-4--pub-依赖治理可选深度治理)
- [9. Phase 5 — 回归验收与交付物沉淀](#9-phase-5--回归验收与交付物沉淀)
- [10. 统一验收清单（China / Global 各一份）](#10-统一验收清单china--global-各一份)
- [11. 风险与对策](#11-风险与对策)
- [12. 附录：关键代码文件索引](#12-附录关键代码文件索引)

---

## 0. 背景、问题、目标

### 0.1 当前工程现状（v1.0 改造前）

- 已具备两条 Dart 入口：
  - 海外入口 [lib/main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart)
  - 国内入口 [lib/main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart)
- Android 侧已初步配置 `productFlavors { global / china }`，见 [android/app/build.gradle:L39-L51](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle#L39-L51)，并做了少量 AAR exclude，见 [android/app/build.gradle:L106-L120](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle#L106-L120)。
- `flavors` 目录已建 [lib/flavors/app_env.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/flavors/app_env.dart)，但目前为注释占位，未承担注入职责。
- 差异化能力主要靠 `AppMarket.value` 运行时判断（[lib/utils/app_market.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_market.dart)）与 `firebaseEnabled / membershipEnabled` 便捷 getter（[lib/utils/app_features.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_features.dart)）。
- Pub 全局声明了 Firebase / In-App Purchase / Google Mobile Ads，见 [pubspec.yaml:L60-L66](file:///Users/wanghongjie/Desktop/workspace/rephone-security/pubspec.yaml#L60-L66)。
- iOS 侧单 Target 硬编码 Firebase/AdMob：
  - [ios/Runner/AppDelegate.swift:L3-L12](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/AppDelegate.swift#L3-L12)
  - [ios/Runner/Info.plist:L27-L28](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/Info.plist#L27-L28)
  - `ios/Runner/GoogleService-Info.plist` 已在 Runner 目录。

### 0.2 当前问题（为什么必须改造）

| # | 问题 | 后果 |
|---|---|---|
| P1 | Pub 仍强依赖海外 SDK 插件 | 国内包即便不走业务分支，Flutter 自动构建仍可能把原生库打进产物 |
| P2 | Dart 层仅运行时判断，import 链未切断 | 极端环境（无 GMS、无插件）下仍易出现“找不到类/符号”或初始化异常 |
| P3 | iOS 单 Target 统一拉 Firebase/AdMob Pod | 国内 IPA 天然带海外 SDK 符号，合规/包体均不合要求 |
| P4 | 入口 × flavor × iOS scheme 未强绑定 | 出现“国内入口但编译了 global 配置”的人祸 |
| P5 | 能力实现散落在多个页面中（Banner 代码 3 份重复） | 后续替换国内广告/Push/IAP SDK 需要改 N 处，回归成本高 |

### 0.3 交付目标

- **国内包（China）**：
  - Dart 编译单元中，国内入口不出现 `firebase_core / firebase_messaging / firebase_crashlytics / in_app_purchase* / google_mobile_ads` 的 import。
  - Android APK/AAB 中，不包含 GMS / Firebase / Billing / GMA 相关 AAR 与类符号。
  - iOS IPA 中，不链接 `Firebase* / Google-Mobile-Ads-SDK`，Info.plist 不含 `GADApplicationIdentifier`，`GoogleService-Info.plist` 不进 bundle。
- **海外包（Global）**：
  - FCM、Crashlytics、Play/StoreKit IAP、AdMob 保持原有功能与行为。
- **全工程**：
  - 统一用 `AppEnv` 注入能力；业务页只依赖能力接口，不直接依赖具体 SDK。
  - 构建命令形成 4 条矩阵（Android/iOS × China/Global），脚本化、可在 CI 复制执行。

---

## 1. 关键术语约定

- **入口（Entry / Target File / `-t`）**：Dart 层 `lib/main.dart` 与 `lib/main_china.dart`。两者唯一的职责是**初始化 AppEnv 并启动 App**，不应包含任何重复的路由/主题代码（后面会抽共享 app widget）。
- **Flavor**：Android `productFlavors` / iOS `Scheme + Configuration`。负责控制：
  - `applicationId / bundleId`
  - 原生依赖（`chinaImplementation` 之类）
  - 资源文件（Manifest、Info.plist、google-services.json、GoogleService-Info.plist）
- **能力门面（Facade）**：`CrashService / PushService / IapService / AdService` 等 Dart 抽象。业务代码只依赖门面，不依赖 `FirebaseCrashlytics`、`InAppPurchase`、`MobileAds`、`BannerAd` 等具体 SDK 类。
- **Market**：业务语义上的国内/海外版本标记（`global` / `china`）。后续以 `--dart-define=MARKET=xxx` 为 Dart 侧唯一裁决来源。

---

## 2. 构建矩阵（先立规范再动代码）

> 任何 Phase 的验收都必须在下面 4 条命令构建的产物上执行；禁止手动混搭“入口 + flavor”。

### 2.1 Android（Flavor + 入口）

- **海外 Global**
  ```bash
  flutter build apk   --flavor global -t lib/main.dart \
    --dart-define=MARKET=global \
    --android-project-arg=targetRegion=global
  flutter build appbundle --flavor global -t lib/main.dart \
    --dart-define=MARKET=global \
    --android-project-arg=targetRegion=global
  ```
- **国内 China**
  ```bash
  flutter build apk   --flavor china  -t lib/main_china.dart \
    --dart-define=MARKET=china
  flutter build appbundle --flavor china  -t lib/main_china.dart \
    --dart-define=MARKET=china
  ```

> 说明：`targetRegion=global` 用于 `com.google.gms.google-services` 与 `com.google.firebase.crashlytics` Gradle 插件 apply（现有脚本已在 [android/app/build.gradle:L8-L11](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle#L8-L11) 做了开关）。国内版不传该参数即默认不 apply。

### 2.2 iOS（Scheme/Configuration + 入口）

iOS 侧需要先配两套 Configuration / Scheme（Phase 3 执行），命名约定如下：

- **海外 Global**：Scheme `Runner-Global`，Configuration `Debug-Global` / `Release-Global`
  ```bash
  flutter build ios --flavor Global -t lib/main.dart \
    --dart-define=MARKET=global
  ```
- **国内 China**：Scheme `Runner-China`，Configuration `Debug-China` / `Release-China`
  ```bash
  flutter build ios --flavor China  -t lib/main_china.dart \
    --dart-define=MARKET=china
  ```

### 2.3 本地调试命令

- 海外 Android 调试：`flutter run --flavor global -t lib/main.dart --dart-define=MARKET=global --android-project-arg=targetRegion=global`
- 国内 Android 调试：`flutter run --flavor china  -t lib/main_china.dart --dart-define=MARKET=china`

---

## 3. 总体改造策略与依赖关系

```
Phase 0 (矩阵规范 + market 来源)
  └─> Phase 1 (AppEnv 注入 + 共享 app shell)
        └─> Phase 2 (Dart 编译期隔离：能力实现双份 + 入口只挑一份)
              |
              ├─> Phase 3A (Android 原生隔离：AAR exclude + 资源分 src/global src/china)
              └─> Phase 3B (iOS 原生隔离：Schemes + Pod 条件 + Info.plist 分开)
                    └─> Phase 4 (可选：把 global-only Pub 插件拆到独立 package)
                          └─> Phase 5 (回归验收 + 脚本 + 文档沉淀)
```

- **串行关系**：Phase 0 → 1 → 2 必须按顺序（否则门面没建好就切接口，业务代码到处报错）。
- **并行关系**：Phase 3A / 3B 可并行（Android/iOS 平台工程改动互不依赖 Dart 细节，但都要求 Phase 2 先把 Dart 入口不 import 海外 SDK 打通，否则即便原生删了也会在 Dart 侧 crash）。
- **可选阶段**：Phase 4 可延后，只要 Phase 2+3 达标，就能先满足“国内包不带海外 SDK 符号”的合规要求。

---

## 4. Phase 0 — 构建矩阵固化与 market 单一事实来源

- **目标**：把“入口 × flavor × MARKET 定义”先钉死，防止后续阶段出现“编译了 china 入口但 AppMarket 返回 global”这种不一致。
- **前置依赖**：无。
- **预计工作量**：0.5 人日。

### 4.1 任务清单

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T0.1 | 新增构建脚本 `scripts/build_flavors.sh`（或 Makefile），封装 §2 的 4 条矩阵命令 | 新建 `scripts/build_flavors.sh` |
| T0.2 | 新增“入口与 flavor 一致性校验” | 在入口、`AppMarket.init()` 中加断言：`MARKET == 'china'` 时，平台 flavor 必须是 `china`（Android）或 scheme 标记必须是 `china`（iOS）；debug 下若不一致直接弹红屏/报错。 | [lib/main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart)、[lib/main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart)、[lib/utils/app_market.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_market.dart) |
| T0.3 | 将 `AppMarket` 的裁决权从“平台 MethodChannel”改为“dart-define MARKET”优先，平台 channel 仅用于 debug 校验 | [lib/utils/app_market.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_market.dart) |
| T0.4 | 更新 README / BUILD_INFO / 交付脚本，明确 CI 必须用 §2 四条命令执行 | [README.md](file:///Users/wanghongjie/Desktop/workspace/rephone-security/README.md)、[BUILD_INFO.md](file:///Users/wanghongjie/Desktop/workspace/rephone-security/BUILD_INFO.md) |

### 4.2 验收标准

- `flutter run --flavor china -t lib/main_china.dart --dart-define=MARKET=global` 在 debug 启动即报错（错位检测生效）。
- `AppMarket.value` 在 China / Global 两次调试中稳定返回预期值，且不再依赖“有没有 GMS / 国内 ROM”这种环境因素。

### 4.3 风险

- 低：主要是规范层 + 少量断言代码。

---

## 5. Phase 1 — AppEnv 注入体系落地（能力门面化）

- **目标**：业务代码从“直接 new FirebaseCrashlytics / MobileAds / InAppPurchase.instance”改为“通过 `AppEnv` 拿能力接口”。先运行时隔离，编译期隔离放在 Phase 2。
- **前置依赖**：Phase 0 完成（MARKET 单一来源）。
- **预计工作量**：1.5 ~ 2 人日。

### 5.1 任务清单

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T1.1 | 定义强类型配置与能力开关：新增 `lib/flavors/env_config.dart`（`enum Market { global, china }`、`EnvConfig`、`FeatureToggles`） | `lib/flavors/env_config.dart`（新建） |
| T1.2 | 实装 [lib/flavors/app_env.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/flavors/app_env.dart) 注入入口：`AppEnv.inject(config, toggles, crash: x, push: x, iap: x, ads: x)`，并提供静态只读访问器 | [lib/flavors/app_env.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/flavors/app_env.dart) |
| T1.3 | 定义 4 个能力门面接口（先抽象，不急着搬实现）：`CrashService / PushService / IapService / AdService` | `lib/flavors/features/*.dart`（新建目录与文件） |
| T1.4 | 共享 App Shell：把 `RePhoneSecurityApp`（主题、路由、本地化）从两份 main 中抽去 `lib/app.dart`，main 只做 inject + runApp | 新建 [lib/app.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/app.dart)，改造 [main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart) 与 [main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart) |
| T1.5 | 把散落的 `FirebaseCrashlytics.instance.*`、`MobileAds.instance.*`、`membershipEnabled / firebaseEnabled / adMobEnabled` 调用点，先替换为 `AppEnv.*` 或 `AppEnv.features.*`（运行时能走通即可，编译期隔离留 Phase 2） | [main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart)、[app_features.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_features.dart)、[main_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/main_page.dart) 等 |
| T1.6 | 文档同步：更新 app_env 注释与 flavors 目录 README（如果需要） | [lib/flavors/](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/flavors) |

### 5.2 验收标准

- 两条入口都能正常进入 Startup → Welcome / Home 流程。
- 代码搜索 `FirebaseCrashlytics.instance`、`MobileAds.instance`、`InAppPurchase.instance` 仅在 “global 具体实现文件” 或旧服务类（还未迁移）中出现，业务 UI 页面中数量为 0（Banner 三处例外：Phase 1 可以先改为门面接口的调用形式）。

### 5.3 风险

- 中：IAP 页面逻辑复杂（[membership_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/membership_page.dart)），抽接口初期可能出现“购买状态丢失 / restore 回调不触发”，必须写回归 case。

---

## 6. Phase 2 — Dart 层编译期隔离（国内入口不 import 海外 SDK）

- **目标**：在 Dart 编译单元层面切断 `main_china.dart` → 海外 SDK 的 import 链路。即便 pub 还在依赖，china 入口编译时代码里不会触发对 Firebase/IAP/AdMob 类的静态引用。
- **前置依赖**：Phase 1 完成。
- **预计工作量**：2 ~ 3 人日。

### 6.1 能力拆分映射

| 能力 | 抽象接口 | Global 具体实现（import 海外 SDK） | China 具体实现（不 import 海外 SDK） |
|------|----------|------------------------------------|--------------------------------------|
| Crash  | `CrashService` | `FirebaseCrashlyticsService`（使用 `firebase_crashlytics`） | `NoopCrashService`（预留 Bugly/Tencent 接入点） |
| Push   | `PushService` | `FcmPushService`（使用 `firebase_messaging` + 现有 [push_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/push_service.dart) 的逻辑） | `NoopPushService`（预留 HMS / 小米 / 魅族 push 接入点） |
| IAP    | `IapService`  | `StoreIapService`（使用 `in_app_purchase*`，复用现有 [iap_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/iap_service.dart)） | `NoopIapService`（预留微信/支付宝/RMB 购买接入点） |
| 广告 | `AdService` | `AdMobBannerService`（使用 `google_mobile_ads`） | `PangleOrNoopAdService`（优先复用已有的 Pangle PlatformView：[android/app/src/china/kotlin/.../pangle/](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/china/kotlin/com/rephone/security/pangle)、[widgets/pangle_banner_view.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/widgets/pangle_banner_view.dart)、[mediation_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/mediation_service.dart)） |

### 6.2 任务清单

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T2.1 | 在 `lib/flavors/features/` 下新增 4 个 global 具体实现与 4 个 noop 实现，并让 [main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart) 只 import global 实现、[main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart) 只 import noop/pangle 实现 | `lib/flavors/features/`、两个 main 文件 |
| T2.2 | 把现有 [push_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/push_service.dart) 内容迁移到 `FcmPushService`，并在原类中留“转发到 AppEnv.push + Deprecate”的壳，最后删掉 | [push_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/push_service.dart) |
| T2.3 | 把现有 [iap_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/iap_service.dart) 内容迁移到 `StoreIapService`，同样过渡后删除原文件 | [iap_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/iap_service.dart) |
| T2.4 | Banner 三处统一改造：[profile_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/profile_page.dart)、[camera_list_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/camera_list_page.dart)、[camera_endpoint_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/camera_endpoint_page.dart) 不再 import `google_mobile_ads`，改为调用 `AppEnv.ads.createBanner(...)` 返回一个 Widget；由 China/Global 实现内部决定走 AdMob、走 Pangle，或返回空 SizedBox | 三个 Page 文件 + AdService 抽象 |
| T2.5 | [membership_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/membership_page.dart) 改造：China 入口模式下要么隐藏“购买”按钮（仅展示“海外版提供订阅”占位），要么直接不在 MainPage Tab 中挂载；Global 模式保持原购买/恢复流程。 | [main_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/main_page.dart)、[membership_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/membership_page.dart) |
| T2.6 | 静态白名单检查：写 CI grep 规则，China 入口链路上（main_china → app shell → pages/services）不得 import 以下包：`firebase_core`、`firebase_messaging`、`firebase_crashlytics`、`in_app_purchase*`、`google_mobile_ads`。Global 实现文件允许。 | CI 脚本（建议放 `scripts/audit_dart_imports.sh`） |

### 6.3 验收标准

- 代码审计（T2.6 脚本）对 china 入口链路输出 clean。
- 国内 debug 包启动后，所有用到 Push/IAP/Ads/Crash 的分支都走 noop 或国内实现，**不出现 MissingPluginException / ClassNotFound**。
- 海外 debug 包完整回归：FCM token 上报、IAP 商品拉取、Banner 展示、Crash 上报均正常。

### 6.4 风险

- 高：IAP 回调流（purchaseStream、restore、iOS sandbox 升降级）改造时最容易出错；建议先把现有 IAP 相关 case 写一份手动回归清单（或自动化）。

---

## 7. Phase 3 — 平台构建隔离（Android/iOS 原生链接不进海外 SDK）

- **目标**：即便 Pub 里还声明 Firebase/AdMob/IAP，也要在平台侧做到“China flavor 不链接、不进包”。这是满足国内商店合规与包体干净的**硬门槛**。
- **前置依赖**：Phase 2 完成（Dart 侧不引用类即可避免“符号没链接导致 Dart 侧反射失败”）。
- **预计工作量**：Android 1 人日；iOS 2 ~ 3 人日（含 Xcode 手工改工程配置）。

### 7.1 Phase 3A：Android 侧

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T3A.1 | 移动 `google-services.json`：从 `android/app/` 移到 `android/app/src/global/google-services.json`；`src/china/` 禁止放置 | [android/app/google-services.json](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/google-services.json) |
| T3A.2 | 扩展 china flavor 的 exclude：在现有 exclude billing 基础上，补充常见传递依赖排除：`com.google.android.gms:*`（先按子模块白名单精细化，最小集合从 `play-services-basement / play-services-base / firebase-installations / firebase-iid / firebase-messaging / firebase-crashlytics` 开始） | [android/app/build.gradle:L106-L120](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle#L106-L120) |
| T3A.3 | `google-services` 与 `crashlytics` Gradle 插件只对 global 开启（现有已做），并验证 china 构建时 Gradle Sync log 中不出现 `google-services plugin` 字样 | [android/app/build.gradle:L8-L11](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle#L8-L11) |
| T3A.4 | Manifest 资源隔离：`src/main/AndroidManifest.xml` 只放公共权限；`src/global/AndroidManifest.xml` 叠加 FCM/AdMob 相关 `<service>`、`<receiver>`、`<queries>`；`src/china/AndroidManifest.xml` 叠加 Pangle 所需声明（如已有） | [android/app/src/main/AndroidManifest.xml](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/main/AndroidManifest.xml)、[global](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/global)、[china](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/china) |
| T3A.5 | 产物校验脚本：新增 `scripts/audit_android_artifacts.sh`，解压 china-release APK 并 grep/列出 AAR/class 不允许的包名前缀 | 新建脚本 |

**3A 验收标准**：
- China APK 解压后 `classes*.dex` / `lib/` 中不出现 `com.google.firebase / com.google.android.gms / com.google.android.gms.ads / com.android.billingclient` 等包符号（用 `apkanalyzer dex packages` 或 strings + grep 做粗查）。

### 7.2 Phase 3B：iOS 侧

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T3B.1 | 采用“单 Target + 4 套 Configuration + Schemes”（推荐）或“双 Target”方案（见计划正文），产出 `Runner-Global / Runner-China` 两个 Scheme + Debug/Release Config | [ios/Runner.xcodeproj/project.pbxproj](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner.xcodeproj/project.pbxproj) |
| T3B.2 | `Podfile` 按 Configuration 条件引入 Firebase/AdMob：仅 `*-Global` 配置下 `pod 'FirebaseCore' / 'FirebaseMessaging' / 'FirebaseCrashlytics' / 'Google-Mobile-Ads-SDK'`；`*-China` 不引入；China 如果要接国内 SDK 单独加 pod | [ios/Podfile](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Podfile) |
| T3B.3 | Swift 编译条件：`AppDelegate.swift` 用 `#if GLOBAL_CONFIG import FirebaseCore; FirebaseApp.configure() #endif`；并在 `*-Global` 的 BuildSettings 里加 `OTHER_SWIFT_FLAGS = -DGLOBAL_CONFIG` | [ios/Runner/AppDelegate.swift](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/AppDelegate.swift) |
| T3B.4 | Info.plist 双份：新建 `Info-Global.plist`（保留 `GADApplicationIdentifier`）与 `Info-China.plist`（移除 `GADApplicationIdentifier`），并按 Configuration 在 BuildSettings 指向不同 plist | [ios/Runner/Info.plist](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/Info.plist)（拆成两份） |
| T3B.5 | `GoogleService-Info.plist` 仅 Copy Bundle Resource 到 Global 配置；China 构建时不拷贝 | Build Phase / 脚本化 |
| T3B.6 | 产物校验脚本：`scripts/audit_ios_artifacts.sh`，用 `nm`/`strings`/`otool` 粗扫 China IPA 里不应出现的符号/字符串前缀 | 新建脚本 |

**3B 验收标准**：
- China scheme 的 `Podfile.lock` 中不再出现 `Firebase*`、`Google-Mobile-Ads-SDK`、`GoogleUtilities*`。
- Payload 中 `Info.plist` 不含 `GADApplicationIdentifier`；可执行文件 `strings` 扫不到 `FIR* / GAD*`。

### 7.3 风险

- 高（iOS）：手动改 pbxproj 容易出错，建议用命令行/脚本对比两份备份，或用 `xcodeproj` gem 做程序化改造。
- 中（Android）：exclude 过粗可能误杀；要逐步增量 exclude，每增一条跑一次 assembleRelease。

---

## 8. Phase 4 — Pub 依赖治理（可选深度治理）

- **目标**：连 `pubspec.yaml` 层面都把 global-only 插件声明移除，`flutter pub deps` 对国内环境完全干净；此阶段**非必须**，可在包体/合规更严格场景再做。
- **前置依赖**：Phase 2、Phase 3 全部通过（否则即便去掉 pub 也会因为调用点残留直接 crash）。
- **预计工作量**：3 ~ 5 人日（含工程结构改造）。

### 8.1 任务清单

| 任务 | 说明 | 关键文件 |
|------|------|----------|
| T4.1 | 新建子 package：`packages/rephone_global_services/`，把 `firebase_* / in_app_purchase* / google_mobile_ads` 依赖搬到该 package 的 pubspec | 新建目录结构 |
| T4.2 | 将 Phase 2 的 “Global 具体实现” 从 `lib/flavors/features/*_global.dart` 搬到子 package 内部 export | 子 package lib 目录 |
| T4.3 | [main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart) `dependencies` 改为依赖子 package；[main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart) 不依赖；主工程 [pubspec.yaml](file:///Users/wanghongjie/Desktop/workspace/rephone-security/pubspec.yaml) 删除 global-only 依赖声明 | 两侧 pubspec |
| T4.4 | CI 跑 `flutter pub deps --no-dev` 并对 China 构建做白名单校验（可选） | 脚本 |

### 8.2 验收标准

- 主工程 `pubspec.yaml` 不再出现 `firebase_core / firebase_messaging / firebase_crashlytics / in_app_purchase* / google_mobile_ads`。
- 两条入口构建与功能回归仍 100% 通过。

---

## 9. Phase 5 — 回归验收与交付物沉淀

- **目标**：形成“可复制、可脚本化、可审计”的最终交付物，保证后续版本迭代不再破坏拆分结果。
- **前置依赖**：Phase 0~4（或 0~3）全部完成。
- **预计工作量**：1 人日。

### 9.1 交付物清单

| 交付物 | 位置 | 说明 |
|--------|------|------|
| 构建矩阵脚本 | `scripts/build_flavors.sh` | 封装 §2 的 4 条标准命令 |
| Dart import 审计脚本 | `scripts/audit_dart_imports.sh` | Phase 2，用于 china 链路 import 白名单检查 |
| Android 产物审计脚本 | `scripts/audit_android_artifacts.sh` | Phase 3A，AAR/DEX 包名检查 |
| iOS 产物审计脚本 | `scripts/audit_ios_artifacts.sh` | Phase 3B，Pods/符号/plist 检查 |
| 手动回归清单 | 附在本 §10 | 两份（Global / China），QA 与开发共用 |
| flavors 文档 | 本文件 + flavors 目录 README | 新人接手与架构对齐 |

---

## 10. 统一验收清单（China / Global 各一份）

### 10.1 Global (海外) 回归清单

- [ ] 首次启动：Startup → Welcome → Auth → Home 全流程无 crash
- [ ] 登录成功后 FCM token 正常上报到后端（抓包或后端日志验证）
- [ ] iOS：APNs token + FCM token 流程正常；切前后台 token refresh 正常
- [ ] Crashlytics：手动触发一次测试崩溃，Firebase Console 能看到
- [ ] IAP：
  - [ ] 拉取商品列表成功（每月/每年/新单一产品）
  - [ ] 购买成功 → 服务端验证 → 会员权益生效
  - [ ] Restore 成功（iOS sandbox 尤其要测）
  - [ ] 已过期用户重购同一 base plan 不出现 ERROR 5/6
- [ ] AdMob：
  - [ ] 相机列表 Banner 正常展示
  - [ ] 相机端 Banner 正常展示
  - [ ] 个人中心 Banner 正常展示
  - [ ] VIP 用户不展示 Banner 的逻辑生效

### 10.2 China (国内) 回归清单

- [ ] 首次启动：Startup → Welcome → Auth → Home 全流程无 crash，不弹出 “Google Play services unavailable” 之类无关告警
- [ ] Dart：不触发 Firebase/IAP/AdMob 相关 MissingPluginException / NoSuchMethod
- [ ] Android APK 审计脚本 clean（见 Phase 3A）
- [ ] iOS IPA 审计脚本 clean（见 Phase 3B）
- [ ] Tab 结构：
  - [ ] 不出现 Membership Tab（或入口仅提示“海外版可用”，点击不拉起购买）
  - [ ] 相机角色切换、登录登出、登出后回 Welcome 正常
- [ ] 广告：
  - [ ] 国内版 Banner 位置要么是 Pangle 正常展示，要么占位不可见；不得出现“请求 AdMob 又加载失败”的报错日志刷屏
- [ ] Push：
  - [ ] noop 实现不崩溃；若后续接 HMS/其他国内 Push，则以最小接入方式验证能初始化
- [ ] 包体对比：国内 APK/IPA 体积相较海外版本应有可感知下降（因剔除 Firebase/AdMob/Billing 等）

---

## 11. 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|------|------|------|------|
| iOS pbxproj 改造导致工程打不开 | 中 | 高 | 改前全量备份；用 `diff` 校验；必要时用 `xcodeproj` gem 程序化改 |
| Android exclude 过粗误杀 HMS 或其他库 | 中 | 中 | 每次只增 1~2 条 exclude 规则，并跑 `assembleChinaRelease` 全量构建验证 |
| IAP 抽接口后 purchaseStream 回调丢失 | 高 | 高 | Phase 1 就先把 IAP 状态流转画成流程图 + 手动回归 checklist；迁移过程中保留 `IapService` 转发过渡期壳 |
| Banner 三个页面的尺寸/生命周期适配差异 | 中 | 中 | AdService 抽象时统一暴露“size + slotId + onReady/onFail”回调，Pangle 与 AdMob 各自做实现，不把平台细节泄漏到 UI 页面 |
| China 入口误配 Global flavor | 中 | 中 | Phase 0 的错位校验 + CI 强制用标准脚本构建，禁止开发人员手动输入命令 |

---

## 12. 附录：关键代码文件索引

（便于 Phase 执行时快速定位需要改动的点）

- Dart 入口：[main.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main.dart)、[main_china.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/main_china.dart)
- Flavors 注入锚点：[app_env.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/flavors/app_env.dart)
- 现有差异化判断：[app_market.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_market.dart)、[app_features.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/utils/app_features.dart)
- 现有海外服务实现：[push_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/push_service.dart)、[iap_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/iap_service.dart)、[mediation_service.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/services/mediation_service.dart)
- Banner 三处改造点：[profile_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/profile_page.dart)、[camera_list_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/camera_list_page.dart)、[camera_endpoint_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/camera_endpoint_page.dart)
- Tab/角色切换：[main_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/main_page.dart)、[membership_page.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/pages/membership_page.dart)
- Pub：[pubspec.yaml](file:///Users/wanghongjie/Desktop/workspace/rephone-security/pubspec.yaml)
- Android 构建：[android/app/build.gradle](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/build.gradle)、[android/build.gradle](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/build.gradle)、[android/settings.gradle](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/settings.gradle)
- Android Flavor 资源：[global/](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/global)、[china/](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/china)
- iOS 构建：[ios/Podfile](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Podfile)、[project.pbxproj](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner.xcodeproj/project.pbxproj)
- iOS Runner 配置：[AppDelegate.swift](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/AppDelegate.swift)、[Info.plist](file:///Users/wanghongjie/Desktop/workspace/rephone-security/ios/Runner/Info.plist)
- 国内 Android Pangle 接入（已有）：[pangle/](file:///Users/wanghongjie/Desktop/workspace/rephone-security/android/app/src/china/kotlin/com/rephone/security/pangle)、[pangle_banner_view.dart](file:///Users/wanghongjie/Desktop/workspace/rephone-security/lib/widgets/pangle_banner_view.dart)

---

**文档维护承诺**：
- 每完成一个 Phase，在本文件对应章节末尾追加“完成日期 + 执行人 + 验证结果 + 变更摘要”的历史记录行；避免规划文档与真实工程状态脱节（按用户偏好：重构后立即同步所有规划/接入文档）。
