import 'dart:io';
import 'package:flutter/material.dart';

/// 全屏大图查看器
/// 支持多页左右滑动、缩放 (InteractiveViewer)、大图下采样防爆内存 (cacheWidth: 1600)
class FullScreenImageViewer extends StatefulWidget {
  final List<String> paths;
  final int initialPage;

  const FullScreenImageViewer({
    super.key,
    required this.paths,
    this.initialPage = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required List<String> paths,
    int initialPage = 0,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          paths: paths,
          initialPage: initialPage,
        ),
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.paths.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          pageCount > 1
              ? '${_currentPage + 1} / $pageCount 页'
              : '图片详情',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemCount: pageCount,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(widget.paths[i]),
              cacheWidth: 1600,
              errorBuilder: (_, error, stack) => const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
