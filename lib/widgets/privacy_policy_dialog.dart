import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../pages/webview_page.dart';

/// 国内版首次启动的隐私政策弹窗。
///
/// - 提供明确的「同意 / 拒绝」两个按钮；
/// - 点击「查看完整隐私政策」可在 WebView 中阅读全文；
/// - 返回键与点击遮罩均不可关闭，必须做出选择。
class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  /// 国内版隐私政策全文地址（与 About 页保持一致）。
  static const String privacyUrl = 'https://rephone.top/privacy_china.html';

  /// 弹出隐私弹窗，返回用户是否同意（true = 同意）。
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PrivacyPolicyDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          l.privacyDialogTitle,
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.privacyDialogContent,
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => WebViewPage(
                          title: l.privacyDialogReadFull,
                          url: privacyUrl,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    l.privacyDialogReadFull,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.privacyDialogDisagree),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.privacyDialogAgree),
          ),
        ],
      ),
    );
  }
}
