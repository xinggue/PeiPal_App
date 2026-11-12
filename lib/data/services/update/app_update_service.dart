import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String? publishedAt;
  final String? downloadUrl;
  final String releasePageUrl;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    this.publishedAt,
    this.downloadUrl,
    required this.releasePageUrl,
  });
}

class AppUpdateService {
  static const String giteeRepo = 'xinggue/peipal_app';
  static const String githubRepo = 'xinggue/PeiPal_App';

  static Future<PackageInfo>? _packageInfoFuture;

  /// 读取当前安装包真实版本（失败时退回 0.0.0，避免展示错误的旧版本号）
  static Future<String> resolveCurrentVersion() async {
    try {
      final info = await (_packageInfoFuture ??= PackageInfo.fromPlatform());
      return info.version.isEmpty ? '0.0.0' : info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    headers: {'Accept': 'application/json'},
  ));

  /// 检测版本更新：优先 Gitee Releases 保证国内直连，失败回退 GitHub release-manifest
  static Future<AppUpdateInfo> checkForUpdate() async {
    final currentVersion = await resolveCurrentVersion();

    // 1. 优先尝试 Gitee API (国内直连)
    try {
      final res = await _dio.get(
        'https://gitee.com/api/v5/repos/$giteeRepo/releases/latest',
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        final tagName = (data['tag_name'] ?? data['name'] ?? '').toString().trim();
        final body = (data['body'] ?? '').toString().trim();
        final publishedAt = (data['created_at'] ?? '').toString().trim();

        String? downloadUrl;
        if (data['assets'] is List) {
          final assets = data['assets'] as List;
          for (final a in assets) {
            if (a is Map) {
              final name = (a['name'] ?? '').toString().toLowerCase();
              final url = (a['browser_download_url'] ?? '').toString();
              if (Platform.isAndroid && name.endsWith('.apk')) {
                downloadUrl = url;
                break;
              } else if (Platform.isMacOS && name.endsWith('.dmg')) {
                downloadUrl = url;
                break;
              } else if (Platform.isWindows && (name.endsWith('.exe') || name.endsWith('.zip'))) {
                downloadUrl = url;
                break;
              }
            }
          }
        }

        final releasePage = 'https://gitee.com/$giteeRepo/releases';
        final hasNew = isVersionNewer(tagName, currentVersion);

        return AppUpdateInfo(
          hasUpdate: hasNew,
          currentVersion: currentVersion,
          latestVersion: tagName.isNotEmpty ? tagName : currentVersion,
          releaseNotes: body.isNotEmpty ? body : null,
          publishedAt: publishedAt.isNotEmpty ? publishedAt : null,
          downloadUrl: downloadUrl,
          releasePageUrl: releasePage,
        );
      }
    } catch (_) {}

    // 2. 备用尝试 GitHub release-manifest.json
    try {
      final res = await _dio.get(
        'https://github.com/$githubRepo/releases/latest/download/release-manifest.json',
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        final version = (data['version'] ?? '').toString().trim();
        final publishedAt = (data['published_at'] ?? '').toString().trim();
        final links = data['links'] as Map? ?? {};
        final giteeRel = (links['gitee_release'] ?? '').toString();
        final githubRel = (links['github_release'] ?? 'https://github.com/$githubRepo/releases/latest').toString();

        String? downloadUrl;
        final platforms = data['platforms'] as Map? ?? {};
        if (Platform.isAndroid && platforms['android'] is Map) {
          final p = platforms['android'] as Map;
          downloadUrl = (p['gitee'] ?? p['github'])?.toString();
        } else if (Platform.isMacOS && platforms['macos'] is Map) {
          final p = platforms['macos'] as Map;
          downloadUrl = (p['gitee'] ?? p['github'])?.toString();
        } else if (Platform.isWindows && platforms['windows_installer'] is Map) {
          final p = platforms['windows_installer'] as Map;
          downloadUrl = (p['gitee'] ?? p['github'])?.toString();
        }

        final hasNew = isVersionNewer(version, currentVersion);
        return AppUpdateInfo(
          hasUpdate: hasNew,
          currentVersion: currentVersion,
          latestVersion: version.isNotEmpty ? version : currentVersion,
          releaseNotes: null,
          publishedAt: publishedAt.isNotEmpty ? publishedAt : null,
          downloadUrl: downloadUrl,
          releasePageUrl: giteeRel.isNotEmpty ? giteeRel : githubRel,
        );
      }
    } catch (_) {}

    // 网络不可达或未发现新版
    return AppUpdateInfo(
      hasUpdate: false,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      releasePageUrl: 'https://gitee.com/$giteeRepo/releases',
    );
  }

  /// 比较版本号：latestTag 是否大于 currentVer
  static bool isVersionNewer(String latestTag, String currentVer) {
    if (latestTag.isEmpty) return false;
    final cleanLatest = latestTag.replaceAll(RegExp(r'^[vV]'), '').split('+').first.trim();
    final cleanCurrent = currentVer.replaceAll(RegExp(r'^[vV]'), '').split('+').first.trim();

    final latestParts = cleanLatest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts = cleanCurrent.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
