import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/ble/typing_done_prefs.dart';
import 'app_toast.dart';

/// 触发“文字打完”提醒。按用户偏好执行应用内通知 / 震动。
/// systemBanner 尚未接入（需本地通知插件），此处忽略。
Future<void> notifyTypingDone(BuildContext context, TypingDonePrefs prefs) async {
  if (prefs.vibrate) {
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
  if (prefs.inAppNotify && context.mounted) {
    showSuccessToast(context, '文字已打完');
  }
}
