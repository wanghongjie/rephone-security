/// IAP 领域 DTO（与具体支付 SDK 完全解耦）。
///
/// 目的：`IapService` 门面只暴露本文件中的类型，业务代码
/// （如 `membership_page.dart`）不允许直接 import
/// `in_app_purchase` / `in_app_purchase_android` 等 SDK 包，
/// 从而在 Dart 层完成「国内包 / 海外包」的隔离：
/// - 海外包由 `features/iap_service_global.dart` 将 SDK 类型转换为本 DTO；
/// - 国内包 / 无支付包由 `iap_service_china.dart`、`iap_service_noop.dart`
///   以空实现返回同样的 DTO 结构，无需链接任何支付 SDK。
library;

/// 订阅套餐的一个计费阶段（对应 SDK 的 pricing phase，如免费试用期、月付、年付）。
class IapPricingPhase {
  const IapPricingPhase({
    required this.priceAmountMicros,
    required this.formattedPrice,
    required this.billingPeriod,
    required this.billingCycleCount,
    required this.priceCurrencyCode,
  });

  /// 微分为单位的金额（避免浮点误差，用于价格比较）。
  final int priceAmountMicros;

  /// 展示用价格字符串，如 "$4.99"。
  final String formattedPrice;

  /// 计费周期，如 "P1M"（月付）、"P1Y"（年付）。
  final String billingPeriod;

  /// 计费周期数；0 表示无限期（如按周期续费）。
  final int billingCycleCount;

  /// 价格币种代码，如 "USD"、"CNY"。
  final String priceCurrencyCode;
}

/// 订阅套餐（对应 Google Play 的 base plan / offer，或 Apple 的订阅套餐）。
class IapSubscriptionOffer {
  const IapSubscriptionOffer({
    this.basePlanId,
    this.offerIdToken,
    this.pricingPhases = const [],
  });

  /// Google Play base plan id，如 "monthly"、"yearly"。
  final String? basePlanId;

  /// Google Play 下单所需的 offer id token；Apple 订阅通常为空。
  final String? offerIdToken;

  /// 计费阶段列表；第一个阶段通常是当前生效的订阅价格。
  final List<IapPricingPhase> pricingPhases;

  /// 订阅单价（取第一个计费阶段）。
  IapPricingPhase? get introPhase => pricingPhases.isEmpty ? null : pricingPhases.first;
}

/// 内购商品（对 SDK `ProductDetails` 的抽象）。
class IapProduct {
  const IapProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.subscriptionOffers = const [],
    this.nativeHandle,
  });

  /// 商品 ID（与后台/App Store/Play Console 一致）。
  final String id;

  /// 商品名称。
  final String title;

  /// 商品描述。
  final String description;

  /// 展示用价格字符串，如 "$4.99"。
  final String price;

  /// 数值价格（double，便于展示与比较）。
  final double rawPrice;

  /// 币种代码，如 "USD"、"CNY"。
  final String currencyCode;

  /// 订阅套餐列表（仅订阅商品有值；Google Play base plan 场景用它下单）。
  final List<IapSubscriptionOffer> subscriptionOffers;

  /// 仅供门面实现层（features/*_global.dart）保存原始 SDK 对象做反向转换，
  /// 业务代码请勿访问此字段。
  final Object? nativeHandle;
}

/// 内购交易状态（对 SDK `PurchaseStatus` 的抽象）。
enum IapPurchaseStatus {
  /// 交易完成（已扣款）。
  purchased,

  /// 交易失败（见 [IapPurchase.error]）。
  error,

  /// 交易进行中（等待确认结果，尚未完成）。
  pending,

  /// 通过恢复购买流程找回的历史交易。
  restored,

  /// 用户取消了交易。
  canceled,
}

/// 内购错误（对 SDK `IAPError` 的抽象）。
class IapPurchaseError {
  const IapPurchaseError({
    required this.code,
    required this.message,
    this.details,
  });

  /// 错误码，如 'storekit_...'、'billing_...'。
  final String code;

  /// 人类可读的错误描述。
  final String message;

  /// 附加详情（可能为 null）。
  final dynamic details;
}

/// 服务端票据校验数据（对 SDK `PurchaseVerificationData` 的抽象）。
class IapVerificationData {
  const IapVerificationData({
    required this.source,
    required this.serverVerificationData,
    required this.localVerificationData,
  });

  /// 校验来源标识（SDK 枚举名的字符串形式）。
  final String source;

  /// 可上传到自有服务端做二次校验的原始票据。
  final String serverVerificationData;

  /// 本地校验数据。
  final String localVerificationData;
}

/// 一笔内购交易（对 SDK `PurchaseDetails` 的抽象）。
class IapPurchase {
  const IapPurchase({
    required this.productID,
    this.purchaseID,
    this.status = IapPurchaseStatus.pending,
    this.transactionDate,
    this.pendingCompletePurchase = false,
    this.error,
    required this.verificationData,
    this.nativeHandle,
  });

  /// 商品 ID。
  final String productID;

  /// 交易/订单 ID（可能为 null，例如部分平台确认前）。
  final String? purchaseID;

  /// 交易状态。
  final IapPurchaseStatus status;

  /// 交易时间戳（SDK 返回的字符串形式）。
  final String? transactionDate;

  /// 是否待确认完成（SDK 建议在服务端校验后调用 completePurchase）。
  final bool pendingCompletePurchase;

  /// 交易失败原因（仅 [IapPurchaseStatus.error] 时有值）。
  final IapPurchaseError? error;

  /// 服务端票据校验数据（用于把票据上传到自有服务端）。
  final IapVerificationData verificationData;

  /// 仅供门面实现层（features/*_global.dart）保存原始 SDK 对象做反向转换，
  /// 业务代码请勿访问此字段。
  final Object? nativeHandle;
}
