import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import '../pages/welcome_page.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _isDialogShowing = false;

  static void handleUnauthorized() {
    if (_isDialogShowing) return;
    
    final context = navigatorKey.currentContext;
    if (context == null) return;

    _isDialogShowing = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text('Your session has expired. Please log in again.'),
        actions: [
          TextButton(
            onPressed: () async {
              _isDialogShowing = false;
              // Close the dialog
              Navigator.of(context).pop();
              
              // Clear session
              await SessionManager.clear();
              
              // Navigate to WelcomePage
              // Using pushAndRemoveUntil to remove all previous routes
              Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      // Ensure flag is reset if dialog is dismissed by other means (though barrierDismissible is false)
      _isDialogShowing = false;
    });
  }
}
