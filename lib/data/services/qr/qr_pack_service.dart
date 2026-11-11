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

/// 二维码扫码设备类型
enum QrScannerType {
  /// 专用扫码器：带专用硬件接收端，支持多包乱序聚合协议 (<<SEQ:...>>) 与按键控制指令
  dedicated,

  /// 常规扫码枪：标准 USB 扫码枪，即扫即打纯文本，不支持按键指令与协议头
  standard,
}

/// 二维码生成配置
class QrConfig {
  final int chunkSize; // 单包最大字符限制 (推荐 150~300)
  final QrScannerType scannerType; // 扫码设备类型

  const QrConfig({
    this.chunkSize = 200,
    this.scannerType = QrScannerType.dedicated,
  });

  bool get isStandardScanner => scannerType == QrScannerType.standard;

  QrConfig copyWith({
    int? chunkSize,
    QrScannerType? scannerType,
  }) {
    return QrConfig(
      chunkSize: chunkSize ?? this.chunkSize,
      scannerType: scannerType ?? this.scannerType,
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
  static const _keyScannerType = 'qr_scanner_type';

  QrConfigNotifier(this._settingsRepo) : super(const QrConfig()) {
    _load();
  }

  Future<void> _load() async {
    final val = await _settingsRepo.get(_keyChunkSize);
    var currentSize = state.chunkSize;
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null && parsed >= 50 && parsed <= 800) {
        currentSize = parsed;
      }
    }

    final typeVal = await _settingsRepo.get(_keyScannerType);
    var currentType = state.scannerType;
    if (typeVal != null) {
      if (typeVal == 'standard') {
        currentType = QrScannerType.standard;
      } else if (typeVal == 'dedicated') {
        currentType = QrScannerType.dedicated;
      }
    }

    state = state.copyWith(chunkSize: currentSize, scannerType: currentType);
  }

  Future<void> updateChunkSize(int newSize) async {
    if (newSize < 50 || newSize > 800) return;
    state = state.copyWith(chunkSize: newSize);
    await _settingsRepo.set(_keyChunkSize, newSize.toString());
  }

  Future<void> updateScannerType(QrScannerType type) async {
    state = state.copyWith(scannerType: type);
    await _settingsRepo.set(
      _keyScannerType,
      type == QrScannerType.standard ? 'standard' : 'dedicated',
    );
  }
}

/// 二维码分包核心服务
class QrPackService {
  /// 清洗常规扫码枪文本：将换行按键指令转为真实换行，剥离其余所有硬件按键指令（{...}）
  static String sanitizeForStandardScanner(String text) {
    // 1. 将回车/换行按键标签转为真实换行符
    var clean = text.replaceAll(RegExp(r'\{ENTER\}|\{RETURN\}', caseSensitive: false), '\n');
    // 2. 将 TAB 按键标签转为真实制表符
    clean = clean.replaceAll(RegExp(r'\{TAB\}', caseSensitive: false), '\t');
    // 3. 剥离所有其他硬件控制指令标签（如 {DELAY:...}, {CFG:...}, {CTRL+C}, {WIN+R}, {DONE:...} 等）
    clean = clean.replaceAll(RegExp(r'\{[A-Z0-9_:+= -]+\}', caseSensitive: false), '');
    return clean;
  }

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
  /// 如果超长，根据 scannerType 决定：
  /// - dedicated: 使用 <<SEQ:ID:M/N>> 协议分包
  /// - standard: 纯文本切分，不带协议头与按键指令
  /// [customSessionId] 若指定则使用指定 ID，否则基于 text 自动计算稳定 ID
  static List<QrPacket> splitText(
    String fullText, {
    int chunkSize = 200,
    QrScannerType scannerType = QrScannerType.dedicated,
    String? customSessionId,
  }) {
    String textToSplit = fullText.trim();
    if (scannerType == QrScannerType.standard) {
      textToSplit = sanitizeForStandardScanner(textToSplit).trim();
    }
    if (textToSplit.isEmpty) return [];

    if (textToSplit.length <= chunkSize) {
      return [
        QrPacket(
          index: 1,
          total: 1,
          sessionId: '',
          content: textToSplit,
          payload: textToSplit,
          isMultiPart: false,
        ),
      ];
    }

    // 切分文本片断
    final chunks = <String>[];
    for (int i = 0; i < textToSplit.length; i += chunkSize) {
      final end = min(i + chunkSize, textToSplit.length);
      chunks.add(textToSplit.substring(i, end));
    }

    final total = chunks.length;
    final packets = <QrPacket>[];

    if (scannerType == QrScannerType.standard) {
      for (int i = 0; i < total; i++) {
        final part = chunks[i];
        packets.add(
          QrPacket(
            index: i + 1,
            total: total,
            sessionId: '',
            content: part,
            payload: part,
            isMultiPart: true,
          ),
        );
      }
    } else {
      final sessionId = customSessionId ?? generateSessionId(textToSplit);
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
    }

    return packets;
  }
}
