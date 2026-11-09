import 'package:peipal/presentation/widgets/common/app_toast.dart';
import '../common/full_screen_image_viewer.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 一份待装订的医疗文书实体
class CollateDocument {
  final String id;
  String title;
  List<String> imagePaths;

  CollateDocument({
    String? id,
    required this.title,
    required this.imagePaths,
  }) : id = id ?? _uuid.v4();

  String get coverPath => imagePaths.isNotEmpty ? imagePaths.first : '';
  int get pageCount => imagePaths.length;
  bool get isMultiPage => pageCount > 1;
}

/// 医疗文书装订与分类工作台
class DocumentCollateSheet extends StatefulWidget {
  final List<String> initialImagePaths;
  final void Function(List<CollateDocument> documents) onConfirm;

  const DocumentCollateSheet({
    super.key,
    required this.initialImagePaths,
    required this.onConfirm,
  });

  @override
  State<DocumentCollateSheet> createState() => _DocumentCollateSheetState();
}

class _DocumentCollateSheetState extends State<DocumentCollateSheet> {
  late List<CollateDocument> _documents;

  // 多选合并模式
  bool _isSelectionMode = false;
  // 有序多选列表：保存选中文书在 _documents 中的索引，顺序即合并顺序
  final List<int> _selectedIndices = [];

  @override
  void initState() {
    super.initState();
    // 初始状态：每一张照片作为一个独立的文书封面
    _documents = [];
    for (int i = 0; i < widget.initialImagePaths.length; i++) {
      _documents.add(CollateDocument(
        title: '文书 ${i + 1}',
        imagePaths: [widget.initialImagePaths[i]],
      ));
    }
  }

  void _renumberDocuments() {
    for (int i = 0; i < _documents.length; i++) {
      _documents[i].title = '文书 ${i + 1}';
    }
  }

  void _enterSelectionMode(int firstIndex) {
    setState(() {
      _isSelectionMode = true;
      _selectedIndices.clear();
      _selectedIndices.add(firstIndex);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// 按勾选顺序将多份选中的文书合并为同一份文书
  void _mergeSelectedDocuments() {
    if (_selectedIndices.length < 2) return;

    final mergedImages = <String>[];
    // 按点击顺序合并照片
    for (final idx in _selectedIndices) {
      mergedImages.addAll(_documents[idx].imagePaths);
    }

    final firstIdx = _selectedIndices.first;

    // 提取并移除非首位的被合并项（从大到小移除以防索引偏移）
    final sortedIndicesToRemove = List<int>.from(_selectedIndices)
      ..sort((a, b) => b.compareTo(a));
    for (final idx in sortedIndicesToRemove) {
      if (idx != firstIdx) {
        _documents.removeAt(idx);
      }
    }

    // 重新定位 firstIdx 并更新它的照片集
    final targetDoc = _documents.firstWhere(
      (d) =>
          d.imagePaths ==
          _documents[firstIdx < _documents.length ? firstIdx : 0].imagePaths,
      orElse: () => _documents.first,
    );
    targetDoc.imagePaths = mergedImages;

    _renumberDocuments();
    _exitSelectionMode();

    showAppToast(context, '已合并为同一份文书，共 ${mergedImages.length} 页');
  }

  /// 点击多页文书时进入二级分页整理排序界面（大图网格、拖拽重排、拆散整份、移出单页）
  Future<void> _openMultiPageEditor(CollateDocument doc) async {
    final result = await Navigator.push<_MultiPageEditorResult?>(
      context,
      MaterialPageRoute(
        builder: (_) => _DocumentPagesEditorPage(document: doc),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result.isDisassembled) {
          // 拆散整份文书为单张
          _documents.remove(doc);
          for (final p in result.paths) {
            _documents.add(CollateDocument(title: '', imagePaths: [p]));
          }
        } else {
          doc.imagePaths = result.paths;
          for (final splitP in result.splitOutPaths) {
            _documents.add(CollateDocument(title: '', imagePaths: [splitP]));
          }
          if (doc.imagePaths.isEmpty) {
            _documents.remove(doc);
          }
        }
        _renumberDocuments();
      });
    }
  }

  /// 点击单张文书时直接全屏放大浏览
  void _showFullScreenImage(String path) {
    FullScreenImageViewer.show(context, paths: [path]);
  }

  void _onConfirm() {
    if (_documents.isEmpty) return;
    Navigator.pop(context);
    widget.onConfirm(_documents);
  }

  @override
  Widget build(BuildContext context) {
    final totalPhotos = _documents.fold<int>(0, (sum, d) => sum + d.pageCount);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('文书整理与分类',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              _isSelectionMode
                  ? '点击勾选多份文书，将按序号顺序合并'
                  : '长按文书多选合并 · 单击卡片查看或排序',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (!_isSelectionMode)
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text('发送 (${_documents.length}份文书)'),
              onPressed: _onConfirm,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Banner Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.25),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '共选中 $totalPhotos 张照片，已划分为 ${_documents.length} 份文书',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // Documents Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.74,
              ),
              itemCount: _documents.length,
              itemBuilder: (context, index) {
                final doc = _documents[index];
                final isSelected = _selectedIndices.contains(index);
                final selectionOrder =
                    isSelected ? _selectedIndices.indexOf(index) + 1 : 0;

                return _buildStackedDocumentCard(
                  doc: doc,
                  index: index,
                  isSelected: isSelected,
                  selectionOrder: selectionOrder,
                );
              },
            ),
          ),

          // Bottom Bar in Selection Mode
          if (_isSelectionMode)
            SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _exitSelectionMode,
                      child: const Text('取消多选'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.call_merge_rounded, size: 18),
                      label: Text(
                        _selectedIndices.length >= 2
                            ? '按序号合并为一份文书 (${_selectedIndices.length}项)'
                            : '请至少勾选 2 份文书',
                      ),
                      onPressed: _selectedIndices.length >= 2
                          ? _mergeSelectedDocuments
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建带有层层叠叠真实纸张厚度质感的文书卡片
  Widget _buildStackedDocumentCard({
    required CollateDocument doc,
    required int index,
    required bool isSelected,
    required int selectionOrder,
  }) {
    final pageCount = doc.pageCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 底层纸张 2（3页以上文书展示，向左微倾）
        if (pageCount >= 3)
          Positioned.fill(
            child: Transform.rotate(
              angle: -0.045,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(-2, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 底层纸张 1（2页以上文书展示，向右微倾平移）
        if (pageCount >= 2)
          Positioned.fill(
            child: Transform.rotate(
              angle: 0.035,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 5,
                      offset: const Offset(3, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 单张文书专属底纸衬边：让所有文书看起来都像一份真正的纸本文书
        if (pageCount == 1)
          Positioned(
            left: 2,
            right: -2,
            top: 2,
            bottom: -2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),

        // 顶层封面主卡片
        Positioned.fill(
          child: Card(
            margin: EdgeInsets.zero,
            elevation: isSelected ? 4 : (pageCount > 1 ? 2 : 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: pageCount > 1 ? 0.35 : 0.2),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onLongPress: () {
                if (!_isSelectionMode) {
                  _enterSelectionMode(index);
                }
              },
              onTap: () {
                if (_isSelectionMode) {
                  _toggleSelection(index);
                } else {
                  // 普通单击：单张放大，多张进入二级编辑
                  if (doc.isMultiPage) {
                    _openMultiPageEditor(doc);
                  } else {
                    _showFullScreenImage(doc.coverPath);
                  }
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cover Image with Badges
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(doc.coverPath),
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey),
                          ),
                        ),

                        // Selection Order Badge (1, 2, 3...)
                        if (_isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black.withValues(alpha: 0.4),
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  isSelected ? '$selectionOrder' : '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Multi-page badge (e.g. 共 3 页)
                        if (doc.isMultiPage && !_isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.layers,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    '共 ${doc.pageCount} 页',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Multi-page edit hint
                        if (doc.isMultiPage && !_isSelectionMode)
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune,
                                      size: 11, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text('排页/拆散',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Document Title Footer
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: Theme.of(context).colorScheme.surface,
                    child: Row(
                      children: [
                        Icon(
                          doc.isMultiPage
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            doc.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 二级界面返回结果
class _MultiPageEditorResult {
  final List<String> paths;
  final List<String> splitOutPaths;
  final bool isDisassembled;

  _MultiPageEditorResult({
    required this.paths,
    this.splitOutPaths = const [],
    this.isDisassembled = false,
  });
}

/// 二级界面：多页文书大图网格、iOS Springboard 风格长按流式挤占调序、拆散整份与单张移出
class _DocumentPagesEditorPage extends StatefulWidget {
  final CollateDocument document;

  const _DocumentPagesEditorPage({required this.document});

  @override
  State<_DocumentPagesEditorPage> createState() =>
      _DocumentPagesEditorPageState();
}

class _DocumentPagesEditorPageState extends State<_DocumentPagesEditorPage> {
  late List<String> _paths;
  final List<String> _splitOutPaths = [];

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _gridKey = GlobalKey();

  // 拖拽排序状态
  int? _draggedIndex;
  int? _targetSlot;
  Offset? _dragPosition;
  Offset _dragTouchOffset = Offset.zero;
  double _gridWidth = 360;

  @override
  void initState() {
    super.initState();
    _paths = List.from(widget.document.imagePaths);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showFullScreen(int initial) {
    if (_draggedIndex != null) return;
    FullScreenImageViewer.show(
      context,
      paths: _paths,
      initialPage: initial,
    );
  }

  /// 拆散整份已合并的文书为单张文书
  Future<void> _disassembleEntireDocument() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拆散整份文书'),
        content: Text(
            '确定将「${widget.document.title}」全部拆散为 ${_paths.length + _splitOutPaths.length} 份独立的单页文书吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定拆散'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final all = [..._paths, ..._splitOutPaths];
      Navigator.pop(
        context,
        _MultiPageEditorResult(paths: all, isDisassembled: true),
      );
    }
  }

  /// 把某一张照片移出当前文书
  void _removeSinglePage(int index) {
    if (_paths.length <= 1) {
      showAppToast(context, '文书至少需保留一页，若需全部拆散请点击右上角「拆散整份」');
      return;
    }
    setState(() {
      final removed = _paths.removeAt(index);
      _splitOutPaths.add(removed);
    });

    showAppToast(context, '已移出该页（返回后将自动作为独立文书）');
  }

  void _onSave() {
    Navigator.pop(
      context,
      _MultiPageEditorResult(
        paths: _paths,
        splitOutPaths: _splitOutPaths,
        isDisassembled: false,
      ),
    );
  }

  // --- iOS 风格挤占与位置重排算法 ---

  static const double _padding = 14.0;
  static const double _spacing = 14.0;
  static const int _crossAxisCount = 2;
  static const double _aspectRatio = 0.74;

  double get _cardWidth => (_gridWidth - _padding * 2 - _spacing) / _crossAxisCount;
  double get _cardHeight => _cardWidth / _aspectRatio;

  Offset _getSlotPosition(int slot) {
    final col = slot % _crossAxisCount;
    final row = slot ~/ _crossAxisCount;
    final x = _padding + col * (_cardWidth + _spacing);
    final y = _padding + row * (_cardHeight + _spacing);
    return Offset(x, y);
  }

  /// iOS 核心挤位算法：
  /// 当被拖动的元素位于 _targetSlot 时，其他所有元素计算其动态挤出后的新槽位
  int _getEffectiveSlot(int itemIndex) {
    if (_draggedIndex == null || _targetSlot == null) return itemIndex;
    if (itemIndex == _draggedIndex) return _targetSlot!;
    final d = _draggedIndex!;
    final t = _targetSlot!;
    if (d < t) {
      // 从前往后拖：d+1 到 t 之间的所有卡片依次往前挪 1 个位置
      if (itemIndex > d && itemIndex <= t) return itemIndex - 1;
    } else if (d > t) {
      // 从后往前拖：t 到 d-1 之间的所有卡片依次往后挪 1 个位置（被挤走）
      if (itemIndex >= t && itemIndex < d) return itemIndex + 1;
    }
    return itemIndex;
  }

  void _onLongPressStart(int index, LongPressStartDetails details) {
    if (_paths.length <= 1) return;
    HapticFeedback.mediumImpact();

    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final initialSlotPos = _getSlotPosition(index);

    if (gridBox != null) {
      final localTouch = gridBox.globalToLocal(details.globalPosition);
      // 记录手指相对于该卡片左上角的触摸偏移
      _dragTouchOffset = Offset(
        localTouch.dx - initialSlotPos.dx,
        localTouch.dy - initialSlotPos.dy,
      );
    } else {
      _dragTouchOffset = Offset(_cardWidth / 2, _cardHeight / 2);
    }

    setState(() {
      _draggedIndex = index;
      _targetSlot = index;
      _dragPosition = initialSlotPos;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_draggedIndex == null) return;

    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return;

    final localFingerPos = gridBox.globalToLocal(details.globalPosition);
    final cardLeft = localFingerPos.dx - _dragTouchOffset.dx;
    final cardTop = localFingerPos.dy - _dragTouchOffset.dy;
    final newPos = Offset(cardLeft, cardTop);

    // 计算拖动卡片的当前视觉中心点
    final cx = newPos.dx + _cardWidth / 2;
    final cy = newPos.dy + _cardHeight / 2;
    final dragCenter = Offset(cx, cy);

    // 寻找距离中心最近的候选插槽
    int bestSlot = _targetSlot ?? _draggedIndex!;
    double minDistance = double.infinity;

    for (int s = 0; s < _paths.length; s++) {
      final slotPos = _getSlotPosition(s);
      final slotCenter = Offset(slotPos.dx + _cardWidth / 2, slotPos.dy + _cardHeight / 2);
      final dist = (dragCenter - slotCenter).distance;
      if (dist < minDistance) {
        minDistance = dist;
        bestSlot = s;
      }
    }

    // 引入 iOS 滞后死区阈值（Hysteresis Buffer: 38 像素）
    // 只有当明显更靠近新槽位时才触发挤位，彻底消除分界线附近高频抖动！
    if (bestSlot != _targetSlot) {
      final currentPos = _getSlotPosition(_targetSlot!);
      final currentCenter = Offset(currentPos.dx + _cardWidth / 2, currentPos.dy + _cardHeight / 2);
      final currentDist = (dragCenter - currentCenter).distance;

      if (currentDist - minDistance > 38.0) {
        HapticFeedback.selectionClick();
        setState(() {
          _targetSlot = bestSlot;
          _dragPosition = newPos;
        });
      } else {
        setState(() {
          _dragPosition = newPos;
        });
      }
    } else {
      setState(() {
        _dragPosition = newPos;
      });
    }

    // 边缘轻柔自动滚动
    _handleAutoScroll(details.globalPosition);
  }

  void _handleAutoScroll(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localDy = box.globalToLocal(globalPos).dy;
    const threshold = 100.0;
    if (localDy < threshold && _scrollController.offset > 0) {
      _scrollController.animateTo(
        (_scrollController.offset - 15).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 30),
        curve: Curves.linear,
      );
    } else if (localDy > box.size.height - threshold &&
        _scrollController.offset < _scrollController.position.maxScrollExtent) {
      _scrollController.animateTo(
        (_scrollController.offset + 15).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 30),
        curve: Curves.linear,
      );
    }
  }

  void _onLongPressEnd() {
    if (_draggedIndex == null) return;

    final from = _draggedIndex!;
    final to = _targetSlot ?? from;

    if (from != to) {
      HapticFeedback.mediumImpact();
      final item = _paths.removeAt(from);
      _paths.insert(to, item);
    }

    setState(() {
      _draggedIndex = null;
      _targetSlot = null;
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.document.title} · 页面整理 (${_paths.length}页)'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.call_split_rounded, size: 16),
            label: const Text('拆散整份'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _disassembleEntireDocument,
          ),
          FilledButton(
            onPressed: _onSave,
            child: const Text('完成'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Banner Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.blue.withValues(alpha: 0.08),
            child: const Row(
              children: [
                Icon(Icons.touch_app_outlined, size: 16, color: Colors.blue),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '长按照片拖拽，其他照片将如 iOS 般顺畅挤走重排；点击可全屏放大浏览',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // Fluid iOS-style Drag & Displace Grid
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _gridWidth = constraints.maxWidth;
                final totalRows = (_paths.length + 1) ~/ _crossAxisCount;
                final totalHeight = _padding * 2 +
                    (totalRows > 0 ? totalRows * _cardHeight + (totalRows - 1) * _spacing : 0);

                return SingleChildScrollView(
                  key: _gridKey,
                  controller: _scrollController,
                  physics: _draggedIndex != null
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: totalHeight < constraints.maxHeight
                        ? constraints.maxHeight
                        : totalHeight,
                    child: Stack(
                      children: [
                        // 所有卡片均保留在树中以维持手势监听（正在被拖动的在原槽位显示半透明虚影）
                        for (int i = 0; i < _paths.length; i++)
                          _buildAnimatedCardItem(
                            index: i,
                            path: _paths[i],
                            cardWidth: _cardWidth,
                            cardHeight: _cardHeight,
                            isBeingDragged: i == _draggedIndex,
                          ),

                        // 当前正在拖动的卡片：绝对定位浮在最顶层，跟随手指实时移动并放大
                        if (_draggedIndex != null && _dragPosition != null)
                          Positioned(
                            left: _dragPosition!.dx,
                            top: _dragPosition!.dy,
                            width: _cardWidth,
                            height: _cardHeight,
                            child: IgnorePointer(
                              child: _buildDraggedFloatingCard(
                                index: _draggedIndex!,
                                path: _paths[_draggedIndex!],
                                cardWidth: _cardWidth,
                                cardHeight: _cardHeight,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 槽位卡片：根据 _getEffectiveSlot 动态计算当前归属槽位，并以 250ms easeOutCubic 丝滑滑动
  Widget _buildAnimatedCardItem({
    required int index,
    required String path,
    required double cardWidth,
    required double cardHeight,
    required bool isBeingDragged,
  }) {
    final effectiveSlot = _getEffectiveSlot(index);
    final pos = _getSlotPosition(effectiveSlot);

    return AnimatedPositioned(
      key: ValueKey(path),
      duration: isBeingDragged ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: cardWidth,
      height: cardHeight,
      child: GestureDetector(
        onTap: () => _showFullScreen(index),
        onLongPressStart: (details) => _onLongPressStart(index, details),
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: (_) => _onLongPressEnd(),
        onLongPressCancel: _onLongPressEnd,
        child: Opacity(
          opacity: isBeingDragged ? 0.25 : 1.0,
          child: _buildCardContent(
            path: path,
            displayPage: effectiveSlot + 1,
            isCover: effectiveSlot == 0,
            onRemove: isBeingDragged ? null : () => _removeSinglePage(index),
          ),
        ),
      ),
    );
  }

  /// 正在被拖动的顶层悬浮卡片
  Widget _buildDraggedFloatingCard({
    required int index,
    required String path,
    required double cardWidth,
    required double cardHeight,
  }) {
    final currentSlot = _targetSlot ?? index;

    return Transform.scale(
      scale: 1.06,
      child: Material(
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: _buildCardContent(
          path: path,
          displayPage: currentSlot + 1,
          isCover: currentSlot == 0,
          isDragging: true,
          onRemove: null,
        ),
      ),
    );
  }

  Widget _buildCardContent({
    required String path,
    required int displayPage,
    required bool isCover,
    bool isDragging = false,
    VoidCallback? onRemove,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDragging
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
          width: isDragging ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),

                // 左上角醒目页码标号（随实时挤位动态更新）
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCover
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: Text(
                      isCover ? '第 1 页 (封面)' : '第 $displayPage 页',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 右上角移出单页按钮
                if (onRemove != null && !isDragging)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onRemove,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                // 底部放大核验提示
                if (!isDragging)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('放大',
                              style: TextStyle(color: Colors.white, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 底部文件名与手柄指示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    path.split('/').last,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
