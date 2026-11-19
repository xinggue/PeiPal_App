import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../repositories/settings_repository.dart';
import '../hub/hub_service.dart';
import '../logging/app_log_service.dart';

class TelemetryService {
  static const String enabledSettingsKey = 'telemetry_enabled';
  static const String lastPingDaySettingsKey = 'telemetry_last_ping_day';
  static const String _anonIdFileName = 'telemetry_anon_id';

  static const List<String> reportedFieldsDescription = [
    'anon_id（本地生成的随机匿名标识，不含设备序列号或账号）',
    'app_version（应用版本号）',
    'build_number（构建号）',
    'platform（操作系统类型，如 android / ios / macos / windows）',
    'os_version（系统版本简要信息）',
  ];

  final SettingsRepository _settingsRepo;
  final Dio _dio;
  final String _baseUrl;
  final Future<Directory> Function()? _supportDirProvider;
  final DateTime Function() _clock;
  final Future<PackageInfo> Function()? _packageInfoProvider;

  bool _inFlight = false;

  TelemetryService(
    this._settingsRepo, {
    Dio? dio,
    String baseUrl = HubService.defaultBaseUrl,
    this._supportDirProvider,
    DateTime Function()? clock,
    this._packageInfoProvider,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 5),
              ),
            ),
        _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _clock = clock ?? DateTime.now;

  Future<bool> isEnabled() async {
    final raw = await _settingsRepo.get(enabledSettingsKey);
    return raw != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    await _settingsRepo.set(enabledSettingsKey, enabled ? 'true' : 'false');
    AppLogService.instance.info('Telemetry', '匿名使用统计已${enabled ? '开启' : '关闭'}');
  }

  Future<String> _getOrCreateAnonId() async {
    final dir = _supportDirProvider != null
        ? await _supportDirProvider()
        : await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, _anonIdFileName));
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (Uuid.isValidUUID(fromString: existing)) {
        return existing;
      }
    }
    final fresh = const Uuid().v4();
    await file.writeAsString(fresh);
    return fresh;
  }

  String _currentPlatform() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem.toLowerCase();
  }

  String _sanitizeOsVersion() {
    if (kIsWeb) return 'web';
    final raw = Platform.operatingSystemVersion.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (raw.length <= 48) return raw;
    return raw.substring(0, 48);
  }

  /// 在已完成引导且用户允许时，每个自然日静默发送一次匿名使用统计。
  Future<bool> pingIfNeeded() async {
    if (_inFlight) return false;
    _inFlight = true;
    try {
      final onboarded = await _settingsRepo.get('onboarding_completed');
      if (onboarded != 'true') return false;

      if (!await isEnabled()) return false;

      final today = DateFormat('yyyy-MM-dd').format(_clock());
      final lastDay = await _settingsRepo.get(lastPingDaySettingsKey);
      if (lastDay == today) return false;

      final anonId = await _getOrCreateAnonId();
      var appVersion = '0.0.0';
      var buildNumber = '0';
      try {
        final info = _packageInfoProvider != null
            ? await _packageInfoProvider()
            : await PackageInfo.fromPlatform();
        if (info.version.isNotEmpty) appVersion = info.version;
        if (info.buildNumber.isNotEmpty) buildNumber = info.buildNumber;
      } catch (_) {}

      final payload = <String, dynamic>{
        'anon_id': anonId,
        'app_version': appVersion,
        'build_number': buildNumber,
        'platform': _currentPlatform(),
        'os_version': _sanitizeOsVersion(),
      };

      final res = await _dio.post<dynamic>(
        '$_baseUrl/v1/telemetry/ping',
        data: payload,
      );
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        await _settingsRepo.set(lastPingDaySettingsKey, today);
        return true;
      }
      return false;
    } catch (e) {
      AppLogService.instance.warn('Telemetry', '匿名心跳发送跳过: $e');
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
