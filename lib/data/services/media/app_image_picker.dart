import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// 跨平台图片与文书选取工具：
/// - 桌面端 (macOS / Windows / Linux) 优先弹出系统原生访达/文件选择器 (File Selector)，完美兼容多选与沙盒访问。
/// - 移动端 (Android / iOS) 走原生 PhotoPicker (ImagePicker)，享受移动端相册与相机体验。
class AppImagePicker {
  static final _picker = ImagePicker();

  /// 多图文书选取
  static Future<List<String>> pickMultiImages() async {
    // 桌面端使用系统访达 / 文件管理器弹窗
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      const typeGroup = XTypeGroup(
        label: '图片文书',
        extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'],
      );
      final files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      return files.map((f) => f.path).toList();
    }

    // 移动端调用原生相册
    final images = await _picker.pickMultiImage();
    return images.map((i) => i.path).toList();
  }

  /// 单图拍照 / 选取
  static Future<String?> pickSingleImage({ImageSource source = ImageSource.camera}) async {
    // 桌面端无后置摄像头时，统一调用系统文件选取
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      const typeGroup = XTypeGroup(
        label: '图片文书',
        extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      return file?.path;
    }

    // 移动端支持原生相机或图库
    final image = await _picker.pickImage(source: source);
    return image?.path;
  }
}
