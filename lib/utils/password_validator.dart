import 'package:rephone_security/l10n/app_localizations.dart';

enum PasswordStrength {
  weak,
  medium,
  strong,
}

class PasswordValidator {
  static PasswordStrength checkStrength(String password) {
    if (password.length < 8) return PasswordStrength.weak;

    bool hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
    bool hasDigit = password.contains(RegExp(r'[0-9]'));
    bool hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    if (hasLetter && hasDigit && hasSpecial) {
      return PasswordStrength.strong;
    } else if ((hasLetter && hasDigit) || (hasLetter && hasSpecial) || (hasDigit && hasSpecial)) {
      return PasswordStrength.medium;
    } else {
      return PasswordStrength.weak;
    }
  }

  static String? validate(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) {
      return l10n.passwordRequired;
    }

    if (value.length < 8) {
      return l10n.passwordRequirementLength;
    }

    bool hasLetter = value.contains(RegExp(r'[a-zA-Z]'));
    bool hasDigit = value.contains(RegExp(r'[0-9]'));
    
    // Require at least letters and numbers for a valid password
    if (!hasLetter || !hasDigit) {
       if (!hasLetter) return l10n.passwordRequirementLetter;
       if (!hasDigit) return l10n.passwordRequirementNumber;
    }

    return null; // Valid
  }
  
  static String getStrengthText(PasswordStrength strength, AppLocalizations l10n) {
    switch (strength) {
      case PasswordStrength.weak:
        return l10n.passwordStrengthWeak;
      case PasswordStrength.medium:
        return l10n.passwordStrengthMedium;
      case PasswordStrength.strong:
        return l10n.passwordStrengthStrong;
    }
  }
}
