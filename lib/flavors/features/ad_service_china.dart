import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../widgets/pangle_banner_view.dart';
import '../service_facades.dart';

/// 国内版广告实现：优先 Pangle（穿山甲）PlatformView；否则返回空占位。
///
/// - FeatureToggles.enablePangleAds=true 时：返回 [PangleBannerView]
/// - 否则：返回空 SizedBox
///
/// Pangle 位 ID（codeId）映射：
/// - 每个 placement（页面/场景）在内部持有独立的穿山甲 codeId
/// - 如某 placement 尚未在 Pangle 后台配置独立位，会回退到全局默认 ID
///   （[_kDefaultPangleCodeId]，与 Android src/china 默认值保持一致）
///
/// 注：本文件只应被 `main_china.dart`（国内入口）import；
/// 海外入口 `main.dart` 不得引用本文件，从而不会带上 Pangle 相关类型。
class ChinaPangleAdService implements AdService {
  final bool _enablePangle;

  /// Pangle Banner 广告位 ID 默认值（国内）；与 Android src/china
  /// `PangleBannerPlatformView` 兜底默认值保持一致。
  static const String _kDefaultPangleCodeId = '104032066';

  /// Banner 常规尺寸：兜底值，当无法获取到 MediaQuery 时使用（一般不会触发）。
  static const double _kBannerDefaultWidthDp = 320;
  static const double _kBannerDefaultHeightDp = 160; // 2:1，与 _computePangleBannerSize 对齐

  /// 按 placement 拆分的 Pangle codeId 映射。
  ///
  /// 说明：
  /// - 若 Pangle 后台已经给每个页面分配独立 codeId，直接改这里即可，
  ///   无需修改任何业务页面。
  /// - 为避免回退逻辑被错误覆盖，**未配置新 ID 前请保持为 null**，
  ///   实现会自动使用 [_kDefaultPangleCodeId]。
  static const Map<String, String?> _placementCodeId = <String, String?>{
    AdPlacement.profile: null,
    AdPlacement.cameraList: '104032066',
    AdPlacement.cameraEndpoint: null,
  };

  /// 构造：传 [FeatureToggles.enablePangleAds]。
  const ChinaPangleAdService({bool enablePangle = true})
      : _enablePangle = enablePangle;

  @override
  Future<void> init() async {
    // Pangle SDK 初始化由 MediationService.initSdkIfNeeded 在入口统一触发。
  }

  @override
  bool get bannerEnabled => _enablePangle;

  /// 取当前 placement 对应的 Pangle codeId；
  /// 未配置则返回全局默认 [_kDefaultPangleCodeId]。
  String resolveCodeId(String? placement) {
    final id = _placementCodeId[placement];
    if (id != null && id.isNotEmpty) return id;
    return _kDefaultPangleCodeId;
  }

  /// 按 Pangle 原生 Banner 约束计算真实渲染尺寸（像素 + dp 对齐）。
  ///
  /// 原算法来自 `camera_list_page.dart`，收拢到这里避免业务页面散写像素换算逻辑：
  /// - 宽度：扣除左右 padding，再减 32dp 外间距，上限 300dp，最小 0
  /// - 高度：按 2:1（宽度一半）保证 Banner 比例，防止穿山甲因比例异常不填充
  /// - 像素：按 devicePixelRatio 换算后，限制在 [1, 1200] / [1, 600]，避免大屏越界
  ({double widthDp, int widthPx, int heightPx, double heightDp})
      _computePangleBannerSize(MediaQueryData media) {
    final usableWidthDp =
        media.size.width - media.padding.left - media.padding.right;
    final bannerWidthDp =
        (usableWidthDp - 32).clamp(0.0, 300.0).toDouble();
    final widthDp = bannerWidthDp > 0
        ? bannerWidthDp
        : usableWidthDp.clamp(0.0, 300.0).toDouble();
    final heightDp = widthDp / 2;
    final widthPx = (widthDp * media.devicePixelRatio).round().clamp(1, 1200);
    final heightPx = (heightDp * media.devicePixelRatio).round().clamp(1, 600);
    return (
      widthDp: widthDp,
      widthPx: widthPx,
      heightPx: heightPx,
      heightDp: heightDp,
    );
  }

  @override
  Widget buildBanner(BuildContext context, {String? placement}) {
    if (!bannerEnabled) return const SizedBox.shrink();
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final codeId = resolveCodeId(placement);
    final media = MediaQuery.maybeOf(context);
    final size = media != null
        ? _computePangleBannerSize(media)
        : (
            widthDp: _kBannerDefaultWidthDp,
            widthPx: (_kBannerDefaultWidthDp * WidgetsBinding
                        .instance.platformDispatcher.views.first.devicePixelRatio)
                    .round()
                    .clamp(1, 1200),
            heightPx: (_kBannerDefaultHeightDp * WidgetsBinding
                        .instance.platformDispatcher.views.first.devicePixelRatio)
                    .round()
                    .clamp(1, 600),
            heightDp: _kBannerDefaultHeightDp,
          );
    return SafeArea(
      top: false,
      child: SizedBox(
        height: size.heightDp,
        child: PangleBannerView(
          codeId: codeId,
          widthDp: size.widthDp,
          widthPx: size.widthPx,
          heightPx: size.heightPx,
          heightDp: size.heightDp,
        ),
      ),
    );
  }
}
