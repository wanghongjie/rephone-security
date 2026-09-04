import 'package:flutter/material.dart';

import '../flavors/app_env.dart';
import '../flavors/env_config.dart';
import '../l10n/app_localizations.dart';
import '../pages/webview_page.dart';

/// 登录/注册页底部的「我已阅读并同意《服务条款》和《隐私协议》」勾选框。
///
/// - 默认不勾选，由父页面在提交前通过 [value] 判断并提示；
/// - 勾选框与协议文字联动，点击协议链接可在 WebView 中查看全文。
class AgreementCheckbox extends StatelessWidget {
  const AgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 当前是否已勾选。
  final bool value;

  /// 勾选状态变化回调。
  final ValueChanged<bool> onChanged;

  /// 服务条款全文地址（与 AuthPage 保持一致）。
  static String termsUrl(BuildContext context) {
    final isChina = AppEnv.config.market == Market.china;
    final lang = Localizations.localeOf(context).languageCode;
    return isChina
        ? 'https://rephone.top/terms_china.html'
        : (lang == 'en'
            ? 'https://rephone.top/terms_us.html'
            : 'https://rephone.top/terms.html');
  }

  /// 隐私政策全文地址（与 AuthPage / About 页保持一致）。
  static String privacyUrl(BuildContext context) {
    final isChina = AppEnv.config.market == Market.china;
    final lang = Localizations.localeOf(context).languageCode;
    return isChina
        ? 'https://rephone.top/privacy_china.html'
        : (lang == 'en'
            ? 'https://rephone.top/privacy_us.html'
            : 'https://rephone.top/privacy.html');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      fontSize: theme.textTheme.bodySmall?.fontSize,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: theme.colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                  height: 1.5,
                ),
                children: [
                  TextSpan(text: l.authCheckAgreePrefix),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => _openTerms(context),
                      child: Text(l.authTermsLink, style: linkStyle),
                    ),
                  ),
                  TextSpan(text: l.authCheckAgreeAnd),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => _openPrivacy(context),
                      child: Text(l.authPrivacyLink, style: linkStyle),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openTerms(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewPage(
          title: AppLocalizations.of(context).authTermsLink,
          url: termsUrl(context),
        ),
      ),
    );
  }

  void _openPrivacy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewPage(
          title: AppLocalizations.of(context).authPrivacyLink,
          url: privacyUrl(context),
        ),
      ),
    );
  }
}
