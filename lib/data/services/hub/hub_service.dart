import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class HubStructureSummary {
  final String id;
  final String name;
  final int slotCount;
  final List<String> slotLabels;

  const HubStructureSummary({
    this.id = '',
    this.name = '',
    this.slotCount = 0,
    this.slotLabels = const [],
  });

  factory HubStructureSummary.fromJson(Map<String, dynamic> json) =>
      HubStructureSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slotCount: json['slotCount'] as int? ?? 0,
        slotLabels:
            (json['slotLabels'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class HubProfileSummary {
  final String id;
  final String name;
  final int blockCount;

  const HubProfileSummary({this.id = '', this.name = '', this.blockCount = 0});

  factory HubProfileSummary.fromJson(Map<String, dynamic> json) =>
      HubProfileSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        blockCount: json['blockCount'] as int? ?? 0,
      );
}

class HubContentSummary {
  final String id;
  final String name;
  final int filledSlotCount;
  final bool hasGlobalGuidance;
  final bool hasFullExample;
  final String sampleSnippet;

  const HubContentSummary({
    this.id = '',
    this.name = '',
    this.filledSlotCount = 0,
    this.hasGlobalGuidance = false,
    this.hasFullExample = false,
    this.sampleSnippet = '',
  });

  factory HubContentSummary.fromJson(Map<String, dynamic> json) =>
      HubContentSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        filledSlotCount: json['filledSlotCount'] as int? ?? 0,
        hasGlobalGuidance: json['hasGlobalGuidance'] as bool? ?? false,
        hasFullExample: json['hasFullExample'] as bool? ?? false,
        sampleSnippet: json['sampleSnippet'] as String? ?? '',
      );
}

class HubPipelineSummary {
  final bool hasPipeline;
  final int nodeCount;
  final List<String> stageLabels;

  const HubPipelineSummary({
    this.hasPipeline = false,
    this.nodeCount = 0,
    this.stageLabels = const [],
  });

  factory HubPipelineSummary.fromJson(Map<String, dynamic> json) =>
      HubPipelineSummary(
        hasPipeline: json['hasPipeline'] as bool? ?? false,
        nodeCount: json['nodeCount'] as int? ?? 0,
        stageLabels:
            (json['stageLabels'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class HubDiagnosisSummary {
  final int count;
  final List<String> tags;
  final List<String> sampleNames;

  const HubDiagnosisSummary({
    this.count = 0,
    this.tags = const [],
    this.sampleNames = const [],
  });

  factory HubDiagnosisSummary.fromJson(Map<String, dynamic> json) =>
      HubDiagnosisSummary(
        count: json['count'] as int? ?? 0,
        tags:
            (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        sampleNames:
            (json['sampleNames'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class HubListingSummary {
  final HubStructureSummary? structure;
  final HubPipelineSummary? pipeline;
  final List<HubProfileSummary> profiles;
  final List<HubContentSummary> contents;
  final HubDiagnosisSummary? diagnoses;

  const HubListingSummary({
    this.structure,
    this.pipeline,
    this.profiles = const [],
    this.contents = const [],
    this.diagnoses,
  });

  factory HubListingSummary.fromJson(Map<String, dynamic> json) =>
      HubListingSummary(
        structure: json['structure'] is Map
            ? HubStructureSummary.fromJson(
                Map<String, dynamic>.from(json['structure'] as Map),
              )
            : (json['structureName'] != null
                  ? HubStructureSummary(name: json['structureName'].toString())
                  : null),
        pipeline: json['pipeline'] is Map
            ? HubPipelineSummary.fromJson(
                Map<String, dynamic>.from(json['pipeline'] as Map),
              )
            : (json['pipeline'] == true
                  ? const HubPipelineSummary(hasPipeline: true)
                  : null),
        profiles:
            (json['profiles'] as List?)
                ?.whereType<Map>()
                .map(
                  (m) =>
                      HubProfileSummary.fromJson(Map<String, dynamic>.from(m)),
                )
                .toList() ??
            ((json['profiles'] as List?)
                    ?.map((e) => HubProfileSummary(name: e.toString()))
                    .toList() ??
                const []),
        contents:
            (json['contents'] as List?)
                ?.whereType<Map>()
                .map(
                  (m) =>
                      HubContentSummary.fromJson(Map<String, dynamic>.from(m)),
                )
                .toList() ??
            ((json['contents'] as List?)
                    ?.map((e) => HubContentSummary(name: e.toString()))
                    .toList() ??
                const []),
        diagnoses: json['diagnoses'] is Map
            ? HubDiagnosisSummary.fromJson(
                Map<String, dynamic>.from(json['diagnoses'] as Map),
              )
            : (json['diagnoses'] is int
                  ? HubDiagnosisSummary(count: json['diagnoses'] as int)
                  : null),
      );
}

class HubListing {
  final String id;
  final String kind;
  final String title;
  final String readme;
  final Map<String, dynamic> counts;
  final HubListingSummary summary;
  final String status; // 'approved', 'pending', 'rejected'
  final bool isMine;
  final String? payload;
  final String structureId;
  final String institution;
  final String versionId;
  final DateTime updatedAt;

  const HubListing({
    required this.id,
    required this.kind,
    required this.title,
    required this.readme,
    required this.counts,
    required this.summary,
    this.status = 'approved',
    this.isMine = false,
    required this.updatedAt,
    this.payload,
    this.structureId = '',
    this.institution = '',
    this.versionId = '',
  });

  factory HubListing.fromJson(Map<String, dynamic> json) => HubListing(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? '',
    title: json['title'] as String? ?? '',
    readme: json['readme'] as String? ?? '',
    counts: Map<String, dynamic>.from(json['counts'] as Map? ?? const {}),
    summary: json['summary'] is Map
        ? HubListingSummary.fromJson(
            Map<String, dynamic>.from(json['summary'] as Map),
          )
        : const HubListingSummary(),
    status: json['status'] as String? ?? 'approved',
    isMine: json['is_mine'] as bool? ?? false,
    payload: json['payload'] as String?,
    structureId: json['structure_id'] as String? ?? '',
    institution: json['institution'] as String? ?? '',
    versionId: json['version_id'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class HubService {
  static const defaultBaseUrl = 'https://xlearning.website/hub';
  // Local publishing credentials are deliberately outside all backup formats.
  // Never migrate the legacy hub_owner_key: older backups could copy it.
  static const _publisherKeyPrefix = 'hub_publisher_key_v2_';
  static Future<void> _identityQueue = Future<void>.value();
  static const _publisherIosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );
  static const _publisherMacOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    useDataProtectionKeyChain: false,
  );
  static const _urlKey = 'hub_custom_base_url';
  static const _adminTokenKey = 'hub_admin_token';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  HubService(this._storage)
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: false,
        ),
      );

  Future<String> getBaseUrl() async {
    final custom = await _storage.read(key: _urlKey);
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return defaultBaseUrl;
  }

  Future<void> setBaseUrl(String? url) async {
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException('请填写有效的服务器地址');
      }
    }
    if (url == null || url.trim().isEmpty || url.trim() == defaultBaseUrl) {
      await _storage.delete(key: _urlKey);
    } else {
      await _storage.write(
        key: _urlKey,
        value: url.trim().replaceAll(RegExp(r'/+$'), ''),
      );
    }
  }

  Future<String?> getAdminToken({String? baseUrl}) async {
    final base = baseUrl ?? await getBaseUrl();
    final scoped = await _storage.read(
      key: '${_adminTokenKey}_${_scope(base)}',
    );
    if (scoped != null) return scoped;
    // Old credentials belong only to the original official service.
    if (base == defaultBaseUrl) {
      final legacy = await _storage.read(key: _adminTokenKey);
      if (legacy != null) {
        await _storage.write(
          key: '${_adminTokenKey}_${_scope(base)}',
          value: legacy,
        );
        await _storage.delete(key: _adminTokenKey);
      }
      return legacy;
    }
    return null;
  }

  Future<void> setAdminToken(String? token) async {
    final key = '${_adminTokenKey}_${_scope(await getBaseUrl())}';
    if (token == null || token.trim().isEmpty) {
      await _storage.delete(key: key);
      if (await getBaseUrl() == defaultBaseUrl) {
        await _storage.delete(key: _adminTokenKey);
      }
    } else {
      await _storage.write(key: key, value: token.trim());
    }
  }

  Future<String> ownerKey({String? baseUrl}) async {
    final base = baseUrl ?? await getBaseUrl();
    final key = '$_publisherKeyPrefix${_scope(base)}';
    // Different HubService instances may initialize the same secure-storage
    // key concurrently. Serialize read/create/write, not the resulting identity:
    // separate storage instances (devices) must still receive separate keys.
    final result = _identityQueue.then((_) async {
      final existing = await _storage.read(
        key: key,
        iOptions: _publisherIosOptions,
        mOptions: _publisherMacOptions,
      );
      if (existing != null && existing.isNotEmpty) return existing;
      final created = const Uuid().v4() + const Uuid().v4();
      await _storage.write(
        key: key,
        value: created,
        iOptions: _publisherIosOptions,
        mOptions: _publisherMacOptions,
      );
      return created;
    });
    _identityQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static String _scope(String base) => base64Url.encode(utf8.encode(base));

  Future<Map<String, dynamic>> analyzeUpload({
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> targets,
    String scope = '',
    String institution = '',
  }) async {
    final base = await getBaseUrl();
    final response = await _dio.post(
      '$base/v2/analyses',
      data: {
        'ownerKey': await ownerKey(baseUrl: base),
        'payload': payload,
        'targets': targets,
        'scope': scope,
        'institution': institution,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> submitUpload({
    required String analysisId,
    required String requestId,
    required List<Map<String, dynamic>> decisions,
    String structureId = '',
    String scope = '',
    String institution = '',
  }) async {
    final base = await getBaseUrl();
    final response = await _dio.post(
      '$base/v2/batches',
      data: {
        'ownerKey': await ownerKey(baseUrl: base),
        'analysis_id': analysisId,
        'request_id': requestId,
        'structure_id': structureId,
        'scope': scope,
        'institution': institution,
        'items': decisions,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<HubListing>> related(String structureId) async {
    final base = await getBaseUrl();
    final res = await _dio.get(
      '$base/v2/structures/$structureId',
      options: Options(headers: {'X-Owner-Key': await ownerKey(baseUrl: base)}),
    );
    return ((res.data['listings'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => HubListing.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<bool> testConnection([String? testUrl]) async {
    try {
      final base = (testUrl != null && testUrl.trim().isNotEmpty)
          ? testUrl.trim().replaceAll(RegExp(r'/+$'), '')
          : await getBaseUrl();
      final res = await _dio.get('$base/health');
      return res.statusCode == 200 && res.data is Map && res.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<HubListing>> list({
    required String kind,
    String q = '',
    bool mineOnly = false,
    int offset = 0,
  }) async {
    final base = await getBaseUrl();
    final key = await ownerKey(baseUrl: base);
    final adminToken = await getAdminToken(baseUrl: base);

    final res = await _dio.get(
      '$base/v1/listings',
      queryParameters: {
        'kind': kind,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (mineOnly) 'mine': '1',
        if (offset > 0) 'offset': offset,
      },
      options: Options(
        headers: {
          'X-Owner-Key': key,
          if (adminToken != null && adminToken.isNotEmpty)
            'X-Admin-Token': adminToken,
        },
      ),
    );
    final rows = (res.data['listings'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => HubListing.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<HubListing> get(String id) async {
    final base = await getBaseUrl();
    final key = await ownerKey(baseUrl: base);
    final adminToken = await getAdminToken(baseUrl: base);

    final res = await _dio.get(
      '$base/v1/listings/$id',
      options: Options(
        headers: {
          'X-Owner-Key': key,
          if (adminToken != null && adminToken.isNotEmpty)
            'X-Admin-Token': adminToken,
        },
      ),
    );
    return HubListing.fromJson(
      Map<String, dynamic>.from(res.data['listing'] as Map),
    );
  }

  Future<Map<String, dynamic>> publish({
    required String kind,
    required String title,
    required String readme,
    required String payload,
  }) async {
    final base = await getBaseUrl();
    final res = await _dio.post(
      '$base/v1/listings',
      data: {
        'ownerKey': await ownerKey(baseUrl: base),
        'kind': kind,
        'title': title,
        'readme': readme,
        'payload': payload,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> delete(String id) async {
    final base = await getBaseUrl();
    await _dio.delete(
      '$base/v1/listings/$id',
      data: {'ownerKey': await ownerKey(baseUrl: base)},
    );
  }

  // --------------------------------------------------------------------------
  // 管理员审核接口 (当配置了 Admin Token 时可用)
  // --------------------------------------------------------------------------
  Future<void> reviewItem({required String id, required bool approve}) async {
    final base = await getBaseUrl();
    final token = await getAdminToken(baseUrl: base);
    if (token == null || token.isEmpty) {
      throw Exception('未配置管理员密钥');
    }
    await _dio.post(
      '$base/v1/admin/review',
      data: {'version_id': id, 'action': approve ? 'approve' : 'reject'},
      options: Options(headers: {'X-Admin-Token': token}),
    );
  }

  static String publicPayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return raw;
    final map = Map<String, dynamic>.from(decoded)
      ..remove('api_configs')
      ..remove('prompt_configs')
      ..remove('device_and_output_configs');
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
