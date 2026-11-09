import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../data/services/qr/qr_pack_service.dart';

/// 弹出二维码病历发送展示弹窗
Future<void> showQrCodeDisplaySheet(
  BuildContext context, {
  required String text,
  String title = '扫码发送到电脑',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => QrCodeDisplaySheet(text: text, title: title),
  );
}

class QrCodeDisplaySheet extends ConsumerStatefulWidget {
  final String text;
  final String title;

  const QrCodeDisplaySheet({
    super.key,
    required this.text,
    this.title = '扫码发送到电脑',
  });

  @override
  ConsumerState<QrCodeDisplaySheet> createState() => _QrCodeDisplaySheetState();
}

class _QrCodeDisplaySheetState extends ConsumerState<QrCodeDisplaySheet> {
  late PageController _pageController;
  int _currentIndex = 0;
  late final String _sessionId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _sessionId = QrPackService.generateSessionId(widget.text);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qrConfig = ref.watch(qrConfigProvider);
    final packets = QrPackService.splitText(
      widget.text,
      chunkSize: qrConfig.chunkSize,
      customSessionId: _sessionId,
    );

    final total = packets.length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶栏拖动条
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 24, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            if (packets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有可发送的内容', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              // 进度胶囊（如果多包）
              if (total > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '第 ${_currentIndex + 1} / $total 张 · 会话 ID: ${packets[_currentIndex].sessionId}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 二维码视图 (支持 PageView 横向滑动)
              SizedBox(
                height: 290,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: total,
                  onPageChanged: (idx) {
                    setState(() => _currentIndex = idx);
                  },
                  itemBuilder: (context, index) {
                    final pkt = packets[index];
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: pkt.content,
                          version: QrVersions.auto,
                          size: 250,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // 底部控制与指引
              if (total > 1) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('上一张'),
                        onPressed: _currentIndex > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                      Text(
                        '支持任意顺序扫码\n全部扫齐后自动打字',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('下一张'),
                        onPressed: _currentIndex < total - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '拿起扫码枪对准屏幕即可输入到电脑 (共 ${widget.text.length} 字符)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
