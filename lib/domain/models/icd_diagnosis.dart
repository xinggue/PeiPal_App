/// A standard ICD entry from the precompiled multi-version knowledge base.
class IcdDiagnosis {
  final int id;
  final String code;
  final String cleanCode;
  final String name;
  final String cleanName;
  final String mixedPy;
  final String purePy;
  final String version;

  const IcdDiagnosis({
    required this.id,
    required this.code,
    required this.cleanCode,
    required this.name,
    required this.cleanName,
    required this.mixedPy,
    required this.purePy,
    required this.version,
  });

  List<String> get versionList =>
      version.split(' / ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  factory IcdDiagnosis.fromMap(Map<String, dynamic> map) => IcdDiagnosis(
        id: map['id'] as int,
        code: map['code'] as String,
        cleanCode: map['clean_code'] as String,
        name: map['name'] as String,
        cleanName: map['clean_name'] as String,
        mixedPy: map['mixed_py'] as String,
        purePy: map['pure_py'] as String? ?? '',
        version: map['version'] as String,
      );
}
