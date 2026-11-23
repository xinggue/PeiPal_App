import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/compliance/storefront_compliance.dart';

/// Resolved at app startup before `runApp` (defaulting to unrestricted in tests).
final initialStorefrontComplianceProvider = Provider<StorefrontComplianceState>(
  (ref) => const StorefrontComplianceState.unrestricted(),
);

class StorefrontComplianceNotifier
    extends StateNotifier<StorefrontComplianceState> {
  StorefrontComplianceNotifier(super.initial);

  Future<void> refresh() async {
    final next = await StorefrontComplianceService.resolve();
    if (mounted && next != state) {
      state = next;
    }
  }
}

final storefrontComplianceProvider = StateNotifierProvider<
    StorefrontComplianceNotifier, StorefrontComplianceState>(
  (ref) => StorefrontComplianceNotifier(
    ref.watch(initialStorefrontComplianceProvider),
  ),
);

/// True when running on iOS under China mainland storefront (or CN region
/// fallback when storefront is unavailable).
final isChinaAiRestrictedProvider = Provider<bool>(
  (ref) => ref.watch(storefrontComplianceProvider).isAiDirectDisabled,
);
