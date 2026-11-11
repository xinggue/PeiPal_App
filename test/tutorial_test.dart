import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/generation/generation_log.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/data/repositories/patient_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/data/services/sample_data_service.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/domain/models/patient.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/providers/tutorial_provider.dart';

class MockSettingsRepo implements SettingsRepository {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class MockPatientRepo implements PatientRepository {
  final Map<String, Patient> _map = {};

  @override
  Future<List<Patient>> getAll() async => _map.values.toList();

  @override
  Future<Patient?> getById(String id) async => _map[id];

  @override
  Future<List<Patient>> search(String query) async => _map.values.toList();

  @override
  Future<void> insert(Patient patient) async => _map[patient.id] = patient;

  @override
  Future<void> update(Patient patient) async => _map[patient.id] = patient;

  @override
  Future<void> delete(String id) async => _map.remove(id);
}

class MockMessageRepo implements MessageRepository {
  final List<Message> _list = [];

  @override
  Future<List<Message>> getAllChronological(String patientId) async =>
      _list.where((m) => m.patientId == patientId).toList();

  @override
  Future<List<Message>> getByPatient(String patientId, {int limit = 100}) async =>
      _list.where((m) => m.patientId == patientId).take(limit).toList();

  @override
  Future<Message?> getById(String id) async =>
      _list.where((m) => m.id == id).firstOrNull;

  @override
  Future<int> getCountByPatient(String patientId) async =>
      _list.where((m) => m.patientId == patientId).length;

  @override
  Future<Message?> getLastByPatient(String patientId) async =>
      _list.where((m) => m.patientId == patientId).lastOrNull;

  @override
  Future<void> insert(Message message) async => _list.add(message);

  @override
  Future<void> insertGeneratedAtomic(Message message, GenerationLog log) async =>
      _list.add(message);

  @override
  Future<void> update(Message message) async {
    final idx = _list.indexWhere((m) => m.id == message.id);
    if (idx != -1) _list[idx] = message;
  }

  @override
  Future<void> delete(String id) async => _list.removeWhere((m) => m.id == id);
}

class MockTemplateRepo implements TemplateRepository {
  final Map<String, Template> _map = {};

  @override
  Future<List<Template>> getAll() async => _map.values.toList();

  @override
  Future<Template?> getById(String id) async => _map[id];

  @override
  Future<void> insert(Template t) async => _map[t.id] = t;

  @override
  Future<void> update(Template t) async => _map[t.id] = t;

  @override
  Future<void> delete(String id) async => _map.remove(id);
}

class MockContentTemplateRepo implements ContentTemplateRepository {
  final Map<String, ContentTemplate> _map = {};

  @override
  Future<List<ContentTemplate>> getAll() async => _map.values.toList();

  @override
  Future<ContentTemplate?> getById(String id) async => _map[id];

  @override
  Future<List<ContentTemplate>> getByStructure(String structureTemplateId) async =>
      _map.values.where((c) => c.structureTemplateId == structureTemplateId).toList();

  @override
  Future<void> insert(ContentTemplate ct) async => _map[ct.id] = ct;

  @override
  Future<void> update(ContentTemplate ct) async => _map[ct.id] = ct;

  @override
  Future<void> delete(String id) async => _map.remove(id);

  @override
  Future<void> deleteByStructure(String structureTemplateId) async =>
      _map.removeWhere((_, c) => c.structureTemplateId == structureTemplateId);
}

void main() {
  group('TutorialNotifier Tests', () {
    test('Does not auto-start before onboarding prompt', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      // Wait for _init async
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.isCompleted, isFalse);
    });

    test('startTutorial activates basicFlow at step 1', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.startTutorial(TutorialType.basicFlow, step: 1);
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.activeTutorial, TutorialType.basicFlow);
      expect(notifier.state.currentStep, 1);
    });

    test('Steps 1 through 5 advance and complete gracefully', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.startTutorial(TutorialType.basicFlow, step: 1);

      expect(notifier.state.currentStep, 1);
      await notifier.nextStep();
      expect(notifier.state.currentStep, 2);
      await notifier.nextStep();
      expect(notifier.state.currentStep, 3);
      await notifier.nextStep();
      expect(notifier.state.currentStep, 4);
      await notifier.nextStep();
      expect(notifier.state.currentStep, 5);
      await notifier.nextStep();

      expect(notifier.state.isActive, isFalse);
      expect(settings.data[TutorialType.basicFlow.settingsKey], 'true');
    });

    test('Skip tutorial immediately finishes and persists flag', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.startTutorial(TutorialType.basicFlow, step: 1);

      await notifier.skipTutorial();
      expect(notifier.state.isActive, isFalse);
      expect(settings.data[TutorialType.basicFlow.settingsKey], 'true');
    });

    test('Reset tutorial restarts basicFlow at step 1', () async {
      final settings = MockSettingsRepo();
      settings.data[TutorialType.basicFlow.settingsKey] = 'true';
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isActive, isFalse);

      await notifier.resetTutorial(TutorialType.basicFlow);
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.activeTutorial, TutorialType.basicFlow);
      expect(notifier.state.currentStep, 1);
      expect(settings.data[TutorialType.basicFlow.settingsKey], 'false');
    });

    test('aiConfig tutorial advances through 3 steps and completes', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.startTutorial(TutorialType.aiConfig, step: 1);
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.activeTutorial, TutorialType.aiConfig);
      expect(notifier.state.currentStep, 1);

      await notifier.nextStep();
      expect(notifier.state.currentStep, 2);
      await notifier.nextStep();
      expect(notifier.state.currentStep, 3);
      await notifier.nextStep();

      expect(notifier.state.isActive, isFalse);
      expect(settings.data[TutorialType.aiConfig.settingsKey], 'true');
    });

    test('resetTutorial supports custom starting step (step 4 generation)', () async {
      final settings = MockSettingsRepo();
      final notifier = TutorialNotifier(settings);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.resetTutorial(TutorialType.basicFlow, step: 4);
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.activeTutorial, TutorialType.basicFlow);
      expect(notifier.state.currentStep, 4);
    });
  });

  group('SampleDataService Tests', () {
    test('Seeds template, patient, and 4 messages correctly', () async {
      final patientRepo = MockPatientRepo();
      final messageRepo = MockMessageRepo();
      final templateRepo = MockTemplateRepo();
      final contentTemplateRepo = MockContentTemplateRepo();
      final settingsRepo = MockSettingsRepo();

      final service = SampleDataService(
        patientRepo: patientRepo,
        messageRepo: messageRepo,
        templateRepo: templateRepo,
        contentTemplateRepo: contentTemplateRepo,
        settingsRepo: settingsRepo,
        seedMedia: false,
      );

      await service.ensureSampleData();

      final patients = await patientRepo.getAll();
      expect(patients.length, 1);
      expect(patients.first.id, SampleDataService.samplePatientId);
      expect(patients.first.name, '示例会话');

      final messages = await messageRepo.getAllChronological(SampleDataService.samplePatientId);
      expect(messages.length, 4);
      expect(messages.where((m) => m.type == MessageType.text).length, 2);
      expect(messages.where((m) => m.type == MessageType.photo).length, 2);
      expect(messages.any((m) => m.type == MessageType.voice), isFalse);
      expect(messages.any((m) => m.type == MessageType.generatedRecord), isFalse);

      final templates = await templateRepo.getAll();
      expect(templates.length, 1);
      expect(templates.first.id, SampleDataService.sampleTemplateId);
      expect(templates.first.name, '示例病史');
      expect(templates.first.slots.length, 8);
      expect(templates.first.slots.first.key, '主诉');

      final contentTemplates = await contentTemplateRepo.getAll();
      expect(contentTemplates.length, 1);
      expect(contentTemplates.first.name, '通用模板');
      expect(contentTemplates.first.slots['主诉']?.guidance, isNotEmpty);
      expect(contentTemplates.first.slots['查体']?.examples, isNotEmpty);

      expect(settingsRepo.data[SampleDataService.keySampleSeeded], 'true');
    });

    test('Does not duplicate data when called again without force', () async {
      final patientRepo = MockPatientRepo();
      final messageRepo = MockMessageRepo();
      final templateRepo = MockTemplateRepo();
      final contentTemplateRepo = MockContentTemplateRepo();
      final settingsRepo = MockSettingsRepo();

      final service = SampleDataService(
        patientRepo: patientRepo,
        messageRepo: messageRepo,
        templateRepo: templateRepo,
        contentTemplateRepo: contentTemplateRepo,
        settingsRepo: settingsRepo,
        seedMedia: false,
      );

      await service.ensureSampleData();
      await service.ensureSampleData();

      final patients = await patientRepo.getAll();
      expect(patients.length, 1);
      final messages = await messageRepo.getAllChronological(SampleDataService.samplePatientId);
      expect(messages.length, 4);
    });
  });
}
