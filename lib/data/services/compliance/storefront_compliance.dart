import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Immutable compliance evaluation snapshot for the current platform & storefront.
class StorefrontComplianceState {
  final bool isAiDirectDisabled;
  final String? storefrontCountryCode;
  final String? deviceRegionCode;
  final String source;
  final bool isLocked;

  const StorefrontComplianceState({
    required this.isAiDirectDisabled,
    this.storefrontCountryCode,
    this.deviceRegionCode,
    required this.source,
    this.isLocked = false,
  });

  const StorefrontComplianceState.unrestricted({
    this.storefrontCountryCode,
    this.deviceRegionCode,
    this.source = 'non_ios',
    this.isLocked = false,
  }) : isAiDirectDisabled = false;

  const StorefrontComplianceState.chinaRestricted({
    this.storefrontCountryCode,
    this.deviceRegionCode,
    this.source = 'storefront',
    this.isLocked = false,
  }) : isAiDirectDisabled = true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorefrontComplianceState &&
          runtimeType == other.runtimeType &&
          isAiDirectDisabled == other.isAiDirectDisabled &&
          storefrontCountryCode == other.storefrontCountryCode &&
          deviceRegionCode == other.deviceRegionCode &&
          source == other.source &&
          isLocked == other.isLocked;

  @override
  int get hashCode => Object.hash(
        isAiDirectDisabled,
        storefrontCountryCode,
        deviceRegionCode,
        source,
        isLocked,
      );
}

String? _normalizeUpper(String? value) {
  final trimmed = value?.trim().toUpperCase();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Evaluates whether direct cloud AI API capabilities must be disabled.
///
/// Only iOS builds distributed/running under China mainland StoreKit storefront
/// (`CHN`, falling back to device region `CN`/`CHN` only when storefront is
/// unavailable) enter restricted mode. Debug overrides are compile-time dead in
/// release builds when invoked with `isDebugMode: kDebugMode`.
StorefrontComplianceState evaluateStorefrontCompliance({
  required bool isIos,
  String? storefrontCountryCode,
  String? deviceRegionCode,
  bool isStorefrontLocked = false,
  String? debugOverride,
  bool isDebugMode = false,
}) {
  if (isDebugMode) {
    final override = debugOverride?.trim().toLowerCase();
    if (override == 'true' || override == '1') {
      return const StorefrontComplianceState.chinaRestricted(
        storefrontCountryCode: 'CHN',
        deviceRegionCode: 'CN',
        source: 'debug_override',
      );
    }
    if (override == 'false' || override == '0') {
      return const StorefrontComplianceState.unrestricted(
        storefrontCountryCode: 'USA',
        deviceRegionCode: 'US',
        source: 'debug_override',
      );
    }
  }

  if (!isIos) {
    return const StorefrontComplianceState.unrestricted(source: 'non_ios');
  }

  final sf = _normalizeUpper(storefrontCountryCode);
  final region = _normalizeUpper(deviceRegionCode);

  if (sf != null) {
    final resolvedSource = isStorefrontLocked ? 'locked_storefront' : 'storefront';
    if (sf == 'CHN') {
      return StorefrontComplianceState.chinaRestricted(
        storefrontCountryCode: sf,
        deviceRegionCode: region,
        source: resolvedSource,
        isLocked: isStorefrontLocked,
      );
    }
    return StorefrontComplianceState.unrestricted(
      storefrontCountryCode: sf,
      deviceRegionCode: region,
      source: resolvedSource,
      isLocked: isStorefrontLocked,
    );
  }

  if (region == 'CN' || region == 'CHN') {
    return StorefrontComplianceState.chinaRestricted(
      deviceRegionCode: region,
      source: 'locale_fallback',
    );
  }

  return StorefrontComplianceState.unrestricted(
    deviceRegionCode: region,
    source: 'locale_fallback',
  );
}

/// Extracts an ISO 3166-1 alpha-2 region code from a locale string such as
/// `zh_CN` or `zh_Hans_CN`, ignoring language and 4-letter script tags.
String? extractRegionFromLocaleName(String localeName) {
  final parts = localeName
      .trim()
      .split(RegExp(r'[_-]'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length < 2) return null;
  for (final part in parts.sublist(1).reversed) {
    if (part.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) {
      return part.toUpperCase();
    }
  }
  return null;
}

class StorefrontComplianceService {
  static const _channel = MethodChannel('com.xinggue.docmasterPei/storefront');
  static const _debugForceEnv = String.fromEnvironment('FORCE_CHINA_COMPLIANCE');

  static Future<StorefrontComplianceState> resolve() async {
    if (kDebugMode && _debugForceEnv.isNotEmpty) {
      final evaluated = evaluateStorefrontCompliance(
        isIos: !kIsWeb && Platform.isIOS,
        debugOverride: _debugForceEnv,
        isDebugMode: kDebugMode,
      );
      if (evaluated.source == 'debug_override') {
        return evaluated;
      }
    }

    if (kIsWeb || !Platform.isIOS) {
      return const StorefrontComplianceState.unrestricted(source: 'non_ios');
    }

    String? storefrontCountryCode;
    String? deviceRegionCode;
    bool isStorefrontLocked = false;

    try {
      final info = await _channel
          .invokeMapMethod<String, dynamic>('getRegionInfo')
          .timeout(const Duration(milliseconds: 2500));
      storefrontCountryCode = info?['storefrontCountryCode']?.toString();
      deviceRegionCode = info?['deviceRegionCode']?.toString();
      isStorefrontLocked = info?['isLocked'] == true;
    } on MissingPluginException {
      deviceRegionCode = extractRegionFromLocaleName(Platform.localeName);
    } on PlatformException {
      deviceRegionCode = extractRegionFromLocaleName(Platform.localeName);
    } on TimeoutException {
      deviceRegionCode = extractRegionFromLocaleName(Platform.localeName);
    }

    return evaluateStorefrontCompliance(
      isIos: true,
      storefrontCountryCode: storefrontCountryCode,
      deviceRegionCode: deviceRegionCode,
      isStorefrontLocked: isStorefrontLocked,
    );
  }
}
