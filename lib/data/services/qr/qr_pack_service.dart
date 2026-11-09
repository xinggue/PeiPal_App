import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/settings_repository.dart';
import '../../../providers/providers.dart';

/// 二维码分包模型
class QrPacket {
  final int index; // 1-based
  final int total; // 总包数
  final String sessionId; // 会话 ID
  final String content; // 包含 <<SEQ:ID:M/N>> 前缀的整包文本，或单包原始文本
  final String payload; // 纯正文负载
  final bool isMultiPart;

  const QrPacket({
    required this.index,
    required this.total,
    required this.sessionId,
    required this.content,
    required this.payload,
    required this.isMultiPart,
  });
}

/// 二维码生成配置
class QrConfig {
  final int chunkSize; // 单包最大字符限制 (推荐 150~300)

  const QrConfig({this.chunkSize = 200});

  QrConfig copyWith({int? chunkSize}) {
    return QrConfig(
      chunkSize: chunkSize ?? this.chunkSize,
    );
  }
}

/// 二维码配置管理 Provider
final qrConfigProvider = StateNotifierProvider<QrConfigNotifier, QrConfig>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return QrConfigNotifier(settingsRepo);
});

class QrConfigNotifier extends StateNotifier<QrConfig> {
  final SettingsRepository _settingsRepo;
  static const _keyChunkSize = 'qr_chunk_size';

  QrConfigNotifier(this._settingsRepo) : super(const QrConfig()) {
    _load();
  }

  Future<void> _load() async {
    final val = await _settingsRepo.get(_keyChunkSize);
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null && parsed >= 50 && parsed <= 800) {
        state = state.copyWith(chunkSize: parsed);
      }
    }
  }

  Future<void> updateChunkSize(int newSize) async {
    if (newSize < 50 || newSize > 800) return;
    state = state.copyWith(chunkSize: newSize);
    await _settingsRepo.set(_keyChunkSize, newSize.toString());
  }
}

/// 二维码分包核心服务
class QrPackService {
  /// 基于文本内容生成确定性哈希 ID (3~4位大写16进制)
  /// 保证同一份文本在任意界面重绘或切页时，生成的会话 ID 严格一致！
  static String generateSessionId(String text) {
    if (text.isEmpty) return '000';
    var hash = 5381;
    for (int i = 0; i < text.length; i++) {
      hash = ((hash << 5) + hash) + text.codeUnitAt(i);
      hash = hash & 0xFFFFFF; // 保持 24-bit
    }
    // 转为 3 位 16 进制大写
    return (hash & 0xFFF).toRadixString(16).toUpperCase().padLeft(3, '0');
  }

  /// 将全文切分为一组 QrPacket
  ///
  /// 如果全文长度 <= chunkSize，直接返回单包（无 <<SEQ: 前缀，即扫即打）
  /// 如果超长，自动使用 <<SEQ:ID:M/N>> 协议分包
  /// [customSessionId] 若指定则使用指定 ID，否则基于 text 自动计算稳定 ID
  static List<QrPacket> splitText(
    String fullText, {
    int chunkSize = 200,
    String? customSessionId,
  }) {
    final trimmed = fullText.trim();
    if (trimmed.isEmpty) return [];

    if (trimmed.length <= chunkSize) {
      return [
        QrPacket(
          index: 1,
          total: 1,
          sessionId: '',
          content: trimmed,
          payload: trimmed,
          isMultiPart: false,
        ),
      ];
    }

    final sessionId = customSessionId ?? generateSessionId(trimmed);
    final packets = <QrPacket>[];

    // 切分文本片断
    final chunks = <String>[];
    for (int i = 0; i < trimmed.length; i += chunkSize) {
      final end = min(i + chunkSize, trimmed.length);
      chunks.add(trimmed.substring(i, end));
    }

    final total = chunks.length;
    for (int i = 0; i < total; i++) {
      final idx = i + 1;
      final part = chunks[i];
      final header = '<<SEQ:$sessionId:$idx/$total>>';
      packets.add(
        QrPacket(
          index: idx,
          total: total,
          sessionId: sessionId,
          content: '$header$part',
          payload: part,
          isMultiPart: true,
        ),
      );
    }

    return packets;
  }
}
