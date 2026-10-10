import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/permission_kind.dart';

/// 权限用途告知弹窗（自定义弹窗）。
///
/// 合规要求：APP 向用户索取权限时，必须在**系统权限弹窗弹出之前**，
/// 通过自定义弹窗或蒙层同步告知索取权限的目的。
///
/// - 明确展示「使用目的」「涉及的信息」；
/// - 提供对等的「同意 / 暂不开启」两个按钮，拒绝后不影响其他功能使用；
/// - 返回 `true` 表示用户确认，此时才允许调用系统权限申请。
class PermissionRationaleDialog extends StatelessWidget {
  const PermissionRationaleDialog({super.key, required this.kind});

  final AppPermissionKind kind;

  /// 弹出权限用途告知弹窗，返回用户是否同意继续申请（true = 同意）。
  static Future<bool> show(BuildContext context, AppPermissionKind kind) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => PermissionRationaleDialog(kind: kind),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(PermissionKindText.icon(kind), color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              PermissionKindText.title(l, kind),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(text: l.permissionRationalePurpose),
            const SizedBox(height: 4),
            Text(
              PermissionKindText.purpose(l, kind),
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            _SectionLabel(text: l.permissionRationaleScope),
            const SizedBox(height: 4),
            Text(
              PermissionKindText.scope(l, kind),
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              l.permissionRationaleNote,
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.permissionRationaleDeny),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.permissionRationaleAllow),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
