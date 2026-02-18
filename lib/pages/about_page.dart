import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'webview_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
                    final lang = Localizations.localeOf(context).languageCode;
                    final url = lang == 'en'
                        ? 'https://rephone.top/terms_us.html'
                        : 'https://rephone.top/terms.html';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WebViewPage(
                          title: l.aboutTerms,
                          url: url,
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
                    final lang = Localizations.localeOf(context).languageCode;
                    final url = lang == 'en'
                        ? 'https://rephone.top/privacy_us.html'
                        : 'https://rephone.top/privacy.html';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WebViewPage(
                          title: l.aboutPrivacy,
                          url: url,
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
