import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum Gender { unspecified, male, female }

extension GenderExt on Gender {
  String get label => switch (this) {
        Gender.male => '男',
        Gender.female => '女',
        Gender.unspecified => '不填',
      };
  String get value => switch (this) {
        Gender.male => 'male',
        Gender.female => 'female',
        Gender.unspecified => 'unspecified',
      };

  static Gender fromString(String? s) => switch (s) {
        'male' => Gender.male,
        'female' => Gender.female,
        _ => Gender.unspecified,
      };
}

enum PatientStatus { active, discharged }

extension PatientStatusExt on PatientStatus {
  String get label => this == PatientStatus.active ? '进行中' : '已归档';
  String get value => name;

  static PatientStatus fromString(String s) =>
      s == 'discharged' ? PatientStatus.discharged : PatientStatus.active;
}

class Patient {
  final String id;
  final String name;
  final Gender gender;
  final int? age;
  final String? medicalRecordNumber;
  final String? notes;
  final PatientStatus status;
  final Map<String, dynamic> extraData;
  final DateTime createdAt;
  final DateTime updatedAt;

  Patient({
    String? id,
    required this.name,
    this.gender = Gender.unspecified,
    this.age,
    this.medicalRecordNumber,
    this.notes,
    this.status = PatientStatus.active,
    this.extraData = const {},
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 自适应生成右侧或副标题简短附加信息（未填写性别/年龄时返回空字符串，避免显示“男 岁”）
  String get displayMeta {
    final parts = <String>[];
    if (gender != Gender.unspecified) {
      parts.add(gender.label);
    }
    if (age != null) {
      parts.add('$age岁');
    }
    for (final v in extraData.values) {
      if (v != null && v.toString().trim().isNotEmpty) {
        parts.add(v.toString().trim());
      }
    }
    return parts.join(' ');
  }

  Patient copyWith({
    String? name,
    Gender? gender,
    int? age,
    bool clearAge = false,
    String? medicalRecordNumber,
    bool clearMrn = false,
    String? notes,
    bool clearNotes = false,
    PatientStatus? status,
    Map<String, dynamic>? extraData,
  }) =>
      Patient(
        id: id,
        name: name ?? this.name,
        gender: gender ?? this.gender,
        age: clearAge ? null : (age ?? this.age),
        medicalRecordNumber:
            clearMrn ? null : (medicalRecordNumber ?? this.medicalRecordNumber),
        notes: clearNotes ? null : (notes ?? this.notes),
        status: status ?? this.status,
        extraData: extraData ?? this.extraData,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'gender': gender.value,
        'age': age,
        'medical_record_number': medicalRecordNumber,
        'notes': notes,
        'status': status.value,
        'extra_data': jsonEncode(extraData),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Patient.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedExtra = const {};
    if (map['extra_data'] != null && map['extra_data'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['extra_data'] as String);
        if (decoded is Map<String, dynamic>) {
          parsedExtra = decoded;
        }
      } catch (_) {}
    }

    return Patient(
      id: map['id'] as String,
      name: map['name'] as String,
      gender: GenderExt.fromString(map['gender'] as String),
      age: map['age'] as int?,
      medicalRecordNumber: map['medical_record_number'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] != null
          ? PatientStatusExt.fromString(map['status'] as String)
          : PatientStatus.active,
      extraData: parsedExtra,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
