import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/session_manager.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _isDialogShowing = false;

  static void handleUnauthorized() {
    if (_isDialogShowing) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _isDialogShowing = true;
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.sessionExpiredTitle),
        content: Text(l.sessionExpiredContent),
        actions: [
          TextButton(
            onPressed: () async {
              _isDialogShowing = false;
              Navigator.of(dialogContext).pop();
              await SessionManager.clear();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pushNamedAndRemoveUntil('/welcome', (route) => false);
              }
            },
            child: Text(l.commonOk),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
  }
}
