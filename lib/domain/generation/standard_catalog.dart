import '../models/favorite_diagnosis.dart';

/// A standard clinical terminology entry (通用标准临床术语条目).
/// Decoupled from any specific table or model, applicable to
/// diagnoses, surgical procedures, pathology, lab tests, etc.
class CatalogItem {
  final String code; // Standard code (e.g. ICD-10 I25.101, ICD-9-CM-3)
  final String name; // Standard name
  final List<String> tags; // Classification tags (e.g. 心内科, 普外科)
  final String? note; // Clinical remarks/subtyping

  const CatalogItem({
    required this.code,
    required this.name,
    this.tags = const [],
    this.note,
  });

  /// Factory adapter from FavoriteDiagnosis model
  factory CatalogItem.fromFavoriteDiagnosis(FavoriteDiagnosis d) => CatalogItem(
        code: d.code,
        name: d.name,
        tags: d.tags,
        note: d.note.isNotEmpty ? d.note : null,
      );
}
