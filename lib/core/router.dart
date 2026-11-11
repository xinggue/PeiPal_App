import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/pages/main/main_navigation_shell.dart';
import '../presentation/pages/patients/patient_list_page.dart';
import '../presentation/pages/patients/patient_form_page.dart';
import '../presentation/pages/patients/patient_records_page.dart';
import '../presentation/pages/tasks/task_center_page.dart';
import '../presentation/pages/chat/chat_page.dart';
import '../presentation/pages/chat/record_review_page.dart';
import '../presentation/pages/templates/docs_hub_page.dart';
import '../presentation/pages/templates/template_list_page.dart';
import '../presentation/pages/templates/template_editor_page.dart';
import '../presentation/pages/templates/content_template_list_page.dart';
import '../presentation/pages/templates/content_template_editor_page.dart';
import '../presentation/pages/templates/typing_presets_page.dart';
import '../presentation/pages/diagnosis/favorite_diagnosis_page.dart';
import '../presentation/pages/diagnosis/diagnosis_search_page.dart';
import '../presentation/pages/settings/settings_page.dart';
import '../presentation/pages/settings/ocr_settings_page.dart';
import '../presentation/pages/settings/asr_settings_page.dart';
import '../presentation/pages/settings/timing_settings_page.dart';
import '../presentation/pages/settings/ble_connect_page.dart';
import '../presentation/pages/settings/qr_settings_page.dart';
import '../presentation/pages/settings/llm_prompt_settings_page.dart';
import '../presentation/pages/settings/prompt_settings_page.dart';
import '../presentation/pages/settings/extractor_settings_page.dart';
import '../presentation/pages/settings/llm_providers_page.dart';
import '../presentation/pages/settings/backup_center_page.dart';
import '../presentation/pages/hub/template_hub_page.dart';
import '../presentation/pages/settings/char_replacement_settings_page.dart';
import '../presentation/pages/settings/about_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/patients',
    routes: [
      StatefulShellRoute(
        builder: (context, state, navigationShell) => navigationShell,
        navigatorContainerBuilder: (context, navigationShell, children) {
          return MainNavigationShell(
            navigationShell: navigationShell,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/patients',
                name: 'patients',
                builder: (context, state) => const PatientListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/ble',
                name: 'ble',
                builder: (context, state) => const BleConnectPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/workspace',
                name: 'workspace',
                builder: (context, state) => const DocsHubPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/patients/new',
        name: 'patient_new',
        builder: (context, state) => const PatientFormPage(),
      ),
      GoRoute(
        path: '/patients/:id/edit',
        name: 'patient_edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final autoExtract = state.uri.queryParameters['autoExtract'] == 'true';
          return PatientFormPage(
            patientId: id,
            autoExtractFromSession: autoExtract,
          );
        },
      ),
      GoRoute(
        path: '/patients/:id/chat',
        name: 'chat',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final highlightId = state.uri.queryParameters['highlightId'];
          return ChatPage(patientId: id, highlightMessageId: highlightId);
        },
      ),
      GoRoute(
        path: '/patients/:id/records',
        name: 'patient_records',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PatientRecordsPage(patientId: id);
        },
      ),
      GoRoute(
        path: '/patients/:pid/records/:mid/review',
        name: 'record_review',
        builder: (context, state) {
          final pid = state.pathParameters['pid']!;
          final mid = state.pathParameters['mid']!;
          return RecordReviewPage(patientId: pid, messageId: mid);
        },
      ),
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        builder: (context, state) => const TaskCenterPage(),
      ),
      GoRoute(
        path: '/templates',
        name: 'templates',
        builder: (context, state) => const TemplateListPage(),
      ),
      GoRoute(
        path: '/templates/new',
        name: 'template_new',
        builder: (context, state) => const TemplateEditorPage(),
      ),
      GoRoute(
        path: '/templates/:id/edit',
        name: 'template_edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TemplateEditorPage(templateId: id);
        },
      ),
      GoRoute(
        path: '/content-templates',
        name: 'content_templates',
        builder: (context, state) => const ContentTemplateListPage(),
      ),
      GoRoute(
        path: '/typing-presets',
        name: 'typing_presets',
        builder: (context, state) => const TypingPresetsPage(),
      ),
      GoRoute(
        path: '/templates/:id/content/new',
        name: 'content_template_new',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final migrateFromId = state.uri.queryParameters['migrateFrom'];
          return ContentTemplateEditorPage(
            structureTemplateId: id,
            initialMigrateFromId: migrateFromId,
          );
        },
      ),
      GoRoute(
        path: '/templates/:sid/content/:cid/edit',
        name: 'content_template_edit',
        builder: (context, state) {
          final sid = state.pathParameters['sid']!;
          final cid = state.pathParameters['cid']!;
          return ContentTemplateEditorPage(
              structureTemplateId: sid, contentTemplateId: cid);
        },
      ),
      GoRoute(
        path: '/diagnoses',
        name: 'diagnoses',
        builder: (context, state) => const FavoriteDiagnosisPage(),
      ),
      GoRoute(
        path: '/diagnoses/search',
        name: 'diagnosis_search',
        builder: (context, state) => const DiagnosisSearchPage(),
      ),
      GoRoute(
        path: '/settings/timing',
        name: 'timing_settings',
        builder: (context, state) => const TimingSettingsPage(),
      ),
      GoRoute(
        path: '/settings/ble',
        name: 'ble_settings',
        builder: (context, state) => const BleConnectPage(),
      ),
      GoRoute(
        path: '/settings/qr',
        name: 'qr_settings',
        builder: (context, state) => const QrSettingsPage(),
      ),
      GoRoute(
        path: '/settings/llm-providers',
        name: 'llm_providers',
        builder: (context, state) => const LlmProvidersPage(),
      ),
      GoRoute(
        path: '/settings/ocr',
        name: 'ocr_settings',
        builder: (context, state) => const OcrSettingsPage(),
      ),
      GoRoute(
        path: '/settings/asr',
        name: 'asr_settings',
        builder: (context, state) => const AsrSettingsPage(),
      ),
      GoRoute(
        path: '/settings/prompts',
        name: 'prompt_settings',
        builder: (context, state) => const PromptSettingsPage(),
      ),
      GoRoute(
        path: '/settings/llm',
        name: 'llm_settings',
        builder: (context, state) => const LlmPromptSettingsPage(),
      ),
      GoRoute(
        path: '/settings/extractor',
        name: 'extractor_settings',
        builder: (context, state) => const ExtractorSettingsPage(),
      ),
      GoRoute(
        path: '/settings/backup',
        name: 'backup_center',
        builder: (context, state) => const BackupCenterPage(),
      ),
      GoRoute(
        path: '/hub',
        name: 'template_hub',
        builder: (context, state) => const TemplateHubPage(),
      ),
      GoRoute(
        path: '/settings/char-replacement',
        name: 'char_replacement_settings',
        builder: (context, state) => const CharReplacementSettingsPage(),
      ),
      GoRoute(
        path: '/settings/about',
        name: 'about_settings',
        builder: (context, state) => const AboutPage(),
      ),
    ],
  );
});
