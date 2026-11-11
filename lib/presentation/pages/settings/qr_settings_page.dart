import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../data/services/qr/qr_pack_service.dart';

class QrSettingsPage extends ConsumerStatefulWidget {
  const QrSettingsPage({super.key});

  @override
  ConsumerState<QrSettingsPage> createState() => _QrSettingsPageState();
}

class _QrSettingsPageState extends ConsumerState<QrSettingsPage> {
  final _testController = TextEditingController(
    text: '标题：示例文书\n'
        '正文：这是一段用于测试扫码输入的示例文本，包含中文、数字与标点。'
        '补充：编号 A-001，时间 2026-10-26，备注可按需修改。\n'
        '条目：1. 第一项\n'
        '2. 第二项{ENTER}',
  );

  late PageController _pageController;
  int _currentCardIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _testController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qrConfig = ref.watch(qrConfigProvider);
    final text = _testController.text;
    final packets = QrPackService.splitText(
      text,
      chunkSize: qrConfig.chunkSize,
      scannerType: qrConfig.scannerType,
      customSessionId: QrPackService.generateSessionId(text),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 扫码设备类型卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(
                        '扫码设备类型',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<QrScannerType>(
                      segments: const [
                        ButtonSegment(
                          value: QrScannerType.dedicated,
                          label: Text('专用扫码器'),
                          icon: Icon(Icons.devices_other, size: 18),
                        ),
                        ButtonSegment(
                          value: QrScannerType.standard,
                          label: Text('常规扫码枪'),
                          icon: Icon(Icons.usb, size: 18),
                        ),
                      ],
                      selected: {qrConfig.scannerType},
                      onSelectionChanged: (set) {
                        ref.read(qrConfigProvider.notifier).updateScannerType(set.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    qrConfig.isStandardScanner
                        ? '常规扫码枪：直连电脑输入纯文本，自动过滤硬件按键指令，长文本不含分包协议头。'
                        : '专用扫码器：配备专用硬件接收端，支持多包乱序聚合与按键动作方案。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 参数配置卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        '分包参数配置',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('单码最大字符限制'),
                      Text(
                        '${qrConfig.chunkSize} 字符',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                  Slider(
                    value: qrConfig.chunkSize.toDouble(),
                    min: 80,
                    max: 500,
                    divisions: 42,
                    label: '${qrConfig.chunkSize} 字符',
                    onChanged: (v) {
                      ref.read(qrConfigProvider.notifier).updateChunkSize(v.round());
                    },
                  ),
                  Text(
                    '说明：普通低成本扫码枪对 150~250 字符密度的二维码识读速度最快、容错率最高。超过此长度自动切分为多张二维码。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 实时切包与测试区域
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.science_outlined, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            '多码测试与预览',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '共 ${packets.length} 张二维码',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _testController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '测试文本',
                      hintText: '输入想要测试扫码的长文本...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _testController.clear();
                          setState(() {});
                        },
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  if (packets.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('请输入测试文本以生成二维码', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else ...[
                    // 卡片索引指示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          packets.length > 1
                              ? '卡片 ${_currentCardIndex + 1} / ${packets.length} · 包含协议头: ${packets[_currentCardIndex].content.startsWith("<<SEQ:") ? "是" : "否"}'
                              : '单码模式 · 无协议头',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 二维码画板 (PageView)
                    SizedBox(
                      height: 260,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: packets.length,
                        onPageChanged: (idx) {
                          setState(() => _currentCardIndex = idx);
                        },
                        itemBuilder: (context, index) {
                          final pkt = packets[index];
                          return Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: QrImageView(
                                data: pkt.content,
                                version: QrVersions.auto,
                                size: 220,
                                backgroundColor: Colors.white,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    if (packets.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _currentCardIndex > 0
                                ? () {
                                    _pageController.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                          ),
                          Text(
                            qrConfig.isStandardScanner
                                ? '常规扫码枪请按顺序依次扫码'
                                : '左右滑动切换卡片，扫齐后自动打字',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _currentCardIndex < packets.length - 1
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
                    ],

                    const SizedBox(height: 12),
                    const Divider(),
                    const Text(
                      '当前分包原始数据预览：',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        packets[_currentCardIndex].content,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
