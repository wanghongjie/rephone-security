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
  });

  final String codeId;
  final double widthDp;
  final int widthPx;
  final int heightPx;
  final double heightDp;

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
