import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PangleBannerView extends StatelessWidget {
  const PangleBannerView({
    super.key,
    required this.codeId,
    required this.widthDp,
    required this.widthPx,
    required this.heightPx,
    required this.heightDp,
    this.onPlatformViewCreated,
  });

  final String codeId;
  final double widthDp;
  final int widthPx;
  final int heightPx;
  final double heightDp;

  /// AndroidView 创建完成回调；原生端用户关闭广告后会通过同名 viewId 的
  /// `rephone/pangle_banner_<viewId>` MethodChannel 推送 `onAdClosed` 事件。
  final ValueChanged<int>? onPlatformViewCreated;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return SizedBox(width: widthDp, height: heightDp);
    }
    return Center(
      child: SizedBox(
        width: widthDp,
        height: heightDp,
        child: AndroidView(
          viewType: 'pangle_banner_view',
          onPlatformViewCreated: onPlatformViewCreated,
          creationParams: <String, dynamic>{
            'codeId': codeId,
            'widthPx': widthPx,
            'heightPx': heightPx,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
  }
}
