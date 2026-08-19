import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../flavors/app_env.dart';
import '../flavors/iap_models.dart';
import '../l10n/app_localizations.dart';
import '../services/payment_api.dart';
import '../services/session_manager.dart';
import '../utils/log_utils.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  bool _isCurrentlyMember = false;
  DateTime? _membershipExpiry;
  bool _loadingProducts = true;
  /// IAP 初始化完成后仍不可用（例如无商店/无支付能力）时置 true。
  /// 不能直接在 build 里读 `AppEnv.iap.isEnabled`：init 前它为 false，
  /// 会导致页面在 init 完成前就定型为「不可用」，即使 init 后价格已返回。
  bool _iapUnavailable = false;
  bool _isRestoring = false;
  bool _isRestoreButtonLoading = false;
  bool _isPurchasing = false;
  String? _activePlan; // monthly|yearly|unknown (from server)
  String? _activePlatform; // ios|android (from server)
  String? _pendingAndroidBasePlanId; // for verify after purchase (rephone_pro base plan)
  String? _error;
  StreamSubscription<List<IapPurchase>>? _purchaseSubscription;
  bool _userInitiatedPurchaseFlow = false;
  DateTime? _lastSnackAt;
  bool _restoreVerifiedEntitlement = false;
  Completer<void>? _restoreVerificationCompleter;
  Completer<void>? _restoreGotRestoredEventCompleter;
  Timer? _restoreSettleTimer;
  IapPurchase? _restoreLatestRestoredPurchase;
  int _restoreLatestRestoredTxMs = -1;
  bool _isCheckingStatus = false;
  DateTime? _lastCheckStatusAt;
  DateTime? _lastAutoRestoreOnErrorAt;
  final Map<String, DateTime> _pendingProductUntil = <String, DateTime>{};
  DateTime? _lastBuyTapAt;

  void _showSnackBarSafe(SnackBar snackBar) {
    if (!mounted) return;
    // Throttle repeated snackbars (e.g. sandbox auto-renew / restore floods)
    final now = DateTime.now();
    if (_lastSnackAt != null && now.difference(_lastSnackAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastSnackAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(snackBar);
  }

  /// 购买流程**最终结果**（校验成功/失败、过期等）：不走 [_showSnackBarSafe] 的 3 秒节流。
  /// 否则「正在验证购买…」刚弹出后，成功提示会在 3 秒内被静默丢弃。
  void _showPurchaseOutcomeSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(snackBar);
  }

  /// 基础版(免费) + 月付 + 年付；年付推荐
  late List<MembershipPlan> _plans;
  String _selectedPremiumPlanId = 'yearly';

  void _syncSelectedPlanWithActivePlan() {
    if (_activePlan == 'monthly') {
      _selectedPremiumPlanId = 'monthly';
    } else if (_activePlan == 'yearly') {
      _selectedPremiumPlanId = 'yearly';
    }
  }

  @override
  void initState() {
    super.initState();
    _plans = _defaultPlans();
    // 每次进入会员页都强制刷新商品价格，避免启动时 init 失败后
    // 命中 "already initialized, skip" 导致页面一直展示加载失败。
    _initIap(force: true);
    _listenPurchases();
    // 启动后先刷新一次服务端权益；
    // 只有在 iOS 且当前判断为非会员时，才执行一次 restore 以补齐历史凭证。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      () async {
        await _checkStatus();
      }();
    });
  }

  /// 返回是否已展示「订阅已过期」提示（用于恢复流程避免重复 SnackBar）。
  Future<bool> _checkStatus({bool showExpiredHint = false}) async {
    // Prevent duplicate concurrent refreshes (e.g. initState + restore completion).
    if (_isCheckingStatus) return false;
    final now = DateTime.now();
    if (_lastCheckStatusAt != null &&
        now.difference(_lastCheckStatusAt!) <
            const Duration(seconds: 2)) {
      return false;
    }
    _isCheckingStatus = true;
    _lastCheckStatusAt = now;
    var showedExpiredSnack = false;
    try {
      final user = await SessionManager.getUser();
      if (user != null) {
        if (!mounted) return showedExpiredSnack;
        final l = AppLocalizations.of(context);
        setState(() {
          _isCurrentlyMember = user.vipLevel > 0;
          _membershipExpiry = user.expireAt;
        });

        // 触发服务端“按需校验”
        // 这里可以静默执行，不需要 loading 遮罩
        try {
          final result = await PaymentApi()
              .refreshSubscription(email: user.email);
          if (result != null) {
            final vipLevel = result['vip_level'] as int? ?? 0;
            final expireAtStr = result['expire_at'] as String?;
            final activePlan = result['active_plan'] as String?;
            final activePlatform = result['platform'] as String?;
            final serverStatus = result['status'] as String?;
            final shouldShowExpired =
                showExpiredHint &&
                vipLevel == 0 &&
                (serverStatus == 'expired' ||
                    (result['message'] is String &&
                        (result['message'] as String)
                            .toLowerCase()
                            .contains('expired')));
            final newUser = user.copyWith(
              vipLevel: vipLevel,
              expireAt: expireAtStr != null ? DateTime.tryParse(expireAtStr) : null,
            );
            await SessionManager.saveUser(newUser);

            if (!mounted) return showedExpiredSnack;
            setState(() {
              _isCurrentlyMember = vipLevel > 0;
              _membershipExpiry = newUser.expireAt;
              _activePlan = activePlan;
              _activePlatform = activePlatform;
              _syncSelectedPlanWithActivePlan();
            });

            LogUtils.d('MembershipPage', 'Status refreshed: vip=$vipLevel');
            if (shouldShowExpired) {
              showedExpiredSnack = true;
              _showSnackBarSafe(
                SnackBar(content: Text(l.membershipSubscriptionExpired)),
              );
            }
          }
        } catch (e) {
          debugPrint('Failed to refresh status: $e');
        }
      }
      return showedExpiredSnack;
    } finally {
      _isCheckingStatus = false;
    }
  }

  bool get _hasActiveSubscription {
    final expiry = _membershipExpiry;
    if (!_isCurrentlyMember) return false;
    if (expiry == null) return true; // 兜底：有会员但无到期时间，按有效处理
    return expiry.isAfter(DateTime.now());
  }

  /// 与后端 [active_plan] 对齐：monthly | yearly（用于购买成功后的提示文案）。
  String? _intendedPlanKeyForPurchase(IapPurchase purchase) {
    final id = purchase.productID;
    if (id == 'rephone_premium_monthly') return 'monthly';
    if (id == 'rephone_premium_yearly') return 'yearly';
    if (id == 'rephone_pro') {
      final bp = _pendingAndroidBasePlanId;
      if (bp == 'monthly' || bp == 'yearly') return bp;
    }
    return null;
  }

  String _friendlyPurchaseError(IapPurchase purchase, AppLocalizations l) {
    final raw = purchase.error;
    final code = raw?.code ?? '';
    final msg = raw?.message ?? '';
    final detailsStr = raw?.details?.toString() ?? '';

    if (Platform.isIOS) {
      if (code == 'storekit_duplicate_product_object') {
        return l.membershipDialogProcessing;
      }

      // Already subscribed to this product (StoreKit server error 3532).
      // Example log:
      // ASDServerErrorDomain Code=3532 "You are currently subscribed to this"
      final combined = '$code $msg $detailsStr';
      if (combined.contains('3532') ||
          combined.toLowerCase().contains('currently subscribed')) {
        return l.membershipSwitchQueued;
      }

      // 常见的网络/会话问题：给更通用的提示
      if (msg.contains('ASDErrorDomain') ||
          msg.contains('AMSErrorDomain') ||
          msg.contains('speedybuy') ||
          msg.contains('timed out')) {
        return l.membershipPurchaseFailed;
      }
    }

    // Android 订阅重复、已拥有等错误通常在 message/code 中体现，做一个兜底友好提示
    if (msg.toLowerCase().contains('already') ||
        msg.toLowerCase().contains('owned') ||
        code.toLowerCase().contains('already') ||
        code.toLowerCase().contains('owned')) {
      return l.membershipStatusPremium;
    }

    // Google Play BillingResponse.developerError (5)，常见于订阅替换参数与 Console 升降级路径不匹配
    if (Platform.isAndroid) {
      final combined = '$code $msg $detailsStr'.toLowerCase();
      if (combined.contains('developererror') ||
          combined.contains('responsecode: 5') ||
          combined.contains('billingresponse.developererror')) {
        return l.membershipAndroidPlayBillingDeveloperError;
      }
    }

    return raw?.message ?? l.membershipPurchaseFailed;
  }

  bool _shouldAutoRestoreOnIOSPurchaseError(IapPurchase purchase) {
    if (!Platform.isIOS) return false;
    final msg = (purchase.error?.message ?? '').toLowerCase();
    final code = (purchase.error?.code ?? '').toLowerCase();

    // iOS sandbox upgrades/downgrades sometimes return:
    // ASDErrorDomain Code=500 -> "Invalid Status Code" (AMSStatusCode=500)
    return msg.contains('invalid status code') ||
        msg.contains('amsstatuscode=500') ||
        (code.contains('500') && (msg.contains('asd') || msg.contains('ams')));
  }

  bool _shouldSuppressPurchaseErrorSnackBar(IapPurchase purchase) {
    if (!Platform.isIOS) return false;

    // 系统已弹出「不允许 App 内购买」时，应用层不再重复弹同类错误提示。
    if (AppEnv.iap.iosCanMakePayments == false) {
      return true;
    }

    final combined = '${purchase.error?.code} '
            '${purchase.error?.message} '
            '${purchase.error?.details}'
        .toLowerCase();
    return combined.contains('payment not allowed') ||
        (combined.contains('asderrordomain') && combined.contains('1050'));
  }

  List<MembershipPlan> _defaultPlans() {
    return [
      MembershipPlan(
        id: 'basic',
        planType: MembershipPlanType.basic,
        price: null,
        isRecommended: false,
        isCurrentPlan: true,
        productId: null,
        displayPrice: null,
      ),
      MembershipPlan(
        id: 'monthly',
        planType: MembershipPlanType.monthly,
        price: null,
        isRecommended: false,
        isCurrentPlan: false,
        productId: 'rephone_premium_monthly',
        basePlanId: 'monthly', // New
        displayPrice: null,
      ),
      MembershipPlan(
        id: 'yearly',
        planType: MembershipPlanType.yearly,
        price: null,
        isRecommended: true,
        isCurrentPlan: false,
        productId: 'rephone_premium_yearly',
        basePlanId: 'yearly', // New
        displayPrice: null,
      ),
    ];
  }

  Future<void> _initIap({bool force = false}) async {
    try {
      // —— 微信支付模式（国内版本）：不走 IAP 商店查询，直接使用服务端统一定价——
      // 服务端价格：月卡 2.99 元、年卡 23.99 元（与 `resolveWechatAmount` 保持一致）。
      // 如需动态改价，可改为调用独立的 /api/payment/products 接口拉取。
      if (AppEnv.iap.isThirdPartyPaymentEnabled) {
        await AppEnv.iap.init(); // 仅注册微信 SDK，不会拉取商品
        if (!mounted) return;
        setState(() {
          _loadingProducts = false;
          for (var i = 0; i < _plans.length; i++) {
            final plan = _plans[i];
            if (plan.planType == MembershipPlanType.monthly) {
              _plans[i] = plan.copyWith(
                price: 2.99,
                displayPrice: '¥2.99 / 月',
              );
            } else if (plan.planType == MembershipPlanType.yearly) {
              _plans[i] = plan.copyWith(
                price: 23.99,
                displayPrice: '¥23.99 / 年',
                isRecommended: true,
              );
            }
          }
        });
        return;
      }
      await AppEnv.iap.init(forceRefresh: force);
      if (!mounted) return;
      if (!AppEnv.iap.isEnabled) {
        // init 完成后仍不可用（无商店/无支付能力）才判定为「该地区不可用」。
        setState(() {
          _iapUnavailable = true;
          _loadingProducts = false;
        });
        return;
      }
      setState(() {
        _loadingProducts = false;
        for (var i = 0; i < _plans.length; i++) {
          final plan = _plans[i];

          // Strategy 2: New Android (Base Plans under 'rephone_pro')
          // Only apply on Android when basePlanId is present
          if (Platform.isAndroid && plan.basePlanId != null) {
            final parentProduct = AppEnv.iap.getProduct('rephone_pro');
            if (parentProduct != null && parentProduct.subscriptionOffers.isNotEmpty) {
              // New Google Play Billing (base plans). Use priceAmountMicros to avoid
              // localization / thousands-separator issues in formattedPrice.
              final offers = parentProduct.subscriptionOffers;

              for (final offer in offers) {
                if (offer.basePlanId == plan.basePlanId &&
                    offer.pricingPhases.isNotEmpty) {
                  final phase = offer.pricingPhases.first;
                  final micros = phase.priceAmountMicros;
                  final raw = micros / 1000000.0;
                  final formatted = phase.formattedPrice;

                  _plans[i] = plan.copyWith(
                    price: raw,
                    displayPrice: formatted,
                    productId: 'rephone_pro',
                    offerToken: offer.offerIdToken,
                  );
                  break;
                }
              }

              if (_plans[i].productId == 'rephone_pro') {
                continue;
              }
            }
          }

          // Strategy 1: Legacy/iOS (Single Product per Plan)
          // Fallback for Android if Strategy 2 failed, or default for iOS
          if (plan.productId != null) {
            final product = AppEnv.iap.getProduct(plan.productId!);
            if (product != null) {
              _plans[i] = plan.copyWith(
                price: product.rawPrice,
                displayPrice: product.price,
              );
              continue;
            }
          }
        }
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _error = 'failed';
      });
      debugPrint('[MembershipPage] _initIap error: $e $st');
    }
  }

  void _listenPurchases() {
    _purchaseSubscription = AppEnv.iap.purchasesStream.listen((list) async {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      for (final purchase in list) {
        // Track pending store transactions to debounce repeated purchase attempts.
        // Pending transactions can persist across app sessions and will cause
        // StoreKit duplicate/pending errors if we try to buy again immediately.
        if (purchase.status == IapPurchaseStatus.pending) {
          _pendingProductUntil[purchase.productID] =
              DateTime.now().add(const Duration(minutes: 5));
        } else {
          _pendingProductUntil.remove(purchase.productID);
        }

        // Restore 阶段：只要收到 restored 事件就标记一下，避免 pendingCompletePurchase=false
        // 导致外层误判“没有可恢复购买”。
        if (_isRestoring &&
            purchase.status == IapPurchaseStatus.restored &&
            _restoreGotRestoredEventCompleter != null &&
            !_restoreGotRestoredEventCompleter!.isCompleted) {
          _restoreGotRestoredEventCompleter!.complete();
        }

        // 避免重复处理同一笔交易
        if (!purchase.pendingCompletePurchase &&
            (purchase.status == IapPurchaseStatus.purchased ||
                purchase.status == IapPurchaseStatus.restored ||
                purchase.status == IapPurchaseStatus.error ||
                purchase.status == IapPurchaseStatus.canceled)) {
          continue;
        }
        switch (purchase.status) {
          case IapPurchaseStatus.pending:
            // Only show UI hints when user just initiated a purchase.
            if (_userInitiatedPurchaseFlow) {
              _showSnackBarSafe(
                SnackBar(content: Text(AppLocalizations.of(context).membershipDialogProcessing)),
              );
            }
            break;
          case IapPurchaseStatus.purchased:
          case IapPurchaseStatus.restored:
            // iOS: storekit_duplicate_product_object 会让插件内部自动触发 restorePurchases()
            // 并吐出大量 restored，但此时 `_isRestoring` 可能是 false（因为不是你手动/页面进入的 restore）。
            // 为避免 restored 风暴逐条后端校验，这里把“自动 restore（由用户点击订阅触发）”也纳入 restore 抑制范围。
            final bool isRestoreStatus = purchase.status == IapPurchaseStatus.restored &&
                (_isRestoring || (_userInitiatedPurchaseFlow && _isPurchasing));

            if (isRestoreStatus) {
              // Restore 阶段：只“收集最新候选”，不逐条调用后端验证。
              // 目的：iOS/沙盒 restore 会吐出大量历史 restored，逐条 verify 会导致重复刷新/重复校验。
              final txMsFromTransactionDate = purchase.transactionDate == null
                  ? -1
                  : int.tryParse(purchase.transactionDate!) ?? -1;
              final txMsFromPurchaseID =
                  int.tryParse(purchase.purchaseID ?? '') ?? -1;
              final candidateScore =
                  txMsFromTransactionDate >= 0 ? txMsFromTransactionDate : txMsFromPurchaseID;
              if (candidateScore > _restoreLatestRestoredTxMs) {
                _restoreLatestRestoredTxMs = candidateScore;
                _restoreLatestRestoredPurchase = purchase;
              }

              // 立即完成 restored，清掉 pending 队列，避免后续 subscribe 再次触发 duplicate transaction。
              await AppEnv.iap.completePurchase(purchase);

              if (!_restoreVerifiedEntitlement) {
                _restoreSettleTimer?.cancel();
                _restoreSettleTimer = Timer(const Duration(seconds: 2), () async {
                  if (_restoreVerifiedEntitlement) return;
                  final candidate = _restoreLatestRestoredPurchase;
                  _restoreVerifiedEntitlement = true;
                  try {
                    // 无论 expired 还是成功，后续都用 `_checkStatus()` 做服务器兜底展示最终状态。
                    if (candidate != null) {
                      final user = await SessionManager.getUser();
                      if (user != null) {
                        if (Platform.isIOS) {
                          await PaymentApi().verifyApplePurchase(
                            transactionId: candidate.purchaseID ?? '',
                            productId: candidate.productID,
                            receiptData: candidate.verificationData.serverVerificationData,
                            email: user.email,
                          );
                        } else {
                          await PaymentApi().verifyGooglePurchase(
                            orderId: candidate.purchaseID ?? '',
                            productId: candidate.productID,
                            purchaseToken: candidate.verificationData.serverVerificationData,
                            basePlanId: candidate.productID == 'rephone_pro' ? _pendingAndroidBasePlanId : null,
                            email: user.email,
                          );
                        }
                      }
                    }
                  } catch (_) {
                    // ignore: we still complete the restore flow and rely on _checkStatus
                  } finally {
                    // 如果当前不是走 `_restorePurchases()`（例如 duplicate 错误触发的自动 restore），
                    // 需要手动刷新一次服务端权益，否则 UI 可能不会立刻更新。
                    if (mounted && !_isRestoring) {
                      await _checkStatus();
                    }
                    if (_restoreVerificationCompleter != null &&
                        !_restoreVerificationCompleter!.isCompleted) {
                      _restoreVerificationCompleter!.complete();
                    }
                  }
                });
              }

              break;
            }

            if (_userInitiatedPurchaseFlow) {
              _showSnackBarSafe(SnackBar(content: Text(l.membershipPurchaseVerifying)));
            }

            final user = await SessionManager.getUser();
            if (user == null) {
              if (_userInitiatedPurchaseFlow) {
                _showPurchaseOutcomeSnackBar(
                  SnackBar(content: Text(l.membershipPleaseLogin)),
                );
              }
              // 未登录也要完成交易，否则会留下 pending 订单，导致下次购买报错
              await AppEnv.iap.completePurchase(purchase);
              return;
            }

            Map<String, dynamic>? result;
            if (Platform.isIOS) {
              result = await PaymentApi().verifyApplePurchase(
                transactionId: purchase.purchaseID ?? '',
                productId: purchase.productID,
                receiptData: purchase.verificationData.serverVerificationData,
                email: user.email,
              );
            } else {
              result = await PaymentApi().verifyGooglePurchase(
                orderId: purchase.purchaseID ?? '',
                productId: purchase.productID,
                purchaseToken: purchase.verificationData.serverVerificationData,
                basePlanId: purchase.productID == 'rephone_pro' ? _pendingAndroidBasePlanId : null,
                email: user.email,
              );
            }

            if (result != null) {
              if (result['subscription_expired'] == true) {
                await AppEnv.iap.completePurchase(purchase);
                _pendingAndroidBasePlanId = null;
                if (_userInitiatedPurchaseFlow) {
                  _showPurchaseOutcomeSnackBar(
                    SnackBar(content: Text(l.membershipSubscriptionExpired)),
                  );
                }
                // Restore flows can emit multiple historical/expired receipts.
                // Avoid spamming refresh/verification by deferring UI refresh until restore completes.
                if (mounted && !_isRestoring) {
                  _checkStatus();
                }
                break;
              }
              await AppEnv.iap.completePurchase(purchase);
              final vipLevel = result['vip_level'] as int? ?? 0;
              final expireAtStr = result['expire_at'] as String?;
              final activePlan = result['active_plan'] as String?;
              final activePlatform = result['platform'] as String?;
              final oldActivePlan = _activePlan;
              final newUser = user.copyWith(
                vipLevel: vipLevel,
                expireAt: expireAtStr != null ? DateTime.tryParse(expireAtStr) : null,
              );
              await SessionManager.saveUser(newUser);

              if (!mounted) return;
              setState(() {
                _isCurrentlyMember = vipLevel > 0;
                _membershipExpiry = newUser.expireAt;
                _activePlan = activePlan;
                _activePlatform = activePlatform;
                _syncSelectedPlanWithActivePlan();
              });

              if (_userInitiatedPurchaseFlow) {
                final intended = _intendedPlanKeyForPurchase(purchase);
                final serverPlan = activePlan;
                final hadPriorPlan =
                    oldActivePlan != null && oldActivePlan!.isNotEmpty;
                final serverUpdatedPlan = serverPlan != null &&
                    serverPlan.isNotEmpty &&
                    hadPriorPlan &&
                    serverPlan != oldActivePlan;

                if (serverUpdatedPlan) {
                  final planLabel = serverPlan == 'monthly'
                      ? l.membershipPlanMonthlyShort
                      : serverPlan == 'yearly'
                          ? l.membershipPlanYearlyShort
                          : '';
                  final msg = l.membershipSwitchAppliedNow.replaceAll('{plan}', planLabel);
                  _showPurchaseOutcomeSnackBar(SnackBar(content: Text(msg)));
                } else if (vipLevel > 0 &&
                    intended != null &&
                    serverPlan != null &&
                    serverPlan.isNotEmpty &&
                    intended != serverPlan) {
                  // 典型：iOS 同组降级/切换后收据已变，但服务端仍返回上一档至周期结束
                  _showPurchaseOutcomeSnackBar(
                    SnackBar(
                      content: Text(l.membershipPurchaseSuccessSwitchPending),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                } else if (vipLevel > 0) {
                  _showPurchaseOutcomeSnackBar(
                    SnackBar(content: Text(l.membershipPurchaseSuccess)),
                  );
                } else {
                  _showPurchaseOutcomeSnackBar(
                    SnackBar(content: Text(l.membershipSwitchQueued)),
                  );
                }
              }
              _pendingAndroidBasePlanId = null;
            } else {
              // 验证失败也要 complete，否则交易会一直挂起
              await AppEnv.iap.completePurchase(purchase);
              _pendingAndroidBasePlanId = null;
              if (_userInitiatedPurchaseFlow) {
                _showPurchaseOutcomeSnackBar(
                  SnackBar(content: Text(l.membershipPurchaseVerifyFailed)),
                );
              }
            }
            break;
          case IapPurchaseStatus.error:
            LogUtils.d(
              'IAP',
              'purchaseStream error productId=${purchase.productID} '
              'code=${purchase.error?.code} msg=${purchase.error?.message} '
              'details=${purchase.error?.details}',
            );
            // 出错时完成交易，避免保留 pending 订单
            await AppEnv.iap.completePurchase(purchase);
            // Errors should still be shown when user initiated the flow.
            if (_userInitiatedPurchaseFlow) {
              if (_shouldSuppressPurchaseErrorSnackBar(purchase)) {
                LogUtils.d(
                  'IAP',
                  'purchase error snackbar suppressed (system purchase-not-allowed prompt already shown)',
                );
              } else {
                final msg = _friendlyPurchaseError(purchase, l);
                _showPurchaseOutcomeSnackBar(SnackBar(content: Text(msg)));
              }

              // iOS sandbox can temporarily fail upgrade/downgrade with
              // ASDErrorDomain Code=500 (Invalid Status Code).
              // Try a restore to pull the resulting transaction/receipt
              // so that server-side verification can reconcile the state.
              if (_shouldAutoRestoreOnIOSPurchaseError(purchase)) {
                final now = DateTime.now();
                final canRestore = _lastAutoRestoreOnErrorAt == null ||
                    now.difference(_lastAutoRestoreOnErrorAt!) >
                        const Duration(seconds: 10);
                if (canRestore && mounted) {
                  _lastAutoRestoreOnErrorAt = now;
                  try {
                    await AppEnv.iap.restore();
                  } catch (_) {
                    // ignore: best-effort
                  }
                }
              }
            }
            break;
          case IapPurchaseStatus.canceled:
            // 用户取消也 complete 一下，清理队列
            await AppEnv.iap.completePurchase(purchase);
            break;
        }

        // 任意终态都解除 UI 的“购买中”状态
        if (mounted &&
            purchase.status != IapPurchaseStatus.pending &&
            _isPurchasing) {
          setState(() => _isPurchasing = false);
        }

        // Any terminal state ends user-initiated UX flow.
        if (purchase.status != IapPurchaseStatus.pending) {
          _userInitiatedPurchaseFlow = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_iapUnavailable) {
      final l = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l.profileMembership)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l.membershipUnavailableInRegion,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMembershipStatus(),
            const SizedBox(height: 12),
            _buildRestoreSection(),
            const SizedBox(height: 28),
            if (_loadingProducts)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              )
            else
              _buildPlansSection(),
            const SizedBox(height: 28),
            _buildFAQSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreSection() {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          const Icon(Icons.restore),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.membershipRestore,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  l.membershipRestoreHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            // 手动 restore：触发 StoreKit 恢复历史交易并补齐服务端 token。
            onPressed: _isRestoring ? null : () {
              _restorePurchases(showSnackbars: true, showButtonLoading: true);
            },
            child: _isRestoreButtonLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.membershipRestoreAction),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipStatus() {
    final l = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isCurrentlyMember
              ? [Colors.purple, Colors.deepPurple]
              : [Colors.grey[400]!, Colors.grey[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isCurrentlyMember ? Icons.workspace_premium : Icons.person,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCurrentlyMember ? l.membershipStatusPremium : l.membershipStatusBasic,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isCurrentlyMember && _membershipExpiry != null)
                      Text(
                        '${[
                          if (_activePlan == 'monthly') l.membershipPlanMonthly,
                          if (_activePlan == 'yearly') l.membershipPlanYearly,
                          if (_activePlatform == 'ios') 'iOS',
                          if (_activePlatform == 'android') 'Android',
                          if (_activePlatform == 'wechat') 'WeChat',
                        ].where((s) => s.isNotEmpty).join(' · ')}\n${l.membershipExpiryPrefix}${_formatDate(_membershipExpiry!)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isCurrentlyMember) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l.membershipUpgradeHint,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlansSection() {
    final l = AppLocalizations.of(context);

    final monthlyPlan = _plans.firstWhere((p) => p.planType == MembershipPlanType.monthly);
    final yearlyPlan = _plans.firstWhere((p) => p.planType == MembershipPlanType.yearly);

    final pricesMissing = !_loadingProducts &&
        (monthlyPlan.displayPrice == null || yearlyPlan.displayPrice == null);

    if (pricesMissing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Text(
              l.membershipLoadProductsFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadingProducts = true;
                  _error = null;
                });
                _initIap(force: true);
              },
              icon: const Icon(Icons.refresh),
              label: Text(l.commonRetry),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.membershipSectionTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          l.membershipDialogUpgradeContent,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 16),
        _buildCombinedPremiumCard(monthlyPlan, yearlyPlan),
      ],
    );
  }

  Widget _buildCombinedPremiumCard(MembershipPlan monthly, MembershipPlan yearly) {
    final l = AppLocalizations.of(context);
    final isYearlySelected = _selectedPremiumPlanId == yearly.id;
    final selectedPlan = isYearlySelected ? yearly : monthly;
    final currentPlatform = Platform.isIOS ? 'ios' : 'android';
    final isCrossPlatformActive =
        _hasActiveSubscription && _activePlatform != null && _activePlatform != currentPlatform;
    final isSelectedCurrentPlan = _hasActiveSubscription &&
        ((_activePlan == 'monthly' && selectedPlan.planType == MembershipPlanType.monthly) ||
            (_activePlan == 'yearly' && selectedPlan.planType == MembershipPlanType.yearly));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.star, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l.membershipPlanPro,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ..._buildFeatureWidgets(yearly, l),
                const Divider(height: 32),
                _buildPlanOption(context, monthly, l),
                const SizedBox(height: 12),
                _buildPlanOption(context, yearly, l, discountLabel: _yearlyDiscountLabel(monthly, yearly, l)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (isSelectedCurrentPlan || isCrossPlatformActive)
                        ? null
                        : () => _subscribeToPlan(selectedPlan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      isCrossPlatformActive
                          ? (currentPlatform == 'android'
                              ? l.membershipCrossPlatformFromIOSShort
                              : l.membershipCrossPlatformFromAndroidShort)
                          : isSelectedCurrentPlan
                              ? l.membershipPlanCurrent
                              : '${l.membershipActionSubscribe} ${selectedPlan.displayPrice ?? ""}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根据月付/年付价格计算年付折扣文案：折扣后单价 + 省 XX%
  String? _yearlyDiscountLabel(MembershipPlan monthly, MembershipPlan yearly, AppLocalizations l) {
    final monthlyPrice = monthly.price;
    final yearlyPrice = yearly.price;
    if (monthlyPrice == null || yearlyPrice == null || monthlyPrice <= 0) return null;
    final equivalentPerMonth = yearlyPrice / 12;
    final savePercent = (1 - yearlyPrice / (monthlyPrice * 12)) * 100;
    if (savePercent <= 0) return null;
    final percentStr = savePercent >= 1 ? savePercent.round().toString() : savePercent.toStringAsFixed(0);
    final priceStr = equivalentPerMonth == equivalentPerMonth.roundToDouble()
        ? equivalentPerMonth.round().toString()
        : equivalentPerMonth.toStringAsFixed(2);

    // 尝试从月付/年付的 displayPrice 中提取货币前缀（如 "JP¥"、"$"）。
    String currencyPrefix = '';
    final displayForCurrency = monthly.displayPrice ?? yearly.displayPrice;
    if (displayForCurrency != null && displayForCurrency.isNotEmpty) {
      final firstDigitIndex = displayForCurrency.indexOf(RegExp(r'\d'));
      if (firstDigitIndex > 0) {
        currencyPrefix = displayForCurrency.substring(0, firstDigitIndex).trim();
      }
    }
    final priceWithCurrency =
        currencyPrefix.isNotEmpty ? '$currencyPrefix$priceStr' : priceStr;

    final pricePart =
        l.membershipPlanPricePerMonth.replaceAll('{price}', priceWithCurrency);
    final savePart = l.membershipYearlySavePercent.replaceAll('{percent}', percentStr);
    return '$pricePart · $savePart';
  }

  Widget _buildPlanOption(BuildContext context, MembershipPlan plan, AppLocalizations l, {String? discountLabel}) {
    final isSelected = _selectedPremiumPlanId == plan.id;
    final isYearly = plan.planType == MembershipPlanType.yearly;
    final isCurrentFromServer = _hasActiveSubscription &&
        ((_activePlan == 'monthly' && plan.planType == MembershipPlanType.monthly) ||
            (_activePlan == 'yearly' && plan.planType == MembershipPlanType.yearly));

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPremiumPlanId = plan.id;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
              : null,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: plan.id,
              groupValue: _selectedPremiumPlanId,
              onChanged: (v) {
                if (v != null) setState(() => _selectedPremiumPlanId = v);
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isYearly ? l.membershipPlanYearly : l.membershipPlanMonthly,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isCurrentFromServer)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l.membershipPlanCurrent,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isYearly && discountLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        discountLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (isYearly)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.membershipBadgeRecommended,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              plan.displayPrice ?? '--',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQSection() {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.membershipFaqTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text(l.membershipFaqCancelTitle),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.membershipFaqCancelContent,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text(l.membershipFaqEffectTitle),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.membershipFaqEffectContent,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showUpgradeDialog() {
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.membershipDialogUpgradeTitle),
        content: Text(l.membershipDialogUpgradeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.membershipDialogLater),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(l.membershipButtonUpgrade),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases({
    bool showSnackbars = true,
    bool showButtonLoading = true,
  }) async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);
    setState(() => _isRestoreButtonLoading = showButtonLoading);
    final l = AppLocalizations.of(context);
    _restoreVerifiedEntitlement = false;
    _restoreSettleTimer?.cancel();
    _restoreLatestRestoredPurchase = null;
    _restoreLatestRestoredTxMs = -1;
    _restoreVerificationCompleter = Completer<void>();
    _restoreGotRestoredEventCompleter = Completer<void>();
    try {
      if (mounted) {
        if (showSnackbars) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.membershipRestoreStarting)),
          );
        }
      }

      await AppEnv.iap.restore();

      if (!mounted) return;

      // iOS Restore 可能会吐出大量 restored 历史交易。
      // 先判断是否“确实有 restored 事件”，再等待“首次找到有效订阅”并完成验证（或超时）。
      var hasRestoredEvent = false;
      try {
        await _restoreGotRestoredEventCompleter!.future
            .timeout(const Duration(seconds: 5));
        hasRestoredEvent = true;
      } on TimeoutException {
        hasRestoredEvent = false;
      }

      if (!hasRestoredEvent) {
        if (!mounted) return;
        if (showSnackbars) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.membershipRestoreNoPurchases)),
          );
        }
        return;
      }

      try {
        await _restoreVerificationCompleter!.future
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // restored 有很多，但没有找到“有效订阅”；这里不报 “no purchases”，让 _checkStatus 用服务器兜底。
      }

      final showedExpiredSnack =
          await _checkStatus(showExpiredHint: showSnackbars);

      // 手动恢复：给用户明确结果（成功 / 无有效会员 / 已过期由 _checkStatus 提示）
      if (mounted && showSnackbars) {
        if (_isCurrentlyMember) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.membershipRestoreSuccess)),
          );
        } else if (hasRestoredEvent && !showedExpiredSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.membershipRestoreSyncedNoMembership)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (showSnackbars) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.membershipRestoreFailed)),
          );
        }
      }
    } finally {
      _restoreSettleTimer?.cancel();
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _isRestoreButtonLoading = false;
        });
      }
    }
  }

  void _subscribeToPlan(MembershipPlan plan) {
    final l = AppLocalizations.of(context);

    // Debounce rapid repeat taps.
    final now = DateTime.now();
    if (_lastBuyTapAt != null &&
        now.difference(_lastBuyTapAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastBuyTapAt = now;

    // —— 微信支付模式：不走商店 IAP，走服务端创建订单 ——
    // 在最前面判断，这样既不会因为 product == null（因为根本没走 IAP 查询）而报错，
    // 也不会进入到 IAP 的 pending 校验逻辑（微信用自己的 debounce 机制）。
    if (AppEnv.iap.isThirdPartyPaymentEnabled) {
      _subscribeWechat(plan);
      return;
    }

    final productId = plan.productId;
    final product = productId == null ? null : AppEnv.iap.getProduct(productId);

    // Debounce if StoreKit/Play reports a pending transaction for this product.
    if (productId != null) {
      final until = _pendingProductUntil[productId];
      if (until != null && until.isAfter(DateTime.now())) {
        _showSnackBarSafe(SnackBar(content: Text(l.membershipDialogProcessing)));
        return;
      }
    }

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.membershipDialogSubscribeContent)),
      );
      return;
    }

    // Cross-platform active subscription: do not allow purchasing on the other platform.
    final currentPlatform = Platform.isIOS ? 'ios' : 'android';
    final isCrossPlatformActive =
        _hasActiveSubscription && _activePlatform != null && _activePlatform != currentPlatform;
    if (isCrossPlatformActive) {
      final crossMsg = currentPlatform == 'android'
          ? l.membershipCrossPlatformManageOnIOS
          : l.membershipCrossPlatformManageOnAndroid;
      _showSnackBarSafe(SnackBar(content: Text(crossMsg)));
      return;
    }

    final isCurrentPlanFromServer = _hasActiveSubscription &&
        ((_activePlan == 'monthly' && plan.planType == MembershipPlanType.monthly) ||
            (_activePlan == 'yearly' && plan.planType == MembershipPlanType.yearly));

    // 已订阅：
    // - 点当前套餐：不再重复购买（避免 StoreKit/Play 报错）
    // - 点另一个套餐：在 App 内发起切换（iOS 同组订阅可直接切换；Android 用订阅替换参数）
    if (_hasActiveSubscription) {
      if (isCurrentPlanFromServer) {
        _showSnackBarSafe(SnackBar(content: Text(l.membershipPlanCurrent)));
        return;
      }

      // 切换套餐确认
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.membershipDialogSubscribeTitle),
          content: Text(l.membershipDialogSubscribeContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (!mounted) return;
                setState(() => _isPurchasing = true);
                _userInitiatedPurchaseFlow = true;

                _showSnackBarSafe(
                  SnackBar(content: Text('${l.membershipDialogProcessing} ${product.title}')),
                );

                try {
                  if (Platform.isAndroid && product.id == 'rephone_pro') {
                    _pendingAndroidBasePlanId = plan.basePlanId;
                  } else {
                    _pendingAndroidBasePlanId = null;
                  }
                await AppEnv.iap.buy(
                  product,
                  offerToken: plan.offerToken,
                  // 已过期/无权益：勿传订阅替换，否则 Play 可能对「重购同档」返回 ERROR(6)
                  skipAndroidSubscriptionReplacement: !_hasActiveSubscription,
                );
                } catch (_) {
                  if (!mounted) return;
                  setState(() => _isPurchasing = false);
                  _showSnackBarSafe(SnackBar(content: Text(l.membershipPurchaseFailed)));
                }
              },
              child: Text(l.commonConfirm),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.membershipDialogSubscribeTitle),
        content: Text(l.membershipDialogSubscribeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel),
          ),
          ElevatedButton(
            onPressed: _isPurchasing
                ? null
                : () async {
              Navigator.pop(context);
              if (!mounted) return;
              setState(() => _isPurchasing = true);
              _userInitiatedPurchaseFlow = true;

              // 购买前不再额外调用 restore()：
              // restored 在 iOS 沙盒/历史较多时会产生大量回调，容易触发重复后端校验。
              // 本页 initState 已做一次 restore，最终权益以服务端 refresh 结果为准。

              if (!mounted) return;
              if (_hasActiveSubscription) {
                setState(() => _isPurchasing = false);
                _showSnackBarSafe(SnackBar(content: Text(l.membershipStatusPremium)));
                return;
              }

              _showSnackBarSafe(
                SnackBar(content: Text('${l.membershipDialogProcessing} ${product.title}')),
              );
              try {
                if (Platform.isAndroid && product.id == 'rephone_pro') {
                  _pendingAndroidBasePlanId = plan.basePlanId;
                } else {
                  _pendingAndroidBasePlanId = null;
                }
                await AppEnv.iap.buy(
                  product,
                  offerToken: plan.offerToken,
                  skipAndroidSubscriptionReplacement: !_hasActiveSubscription,
                );
              } catch (e) {
                if (mounted) {
                  setState(() => _isPurchasing = false);
                  _showSnackBarSafe(SnackBar(content: Text(l.membershipPurchaseFailed)));
                }
              }
            },
            child: Text(l.commonConfirm),
          ),
        ],
      ),
    );
  }

  /// 微信 APP 支付：订阅套餐（月/年）的完整购买流程。
  ///
  /// 流程：
  ///   1. 前置校验：登录态、当前套餐、跨平台互斥、正在购买中、基础套餐等。
  ///   2. 弹确认对话框，用户确认后标记 `_isPurchasing=true`。
  ///   3. 调用 [IapService.createServerOrder] → 后端创建微信预支付订单 →
  ///      内部直接调起微信 SDK 支付，等待 SDK 回调结果。
  ///   4. 只要 SDK 返回成功（errCode==0），立即调用 `/wechat/verify`
  ///      让服务端主动查单并加速发放权益（notify 回调可能会有延迟或丢包）。
  ///   5. 兜底：不论 verify 成功与否，用 `/wechat/query` 做最多 8 次退避轮询（~30s）
  ///      确保 notify 丢包场景下权益仍会到账。
  ///   6. 最终 `_checkStatus()` 刷新本地用户状态 + 展示成功/失败提示。
  ///
  /// 注意：此方法是「异步 void」设计（与老的 `_subscribeToPlan` 保持一致），
  /// 内部通过 `setState` + `_showSnackBarSafe` 与 UI 交互，调用方不 await。
  Future<void> _subscribeWechat(MembershipPlan plan) async {
    final l = AppLocalizations.of(context);

    // 1. 基础校验：禁止购买基础套餐
    if (plan.planType == MembershipPlanType.basic) {
      _showSnackBarSafe(SnackBar(content: Text(l.membershipPlanCurrent)));
      return;
    }

    // 2. 登录校验：微信支付必须绑定账号，否则无法发权益
    final user = await SessionManager.getUser();
    if (user == null) {
      _showSnackBarSafe(SnackBar(content: Text(l.membershipPleaseLogin)));
      return;
    }

    // 3. 正在购买中：互斥（避免重复点击 → 生成多个 out_trade_no）
    if (_isPurchasing) {
      _showSnackBarSafe(SnackBar(content: Text(l.membershipDialogProcessing)));
      return;
    }

    // 4. 跨平台订阅互斥：
    //    如果当前账号已通过海外 IAP（ios/android）购买过，
    //    不要在微信侧再次发起支付（否则同档双付但只续其中一个平台，易产生纠纷）。
    if (_hasActiveSubscription &&
        _activePlatform != null &&
        _activePlatform != 'wechat') {
      final crossMsg = _activePlatform == 'ios'
          ? l.membershipCrossPlatformManageOnIOS
          : l.membershipCrossPlatformManageOnAndroid;
      _showSnackBarSafe(SnackBar(content: Text(crossMsg)));
      return;
    }

    // 5. 同平台已是当前套餐：禁止重复
    final isCurrentPlanFromServer = _hasActiveSubscription &&
        _activePlatform == 'wechat' &&
        ((_activePlan == 'monthly' && plan.planType == MembershipPlanType.monthly) ||
            (_activePlan == 'yearly' && plan.planType == MembershipPlanType.yearly));
    if (isCurrentPlanFromServer) {
      _showSnackBarSafe(SnackBar(content: Text(l.membershipPlanCurrent)));
      return;
    }

    final planLabel = plan.planType == MembershipPlanType.monthly
        ? l.membershipPlanMonthlyShort
        : l.membershipPlanYearlyShort;
    final sku = plan.planType == MembershipPlanType.monthly
        ? 'rephone_premium_monthly'
        : 'rephone_premium_yearly';
    final planStr = plan.planType == MembershipPlanType.monthly ? 'monthly' : 'yearly';

    // 6. 购买确认弹框（与 IAP 风格保持一致）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.membershipDialogSubscribeTitle),
        content: Text(l.membershipDialogSubscribeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isPurchasing = true;
      _userInitiatedPurchaseFlow = true;
    });
    _showSnackBarSafe(
      SnackBar(content: Text('${l.membershipDialogProcessing} $planLabel')),
    );

    String? outTradeNo;
    bool entitlementOk = false;
    Object? lastErr;
    try {
      // 7. 服务端创建订单 + 内部自动调起微信 SDK
      final orderResult = await AppEnv.iap.createServerOrder(
        sku: sku,
        plan: planStr,
        email: user.email,
      );
      outTradeNo = orderResult?['out_trade_no'] as String?;
      final sdkSuccess = orderResult?['sdk_success'] as bool? ?? false;
      if (outTradeNo == null) {
        throw StateError('创建订单失败：服务端未返回订单号');
      }

      // 8. SDK 成功 → 立即 notifyServerOrderPaid（调 /wechat/verify）
      if (sdkSuccess) {
        final ok = await AppEnv.iap.notifyServerOrderPaid(
          outTradeNo,
          email: user.email,
        );
        if (ok) {
          entitlementOk = true;
        }
      }

      // 9. 兜底：不论 SDK / verify 结果，都用 query 轮询 ~30s 确认真实支付状态。
      //    覆盖场景：
      //    - SDK 回调丢失/超时，但用户实际已支付成功
      //    - notify 回调丢包，verify 时微信还没来得及更新订单状态
      //    - 用户取消后 10 秒重新支付（不会，因为 debounce + _isPurchasing）
      if (!entitlementOk) {
        entitlementOk = await AppEnv.iap.queryServerOrderStatus(
          outTradeNo,
          email: user.email,
        );
      }
    } catch (e, st) {
      lastErr = e;
      debugPrint('[MembershipPage] _subscribeWechat error: $e $st');
    } finally {
      // 10. 刷新服务端权益状态（即使认为成功也刷一次，保证最终一致）
      try {
        await _checkStatus();
      } catch (_) {
        // ignore
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isPurchasing = false;
        _userInitiatedPurchaseFlow = false;
      });

      // 11. UI 结果提示
      final isNowMember = _hasActiveSubscription || _isCurrentlyMember;
      if (entitlementOk || isNowMember) {
        // 已切换套餐
        final nowActivePlan = _activePlan;
        if (nowActivePlan != null && nowActivePlan != planStr) {
          _showPurchaseOutcomeSnackBar(
            SnackBar(
              content: Text(l.membershipPurchaseSuccessSwitchPending),
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          _showPurchaseOutcomeSnackBar(
            SnackBar(content: Text(l.membershipPurchaseSuccess)),
          );
        }
      } else {
        // 失败：给出具体原因（如果异常包含 message）
        final String msg;
        if (lastErr != null) {
          final errStr = lastErr.toString();
          if (errStr.contains('创建订单失败') ||
              errStr.contains('订单号') ||
              errStr.isNotEmpty) {
            msg = '${l.membershipPurchaseFailed}：$errStr';
          } else {
            msg = l.membershipPurchaseFailed;
          }
        } else {
          msg = l.membershipPurchaseFailed;
        }
        _showPurchaseOutcomeSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }
}

enum MembershipPlanType { basic, monthly, yearly }

class MembershipPlan {
  final String id;
  final MembershipPlanType planType;
  final double? price;
  final bool isRecommended;
  final bool isCurrentPlan;
  final String? productId;
  final String? basePlanId; // New: for Google Play Billing 5+
  final String? offerToken; // New: for Google Play Billing 5+
  final String? displayPrice;

  MembershipPlan({
    required this.id,
    required this.planType,
    required this.price,
    required this.isRecommended,
    required this.isCurrentPlan,
    this.productId,
    this.basePlanId,
    this.offerToken,
    this.displayPrice,
  });

  bool get isFree => price == null || price == 0;

  MembershipPlan copyWith({
    double? price,
    String? displayPrice,
    bool? isCurrentPlan,
    bool? isRecommended,
    String? productId,
    String? offerToken,
  }) {
    return MembershipPlan(
      id: id,
      planType: planType,
      price: price ?? this.price,
      isRecommended: isRecommended ?? this.isRecommended,
      isCurrentPlan: isCurrentPlan ?? this.isCurrentPlan,
      productId: productId ?? this.productId,
      basePlanId: basePlanId,
      offerToken: offerToken ?? this.offerToken,
      displayPrice: displayPrice ?? this.displayPrice,
    );
  }
}

/// 从 IAP 价格字符串解析数值（去掉货币符号等）
double? _parsePriceFromDisplay(String? displayPrice) {
  if (displayPrice == null || displayPrice.isEmpty) return null;
  final cleaned = displayPrice.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
  return double.tryParse(cleaned);
}

List<Widget> _buildFeatureWidgets(MembershipPlan plan, AppLocalizations l) {
  final featureKeys = plan.planType == MembershipPlanType.basic
      ? [
          'membershipFeatureNoDeviceLimit',
          'membershipFeatureBasicCloudImages',
          'membershipFeatureLiveStreaming',
        ]
      : [
          'membershipFeatureNoDeviceLimit',
          'membershipFeatureProCloudPlayback',
          'membershipFeatureLiveStreaming',
          'membershipFeatureNoAds',
        ];

  return featureKeys
      .map(
        (key) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(l.tr(key))),
            ],
          ),
        ),
      )
      .toList();
}
