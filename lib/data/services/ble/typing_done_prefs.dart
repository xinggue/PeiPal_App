/// “文字打完”提醒偏好。
///
/// systemBanner 目前预留（需本地通知插件，尚未接入），先只做
/// inAppNotify（应用内 SnackBar）与 vibrate（震动）。
class TypingDonePrefs {
  final bool systemBanner;
  final bool inAppNotify;
  final bool vibrate;

  const TypingDonePrefs({
    this.systemBanner = false,
    this.inAppNotify = false,
    this.vibrate = false,
  });

  static TypingDonePrefs parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const TypingDonePrefs();
    final set = raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    return TypingDonePrefs(
      systemBanner: set.contains('system'),
      inAppNotify: set.contains('inapp'),
      vibrate: set.contains('vibrate'),
    );
  }

  String get code => [
        if (systemBanner) 'system',
        if (inAppNotify) 'inapp',
        if (vibrate) 'vibrate',
      ].join(',');

  TypingDonePrefs copyWith({
    bool? systemBanner,
    bool? inAppNotify,
    bool? vibrate,
  }) =>
      TypingDonePrefs(
        systemBanner: systemBanner ?? this.systemBanner,
        inAppNotify: inAppNotify ?? this.inAppNotify,
        vibrate: vibrate ?? this.vibrate,
      );
}
