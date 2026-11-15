import 'dart:convert';
import 'dart:io';
import 'package:enough_convert/gbk.dart';
import '../../../domain/models/document_parser_provider.dart';

/// Local reading is deliberately limited to text files. All office documents
/// (including PDFs with a text layer) go through the selected document service.
class DocumentParserService {
  static const maxTextBytes = 10 * 1024 * 1024;

  static Future<String> parseFileText(String path) async {
    if (!DocumentParserProviderConfig.isLocalFile(path)) {
      throw const FormatException('该文件需要配置文件解析服务');
    }
    final file = File(path);
    if (await file.length() > maxTextBytes) {
      throw const FormatException('文本文件不能超过 10 MiB，请拆分后发送');
    }
    return decodeText(await file.readAsBytes());
  }

  static String decodeText(List<int> bytes) {
    if (bytes.length >= 4 &&
        ((bytes[0] == 0x50 && bytes[1] == 0x4b) ||
            (bytes[0] == 0x25 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x44 &&
                bytes[3] == 0x46) ||
            (bytes[0] == 0xd0 && bytes[1] == 0xcf))) {
      throw const FormatException('文件内容与文本格式不符，请使用原始文件后缀');
    }
    String text;
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) throw const FormatException('UTF-16 文本不完整');
      final little = bytes[0] == 0xff;
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        units.add(
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
        );
      }
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        if (unit >= 0xd800 && unit <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('UTF-16 文本不完整');
          }
        } else if (unit >= 0xdc00 && unit <= 0xdfff) {
          throw const FormatException('UTF-16 文本不完整');
        }
      }
      text = String.fromCharCodes(units);
    } else {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        try {
          text = gbk.decode(bytes);
        } on FormatException {
          throw const FormatException('无法识别文本编码，请另存为 UTF-8 后重试');
        }
      }
    }
    text = text.replaceFirst(RegExp('^\uFEFF'), '');
    if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(text)) {
      throw const FormatException('文件包含非文本内容，请确认文件格式或另存为 UTF-8');
    }
    return text;
  }
}
