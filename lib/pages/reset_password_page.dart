import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_api.dart';
import '../services/session_manager.dart';
import '../utils/log_utils.dart';
import '../utils/password_validator.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _currentUserEmail;
  PasswordStrength _strength = PasswordStrength.weak;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
    _newPasswordController.addListener(_updateStrength);
  }

  void _updateStrength() {
    setState(() {
      _strength = PasswordValidator.checkStrength(_newPasswordController.text);
    });
  }

  Future<void> _loadUserEmail() async {
    final user = await SessionManager.getUser();
    if (mounted) {
      setState(() {
        _currentUserEmail = user?.email;
      });
    }
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentUserEmail == null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.tr('resetPasswordLoadUserFailed'))),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authApi = AuthApi();
      await authApi.resetPassword(
        email: _currentUserEmail!,
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      
      LogUtils.i('ResetPassword', 'Password reset successfully for: $_currentUserEmail');
      
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.resetPasswordSuccess)),
      );
      
      Navigator.of(context).pop();
    } catch (e) {
      LogUtils.e('ResetPassword', 'Failed to reset password', e);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.tr('resetPasswordFailed')}: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_updateStrength);
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.resetPasswordTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _oldPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.resetPasswordOld,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.tr('resetPasswordOldEmpty');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.resetPasswordNew,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                ),
                validator: (value) {
                  return PasswordValidator.validate(value, l);
                },
              ),
              if (_newPasswordController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _strength == PasswordStrength.weak
                      ? 0.33
                      : (_strength == PasswordStrength.medium ? 0.66 : 1.0),
                  color: _strength == PasswordStrength.weak
                      ? Colors.red
                      : (_strength == PasswordStrength.medium
                          ? Colors.orange
                          : Colors.green),
                  backgroundColor: Colors.grey[200],
                ),
                const SizedBox(height: 4),
                Text(
                  PasswordValidator.getStrengthText(_strength, l),
                  style: TextStyle(
                    color: _strength == PasswordStrength.weak
                        ? Colors.red
                        : (_strength == PasswordStrength.medium
                            ? Colors.orange
                            : Colors.green),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.resetPasswordConfirm,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.tr('resetPasswordConfirmEmpty');
                  }
                  if (value != _newPasswordController.text) {
                    return l.tr('resetPasswordNotMatch');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleResetPassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l.resetPasswordSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
