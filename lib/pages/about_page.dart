import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'webview_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _termsUrl = 'https://rephone-h5.pages.dev/terms.html';
  static const String _privacyUrl = 'https://rephone-h5.pages.dev/privacy.html';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.aboutTitle),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(l.aboutTerms),
                  subtitle: Text(l.aboutView),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WebViewPage(
                          title: '服务条款',
                          url: _termsUrl,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l.aboutPrivacy),
                  subtitle: Text(l.aboutView),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WebViewPage(
                          title: '隐私协议',
                          url: _privacyUrl,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
