import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../utils/app_market.dart';
import '../../../utils/log_utils.dart';
import '../service_facades.dart';

const String _kTag = 'GlobalAdMobService';

/// 海外版广告实现：基于 Google Mobile Ads，封装各页面通用的横幅广告。
///
/// 业务页面统一调用 `AppEnv.ads.buildBanner(context, placement: AdPlacement.xxx)`，
/// 无需感知 BannerAd / AdRequest / AdWidget 等具体类型，也无需散写 Ad Unit ID。
///
/// Ad Unit ID 映射：
/// - 每个 placement（页面/场景）在内部持有一条独立的 AdMob Ad Unit ID
///   （Android/iOS 各一条 × debug/release 各一条）
/// - 如某 placement 尚未在 AdMob 后台配置独立 ID，会回退到全局默认 ID
///   （`_defaultAdUnits`），确保不会因缺 ID 崩溃。
///
/// 注：本文件只应被 `main.dart`（海外入口）import；
/// 国内入口 `main_china.dart` 不得引用本文件，从而不会带上 Google Mobile Ads。
class GlobalAdMobService implements AdService {
  final bool _enabled;
  final String _testDeviceId;

  /// AdMob 横幅 Ad Unit ID 集合：debug/release × Android/iOS。
  static const _AdUnits _defaultAdUnits = _AdUnits(
    androidRelease: 'ca-app-pub-6709616886871539/6420803882',
    androidDebug: 'ca-app-pub-3940256099942544/6300978111',
    iosRelease: 'ca-app-pub-6709616886871539/8914838386',
    iosDebug: 'ca-app-pub-3940256099942544/2934735716',
  );

  /// 按页面/场景拆分的 AdMob Banner 位 ID 映射。
  ///
  /// 说明：
  /// - 如果 AdMob 后台已经给每个页面分配了独立 ID，直接改这里即可，
  ///   无需修改任何业务页面。
  /// - 为避免回退逻辑被错误覆盖，**未配置新 ID 前请保持为 null**，
  ///   实现会自动使用 [_defaultAdUnits]。
  static const Map<String, _AdUnits> _placementAdUnits =
      <String, _AdUnits>{
    AdPlacement.profile: _AdUnits(
      androidRelease: 'ca-app-pub-6709616886871539/6420803882',
      androidDebug: 'ca-app-pub-3940256099942544/6300978111',
      iosRelease: 'ca-app-pub-6709616886871539/8914838386',
      iosDebug: 'ca-app-pub-3940256099942544/2934735716',
    ),
    AdPlacement.cameraList: _AdUnits(
      androidRelease: 'ca-app-pub-6709616886871539/3198659691',
      androidDebug: 'ca-app-pub-3940256099942544/9214589741',
      iosRelease: 'ca-app-pub-6709616886871539/9894245770',
      iosDebug: 'ca-app-pub-3940256099942544/2435281174',
    ),
    AdPlacement.cameraEndpoint: _AdUnits(
      androidRelease: 'ca-app-pub-6709616886871539/4916851224',
      androidDebug: 'ca-app-pub-3940256099942544/9214589741',
      iosRelease: 'ca-app-pub-6709616886871539/3662511708',
      iosDebug: 'ca-app-pub-3940256099942544/2435281174',
    ),
  };

  /// 构造海外版 AdMob 服务。
  ///
  /// - [enabled]：是否启用（一般与 [FeatureToggles.enableGoogleMobileAds] 一致）
  /// - [testDeviceId]：GMA 的测试设备 ID，发布包可传空字符串使用默认。
  const GlobalAdMobService({
    bool enabled = true,
    String testDeviceId = '32269ED36C964717F118F673D33C50C3',
  })  : _enabled = enabled,
        _testDeviceId = testDeviceId;

  @override
  bool get bannerEnabled => _enabled && AppMarket.adMobEnabled;

  @override
  Future<void> init() async {
    if (!bannerEnabled) return;
    await MobileAds.instance.initialize();
    if (_testDeviceId.isNotEmpty) {
      try {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: <String>[_testDeviceId]),
        );
      } catch (e, st) {
        LogUtils.w(_kTag, 'updateRequestConfiguration failed: $e\n$st');
      }
    }
  }

  /// 取当前 placement 对应的 AdMob Ad Unit ID。
  ///
  /// - 当 [placement] 未传或在 [_placementAdUnits] 中未找到有效 ID 时：
  ///   回退到 [_defaultAdUnits]，避免 SDK 因空字符串崩溃。
  String resolveAdUnitId(String? placement) {
    final units = _placementAdUnits[placement] ?? _defaultAdUnits;
    return units.pickCurrent() ?? _defaultAdUnits.pickCurrent()!;
  }

  @override
  Widget buildBanner(BuildContext context, {String? placement}) {
    if (!bannerEnabled) return const SizedBox.shrink();
    return _AdMobBannerWidget(
      adUnitId: resolveAdUnitId(placement),
    );
  }
}

/// 单个 placement 的 AdMob 横幅 Ad Unit ID 集合。
///
/// - Android/iOS 分开配置（AdMob 后台是按应用分位的）。
/// - debug/release 分开配置（debug 用官方 demo 位，避免无效展示/封禁）。
/// - 当某 4 个字段为 null 时，[pickCurrent] 会返回 null，由上层回退
///   到全局默认 ID。
class _AdUnits {
  final String? androidRelease;
  final String? androidDebug;
  final String? iosRelease;
  final String? iosDebug;

  const _AdUnits({
    this.androidRelease,
    this.androidDebug,
    this.iosRelease,
    this.iosDebug,
  });

  /// 根据当前 Platform 与 kReleaseMode 选择匹配的 Ad Unit ID；
  /// 如果对应字段为 null，则返回 null 让上层回退。
  String? pickCurrent() {
    final release = kReleaseMode;
    if (Platform.isAndroid) {
      return release ? androidRelease : androidDebug;
    }
    return release ? iosRelease : iosDebug;
  }
}

/// 单个 BannerAd 容器：负责生命周期（load / dispose / error 处理）。
class _AdMobBannerWidget extends StatefulWidget {
  const _AdMobBannerWidget({required this.adUnitId});

  final String adUnitId;

  @override
  State<_AdMobBannerWidget> createState() => _AdMobBannerWidgetState();
}

class _AdMobBannerWidgetState extends State<_AdMobBannerWidget> {
  BannerAd? _banner;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (a) {
          if (!mounted) {
            a.dispose();
            return;
          }
          setState(() {
            _banner = a as BannerAd;
            _ready = true;
          });
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          LogUtils.w(
            _kTag,
            'BannerAd failed code=${e.code} msg=${e.message} '
            'domain=${e.domain} unit=${widget.adUnitId}',
          );
          if (!mounted) return;
          setState(() {
            _banner = null;
            _ready = false;
          });
        },
      ),
    );
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _banner;
    if (b == null || !_ready) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        width: b.size.width.toDouble(),
        height: b.size.height.toDouble(),
        child: AdWidget(ad: b),
      ),
    );
  }
}
