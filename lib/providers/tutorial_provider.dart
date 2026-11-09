import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/settings_repository.dart';
import 'providers.dart';

enum TutorialType {
  basicFlow,
  aiConfig,
  bleKeyboard,
}

extension TutorialTypeExt on TutorialType {
  String get title => switch (this) {
        TutorialType.basicFlow => '基础操作流程',
        TutorialType.aiConfig => 'AI 与接口配置',
        TutorialType.bleKeyboard => '蓝牙模拟键盘录入',
      };

  String get settingsKey => switch (this) {
        TutorialType.basicFlow => 'tutorial_basic_flow_completed',
        TutorialType.aiConfig => 'tutorial_ai_config_completed',
        TutorialType.bleKeyboard => 'tutorial_ble_keyboard_completed',
      };
}

class TutorialState {
  final TutorialType? activeTutorial;
  final int currentStep; // 1-based index (e.g. 1 to 5)
  final bool isCompleted;

  const TutorialState({
    this.activeTutorial,
    this.currentStep = 0,
    this.isCompleted = true,
  });

  bool get isActive => activeTutorial != null && !isCompleted;

  TutorialState copyWith({
    TutorialType? activeTutorial,
    int? currentStep,
    bool? isCompleted,
    bool clearActiveTutorial = false,
  }) {
    return TutorialState(
      activeTutorial: clearActiveTutorial
          ? null
          : (activeTutorial ?? this.activeTutorial),
      currentStep: currentStep ?? this.currentStep,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class TutorialNotifier extends StateNotifier<TutorialState> {
  final SettingsRepository _settingsRepo;
  bool _manuallyStarted = false;

  TutorialNotifier(this._settingsRepo) : super(const TutorialState()) {
    _init();
  }

  Future<void> _init() async {
    // 教程不再自动启动，由「欢迎引导页」询问用户后再决定是否开启。
    final completed =
        await _settingsRepo.get(TutorialType.basicFlow.settingsKey);
    if (_manuallyStarted) return;
    state = TutorialState(
      activeTutorial: null,
      currentStep: 0,
      isCompleted: completed == 'true',
    );
  }

  Future<void> startTutorial(TutorialType type, {int step = 1}) async {
    _manuallyStarted = true;
    state = TutorialState(
      activeTutorial: type,
      currentStep: step,
      isCompleted: false,
    );
  }

  Future<void> nextStep() async {
    if (!state.isActive) return;

    if (state.activeTutorial == TutorialType.basicFlow) {
      if (state.currentStep < 5) {
        state = state.copyWith(currentStep: state.currentStep + 1);
      } else {
        await completeTutorial();
      }
    }
  }

  void goToStep(int step) {
    if (!state.isActive) return;
    state = state.copyWith(currentStep: step);
  }

  Future<void> skipTutorial() async {
    final active = state.activeTutorial;
    if (active != null) {
      await _settingsRepo.set(active.settingsKey, 'true');
    }
    state = const TutorialState(
      activeTutorial: null,
      currentStep: 0,
      isCompleted: true,
    );
  }

  Future<void> completeTutorial() async {
    final active = state.activeTutorial;
    if (active != null) {
      await _settingsRepo.set(active.settingsKey, 'true');
    }
    state = const TutorialState(
      activeTutorial: null,
      currentStep: 0,
      isCompleted: true,
    );
  }

  Future<void> resetTutorial(TutorialType type) async {
    await _settingsRepo.set(type.settingsKey, 'false');
    await startTutorial(type, step: 1);
  }

  Future<bool> isCompleted(TutorialType type) async {
    final res = await _settingsRepo.get(type.settingsKey);
    return res == 'true';
  }
}

final tutorialProvider =
    StateNotifierProvider<TutorialNotifier, TutorialState>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return TutorialNotifier(settingsRepo);
});

/// 是否已完成首次启动的三页引导（欢迎 / 权限 / 教程询问）。
final onboardingCompletedProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final raw = await repo.get('onboarding_completed');
  return raw == 'true';
});

/// 标记引导完成，并通知应用切换到主界面。
Future<void> markOnboardingCompleted(WidgetRef ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  await repo.set('onboarding_completed', 'true');
  ref.invalidate(onboardingCompletedProvider);
}
