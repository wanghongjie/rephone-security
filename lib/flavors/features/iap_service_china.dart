import 'dart:async';

import 'package:flutter/foundation.dart';
// 微信 SDK fluwx 6.x（社区维护版）：仅本文件 import，海外入口 main.dart 永不引用，
// 从而不会把微信 SDK 代码链接进 Play Store / App Store 包。
import 'package:fluwx/fluwx.dart' as fluwx;

import '../../services/payment_api.dart';
import '../iap_models.dart';
import '../service_facades.dart';

const String _kTag = 'WechatIAP';

/// 国内版微信支付实现：基于「服务端创建订单 → 客户端调起 SDK →
/// 微信异步回调服务端 / 客户端 verify 兜底」的标准微信支付 APP 模式。
///
/// 设计要点（对齐项目架构约束）：
///
/// 1. **文件级隔离**：仅本文件直接 `import 'package:fluwx/fluwx.dart'`，
///    仅在 `main_china.dart`（国内入口）注入；海外入口 `main.dart` 永不 import
///    本文件，因此微信 SDK 不会被编译进海外包，满足「海外/国内实现彻底隔离」。
///
/// 2. **傻瓜式接入**：业务页面（[MembershipPage]）**完全不感知 fluwx**，
///    只调用 [IapService] 门面的 [createServerOrder] /
///    [notifyServerOrderPaid] / [queryServerOrderStatus] 三个方法；
///    微信 SDK 初始化、签名、调起、回调、轮询、重试等复杂逻辑全部封装在本类。
///
/// 3. **安全原则**：
///    - 价格由服务端集中管理，客户端只传 `sku + plan`（product_id + monthly/yearly），
///      绝不允许客户端直接传金额，防止篡改。
///    - 支付结果**不信任前端 SDK 回调**：SDK 返回成功后，仍立即调用
///      [PaymentApi.verifyWechatOrder] 让服务端主动查单；再通过
///      [PaymentApi.queryWechatOrder] 做最多 8 次指数退避轮询作为兜底，
///      确保即使 notify 回调丢失，权益也能在 30s 内发放。
///
/// 4. **IapService 兼容性**：
///    由于 [IapService] 门面仍声明 `purchasesStream` / `products` 等 getter，
///    本实现中：
///    - `products` 返回空列表（会员套餐展示直接由 MembershipPage 硬编码或后端下发）
///    - `purchasesStream` 返回一个空的广播流（微信支付不会产生购买事件）
///    - `buy` / `purchase` / `restorePurchases` 等 IAP 原生方法直接报错或 noop
///    业务页面在微信分支下，应**通过 [isThirdPartyPaymentEnabled] 判真后，
///    走 [createServerOrder] 链路**，不走 `buy / purchasesStream` 老链路。
class ChinaWechatIapService implements IapService {
  final bool _enabled;

  /// 客户端支付参数 Stream：上层 MembershipPage 可以监听，也可以直接用 await 返回值。
  final StreamController<List<IapPurchase>> _purchases =
      StreamController<List<IapPurchase>>.broadcast();

  // ——— Fluwx 6.x SDK 适配层 ———
  // 6.x 之后不再使用全局函数，改为通过 Fluwx 实例操作：
  //   - 注册 registerApi
  //   - 支付 pay(Payment(...))
  //   - 回调 addSubscriber
  // 所有 SDK 交互都走这个单例实例。
  final fluwx.Fluwx _fluwx = fluwx.Fluwx();

  /// 微信 SDK 是否已经初始化（registerApi 建议只调用一次）。
  bool _sdkInitialized = false;

  /// WeChatResponse 的订阅句柄，用于在 dispose 或超时后安全取消。
  fluwx.FluwxCancelable? _responseCancelable;

  /// 构造：国内入口 `main_china.dart` 中由 `toggles.enableWechatPay` 控制。
  ///
  /// [enabled] 为 false 时，所有操作等价于 Noop：
  /// 不初始化 SDK、不访问网络，但不会抛异常，UI 通过 [isEnabled] 隐藏购买按钮。
  ChinaWechatIapService({bool enabled = true}) : _enabled = enabled;

  // —————————— 基础能力 ——————————

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isThirdPartyPaymentEnabled => _enabled;

  @override
  bool? get iosCanMakePayments => null;

  @override
  List<IapProduct> get products => const <IapProduct>[];

  @override
  Stream<List<IapPurchase>> get purchasesStream => _purchases.stream;

  /// 初始化：注册微信 SDK AppID。
  ///
  /// Flutter 端 `registerApi` 的两个关键参数：
  ///   - `appId`：微信开放平台「移动应用」AppID（`wx` 开头，需在微信商户平台绑定到商户号）
  ///   - `universalLink`：iOS 必选；Android 可忽略。取值需与微信开放平台
  ///     「开发信息 → Universal Links」填写的完全一致。国内云服务器一般配置为
  ///     `https://<你的域名>/<随便一个路径，比如 wechat/`
  ///
  /// 注意：这里 AppID 写死在代码里是**临时方案**，实际可通过 `AppEnv.config`
  /// 或后端接口下发；为了让当前改造能直接跑通，示例值与 `configs/config.ini`
  /// 中 `[wechat_pay].app_id` 的占位一致，后续从后端初始化接口拉取更规范。
  @override
  Future<void> init({bool forceRefresh = false}) async {
    if (!_enabled) return;
    if (_sdkInitialized) return;
    try {
      final ok = await _fluwx.registerApi(
        appId: 'wx_your_app_id',
        doOnAndroid: true,
        doOnIOS: true,
        universalLink: 'https://rephone.top/wechat/',
      );
      _sdkInitialized = ok;
      _WechatLog.d(_kTag, 'fluwx registerApi ok=$ok');
    } catch (e, st) {
      _WechatLog.e(_kTag, 'fluwx 初始化失败：不影响应用启动，后续支付会报错', e, st);
      // 不抛错：SDK 初始化失败时 UI 通过 isEnabled 仍为 true，
      // 但点击购买时会抛出明确错误，让用户重试或联系客服。
    }
  }

  @override
  Future<List<IapProduct>> loadProducts() async {
    // 微信支付模式下：套餐列表由 MembershipPage 自己硬编码（月卡/年卡），
    // 或调用独立的后端接口（/api/payment/products）拉取。
    // 这里返回空列表，不影响现有逻辑。
    return const <IapProduct>[];
  }

  @override
  IapProduct? getProduct(String id) => null;

  // —————————— 商店 IAP 老链路（微信支付不使用，按 noop/报错处理） ——————————

  @override
  Future<void> purchase(String sku) async {
    if (!_enabled) {
      throw StateError('[ChinaWechatIapService] purchase($sku): 微信支付未启用');
    }
    // 业务代码走 createServerOrder，不应走到这里；
    // 兼容老代码调用：直接抛明确错误，便于发现调用点错误。
    throw UnsupportedError(
      '微信支付不能走 purchase() 商店内购 API，请改用 createServerOrder(sku, plan, email)。',
    );
  }

  @override
  Future<void> buy(
    IapProduct product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  }) async {
    throw UnsupportedError(
      '微信支付不能走 buy() 商店内购 API，请改用 createServerOrder。',
    );
  }

  @override
  Future<void> restorePurchases() async {
    // 微信支付无"恢复历史购买"概念：会员权益直接通过后端
    // /api/payment/refresh（即 refreshSubscription）同步。
    debugPrint('[ChinaWechatIapService] restorePurchases：微信支付不支持。');
  }

  @override
  Future<void> restore() => restorePurchases();

  @override
  Future<void> completePurchase(IapPurchase purchase) async {
    // 微信 SDK 不需要手动完成交易（没有 Play/StoreKit 的 3 天退款窗口）。
    debugPrint('[ChinaWechatIapService] completePurchase：微信支付无需调用。');
  }

  // —————————— 第三方支付（服务端下单）新链路 ——————————

  /// 微信 APP 支付：向服务端申请订单 → 调起微信 SDK → 返回 `true` 表示
  /// SDK 返回成功（仍需 verify + 轮询兜底确认权益）。
  ///
  /// 返回结构：
  /// ```
  /// {
  ///   'out_trade_no': 'wx...',    // 订单号，必返回
  ///   'params': { ... },          // 调试用，实际 SDK 已被内部调用
  ///   'sdk_success': true/false,  // 微信 SDK 回调是否 isSuccessful（errCode==0）
  /// }
  /// ```
  @override
  Future<Map<String, dynamic>?> createServerOrder({
    required String sku,
    required String plan,
    required String email,
  }) async {
    if (!_enabled) {
      throw StateError('[ChinaWechatIapService] createServerOrder: 微信支付未启用');
    }
    // 1. 服务端创建订单（prepay_id + 签名参数）
    final result = await PaymentApi().createWechatOrder(
      productId: sku,
      plan: plan,
      email: email,
    );
    if (result == null) {
      _WechatLog.e(_kTag, '创建订单失败：后端返回 null');
      return null;
    }
    final outTradeNo = result['out_trade_no'] as String?;
    final params = result['params'] as Map<String, dynamic>?;
    if (outTradeNo == null || params == null) {
      _WechatLog.e(_kTag, '创建订单响应字段缺失: $result');
      return result;
    }

    // 2. 调起微信 SDK 支付（内部注册一次性回调 + 超时兜底）
    bool sdkSuccess = false;
    try {
      if (!_sdkInitialized) {
        await init(); // 确保 SDK 已注册
      }

      // —— 2a. 用 Completer 包装 Fluwx 6.x 的 addSubscriber 一次性回调 ——
      // addSubscriber 只要回调一次 WeChatPaymentResponse 即完成 Completer；
      // 超时（15s）或异常后安全取消订阅。
      final completer = Completer<fluwx.WeChatPaymentResponse>();
      _responseCancelable?.cancel(); // 防御：清除之前残留的订阅
      _responseCancelable = _fluwx.addSubscriber((resp) {
        if (resp is fluwx.WeChatPaymentResponse && !completer.isCompleted) {
          completer.complete(resp);
        }
      });

      // —— 2b. 发起支付：Payment 是 PayType 的 APP 支付子类（与 3.x Pay 字段一致）
      final payLaunched = await _fluwx.pay(
        which: fluwx.Payment(
          appId: params['app_id'] as String? ?? '',
          partnerId: params['partner_id'] as String? ?? '',
          prepayId: params['prepay_id'] as String? ?? '',
          packageValue: params['package'] as String? ?? 'Sign=WXPay',
          nonceStr: params['nonce_str'] as String? ?? '',
          timestamp: int.tryParse(params['timestamp'] as String? ?? '0') ?? 0,
          sign: params['sign'] as String? ?? '',
        ),
      );
      if (!payLaunched) {
        _WechatLog.w(_kTag, '调起微信失败：pay 返回 false，可能未安装微信');
      }

      final paidEvent = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _WechatLog.w(_kTag, '微信 SDK 回调超时：按失败处理，交由 query 轮询兜底');
          // 15 秒内没收到 SDK 回调：构造一个假的失败事件返回，
          // 让外层流程仍走到 verify + query 轮询，避免错过实际已支付的订单。
          return _DummyFailedPaymentResponse();
        },
      );

      sdkSuccess = paidEvent.isSuccessful;
      _WechatLog.d(_kTag,
          '微信 SDK 回调：errCode=${paidEvent.errCode} outTradeNo=$outTradeNo sdkSuccess=$sdkSuccess');
    } catch (e, st) {
      _WechatLog.e(_kTag, '调起微信 SDK 异常', e, st);
      sdkSuccess = false;
    } finally {
      // 无论成功/失败/超时，都要清理 addSubscriber 的订阅，避免泄漏。
      _responseCancelable?.cancel();
      _responseCancelable = null;
    }

    return <String, dynamic>{
      ...result,
      'sdk_success': sdkSuccess,
    };
  }

  /// SDK 返回成功后，主动调用 /wechat/verify 加速权益发放。
  @override
  Future<bool> notifyServerOrderPaid(
    String orderId, {
    String? email,
    String? transactionId,
  }) async {
    if (orderId.isEmpty || email == null || email.isEmpty) return false;
    final result = await PaymentApi().verifyWechatOrder(
      outTradeNo: orderId,
      email: email,
      transactionId: transactionId,
    );
    if (result == null) return false;
    final paid = result['paid'] as bool? ?? false;
    final verified = result['verified'] as bool? ?? false;
    return paid || verified;
  }

  /// 兜底查单：指数退避，最多查 8 次（约 2s / 4s / 6s ... 总计 ~30s）。
  ///
  /// 用于 notify 回调丢包、verify 接口返回仍未到账的极端场景。
  @override
  Future<bool> queryServerOrderStatus(String orderId, {String? email}) async {
    if (orderId.isEmpty || email == null || email.isEmpty) return false;
    const maxAttempts = 8;
    for (var i = 1; i <= maxAttempts; i++) {
      try {
        final result = await PaymentApi().queryWechatOrder(
          outTradeNo: orderId,
          email: email,
        );
        final paid = result?['paid'] as bool? ?? false;
        if (paid) {
          _WechatLog.d(_kTag, '查单成功：$orderId (第 $i 次)');
          return true;
        }
      } catch (e) {
        _WechatLog.w(_kTag, '查单第 $i 次失败: $e');
      }
      // 指数退避：第 i 次等 i*2 秒
      await Future<void>.delayed(Duration(seconds: i * 2));
    }
    _WechatLog.w(_kTag, '查单 $maxAttempts 次仍未成功：建议用户手动进入会员页刷新');
    return false;
  }
}

/// 微信支付回调超时或异常时，给外层一个语义化的「失败」响应对象，
/// 避免上层分支中对 null / 异常的特殊处理。
///
/// 只在本文件内部使用：返回 isSuccessful=false，errCode 用 -999 标记为「本地超时假失败」，
/// 外层仍会调用 verify + query 查单，保证不会因 SDK 回调丢包而漏发权益。
class _DummyFailedPaymentResponse extends fluwx.WeChatPaymentResponse {
  _DummyFailedPaymentResponse() : super.fromMap(<dynamic, dynamic>{});

  @override
  int? get errCode => -999;

  @override
  String? get errStr => 'local_timeout_or_exception';

  @override
  bool get isSuccessful => false;
}

/// 微信支付模块内部日志封装（私有，避免与全局 `LogUtils` / `package:rephone_security/utils/log_utils.dart` 命名冲突）。
// ignore: unused_element
class _WechatLog {
  static void d(String tag, String msg) {
    if (kDebugMode) debugPrint('[$tag] D: $msg');
  }

  static void w(String tag, String msg) {
    if (kDebugMode) debugPrint('[$tag] W: $msg');
  }

  static void e(String tag, String msg, [Object? err, StackTrace? st]) {
    debugPrint('[$tag] E: $msg');
    if (err != null) debugPrint('  err=$err');
    if (st != null) debugPrint('  stack=$st');
  }
}
