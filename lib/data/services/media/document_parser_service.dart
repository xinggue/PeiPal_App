import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// 常见医疗文件（PDF、Word docx、纯文本 txt/md/csv/json）的本地快速文本提取服务
class DocumentParserService {
  /// 单个 PDF 文档允许解析的最大页数上限，防止数百页大文件引起内存溢出 (OOM) 或无响应闪退
  static const int kMaxPdfParsePages = 20;

  /// 根据文件路径解析提取纯文本（对图文混排与纯图扫描 PDF 自动分流并支持导出图片）
  static Future<String> parseFileText(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FileSystemException('文件不存在');
    }

    final ext = filePath.split('.').last.toLowerCase();

    switch (ext) {
      case 'txt':
      case 'text':
      case 'md':
      case 'markdown':
      case 'csv':
      case 'json':
        return _parsePlainText(file);

      case 'docx':
        return _parseDocx(file);

      case 'pdf':
        return _parsePdf(file);

      default:
        try {
          return await _parsePlainText(file);
        } catch (_) {
          throw UnsupportedError('暂不支持解析 .$ext 格式的文件');
        }
    }
  }

  /// 纯文本类文件解析（支持 UTF-8 与 GBK 宽松容错）
  static Future<String> _parsePlainText(File file) async {
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  /// Word (.docx) 文件解析
  static Future<String> _parseDocx(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final archiveFile in archive) {
      if (archiveFile.name == 'word/document.xml') {
        final xmlContent = utf8.decode(archiveFile.content as List<int>, allowMalformed: true);
        return _extractTextFromDocxXml(xmlContent);
      }
    }

    throw const FormatException('未在 docx 文件中找到正文内容');
  }

  static String _extractTextFromDocxXml(String xml) {
    final buffer = StringBuffer();
    final paragraphRegex = RegExp(r'<w:p[\s>](.*?)<\/w:p>', dotAll: true);
    final textRegex = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);

    final paragraphs = paragraphRegex.allMatches(xml);
    for (final p in paragraphs) {
      final pContent = p.group(1) ?? '';
      final texts = textRegex.allMatches(pContent);
      final pText = texts.map((m) => m.group(1) ?? '').join('');
      if (pText.trim().isNotEmpty) {
        buffer.writeln(pText);
      }
    }

    final result = buffer.toString().trim();
    if (result.isNotEmpty) return result;

    return xml.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// PDF 提取：尝试提取内置文字图层，并严格控制最大解析页数上限
  static Future<String> _parsePdf(File file) async {
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final totalPages = document.pages.count;

    final textExtractor = PdfTextExtractor(document);
    String text;
    bool isTruncated = false;

    if (totalPages <= kMaxPdfParsePages) {
      text = textExtractor.extractText();
    } else {
      isTruncated = true;
      // 仅安全抽取前 20 页（0-indexed：0 到 19）
      text = textExtractor.extractText(startPageIndex: 0, endPageIndex: kMaxPdfParsePages - 1);
    }
    document.dispose();

    final trimmed = text.trim();
    if (isTruncated) {
      final notice = 'ℹ️【提示】该文档共 $totalPages 页，为保证流畅度仅提取前 $kMaxPdfParsePages 页内容：\n\n';
      return notice + trimmed;
    }
    return trimmed;
  }

  /// 判断 PDF 是否缺乏文字层（纯扫描件或提取文字过少）
  static bool isPdfTextSparse(String extractedText) {
    // 移除提示说明后的真实提取文本
    var clean = extractedText;
    if (clean.contains('ℹ️【提示】')) {
      final parts = clean.split('\n\n');
      clean = parts.length > 1 ? parts.sublist(1).join('\n\n') : clean;
    }
    clean = clean.replaceAll(RegExp(r'\s+'), '');
    return clean.length < 15;
  }

  /// 将 PDF 每一页渲染并光栅化为高清 JPG 图片，存储至指定目录
  /// 供后续送入多模态 Vision / OCR 引擎深度识别
  static Future<List<String>> renderPdfPagesToImages({
    required String pdfPath,
    required String outputDir,
    int maxPages = kMaxPdfParsePages,
  }) async {
    final images = <String>[];
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    pdfx.PdfDocument? document;
    try {
      document = await pdfx.PdfDocument.openFile(pdfPath);
      final count = document.pagesCount.clamp(1, maxPages);

      for (int i = 1; i <= count; i++) {
        final page = await document.getPage(i);
        // 按 2x 缩放光栅化，保证文字清晰度
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (pageImage != null) {
          final pageFilePath = p.join(
            outputDir,
            'pdf_page_${i.toString().padLeft(3, '0')}.jpg',
          );
          final file = File(pageFilePath);
          await file.writeAsBytes(pageImage.bytes);
          images.add(pageFilePath);
        }
      }
    } catch (_) {
      // 若光栅化异常，返回已渲染的部分
    } finally {
      await document?.close();
    }

    return images;
  }
}
