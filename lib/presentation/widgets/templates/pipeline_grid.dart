import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:peipal/presentation/widgets/common/app_sheet.dart';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../domain/models/pipeline_graph.dart';
import '../../../../domain/models/template.dart';

class PipelineGrid extends StatefulWidget {
  final PipelineGraph graph;
  final List<TemplateSlot> allSlots;
  final Set<String> assignedSlots;
  final void Function() onChanged;

  const PipelineGrid({
    super.key,
    required this.graph,
    required this.allSlots,
    required this.assignedSlots,
    required this.onChanged,
  });

  static const gridW = 240;
  static const gridH = 60;
  static const pad = 14;
  static const nodeW = 150.0;
  static const nodeH = 56.0;
  static const portD = 40.0; // port diameter ~75% of node height

  @override
  State<PipelineGrid> createState() => _PipelineGridState();
}

class _PipelineGridState extends State<PipelineGrid> {
  int _connectingFromIdx = -1;
  int _movingIdx = -1;
  int _movingGroup = -1;
  bool _multiMove = false;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  int _nextGroup = 1;

  int get _maxCol => widget.graph.nodes.fold(0, (m,n) => n.col>m?n.col:m) + 2;
  int get _maxRow => widget.graph.nodes.fold(0, (m,n) => n.row>m?n.row:m) + 2;

  Offset _pos(PipelineNode n) => Offset((n.col*PipelineGrid.gridW+PipelineGrid.pad).toDouble(), (n.row*PipelineGrid.gridH+PipelineGrid.pad).toDouble());
  Rect _rect(PipelineNode n) {
    final p=_folderPos(n);
    return n.isGrouped
        ? Rect.fromLTWH(p.dx,p.dy,PipelineGrid.nodeW,PipelineGrid.nodeH*2)
        : Rect.fromLTWH(p.dx,p.dy,PipelineGrid.nodeW,PipelineGrid.nodeH);
  }

  /// Position of a node's folder (or itself if standalone). Grouped nodes
  /// all map to the folder = position of the group's first member.
  Offset _folderPos(PipelineNode n) {
    if (!n.isGrouped) return _pos(n);
    final members = widget.graph.nodes.where((x) => x.group == n.group).toList();
    if (members.isEmpty) return _pos(n);
    return _pos(members.first);
  }

  void _addNode() {
    widget.graph.nodes.add(PipelineNode(label:'新节点',col:0,row:_maxRow));
    widget.onChanged(); setState((){});
  }

  void _removeNode(int i) {
    final n=widget.graph.nodes[i];
    widget.assignedSlots.removeAll(n.slotKeys);
    widget.graph.edges.removeWhere((e)=>e.from==n.id||e.to==n.id);
    widget.graph.nodes.removeAt(i);
    widget.onChanged(); setState((){});
  }

  void _showNodeMenu(int i) {
    final node = widget.graph.nodes[i];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(node.label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _editNode(i);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('移动位置'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _movingIdx = i);
                showAppToast(context, '使用下方方向键移动节点');
              },
            ),
            if(node.isGrouped)
              ListTile(
                leading: const Icon(Icons.group_remove, color: Colors.purple),
                title: const Text('取消成组', style: TextStyle(color: Colors.purple)),
                onTap: () {
                  Navigator.pop(ctx);
                  _ungroup(node.group);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _removeNode(i);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNode(int i) async {
    final node=widget.graph.nodes[i];
    final lc=TextEditingController(text:node.label);
    final pc=TextEditingController(text:node.prompt);
    final sel=Set<String>.from(node.slotKeys);
    try {
      await showAppSheet(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>Padding(
        padding: const EdgeInsets.all(16),
        child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('编辑节点',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),
          TextField(controller:lc,decoration:const InputDecoration(labelText:'标签',border:OutlineInputBorder(),isDense:true)),
          const SizedBox(height:8),
          Text('字段',style:TextStyle(fontSize:13,color:Colors.grey[600])),
          ...widget.allSlots.where((s)=>sel.contains(s.key)||!widget.assignedSlots.contains(s.key)||node.slotKeys.contains(s.key)).map((slot)=>
            CheckboxListTile(dense:true,title:Text(slot.label,style:const TextStyle(fontSize:13)),value:sel.contains(slot.key),
              onChanged:(v){ss((){
                if(v==true){sel.add(slot.key);}
                else{sel.remove(slot.key);}
              });},
            )),
          const SizedBox(height:8),
          TextField(controller:pc,maxLines:3,decoration:const InputDecoration(
            labelText:'节点提示词（可选）',border:OutlineInputBorder(),
            hintText:'如：用规范用语，列出可选项',
          )),
          const SizedBox(height:12),
          FilledButton(onPressed:(){
            widget.assignedSlots.removeAll(node.slotKeys);
            widget.assignedSlots.addAll(sel);
            node.label=lc.text.trim();
            node.prompt=pc.text.trim();
            node.slotKeys=sel.toList();
            widget.onChanged();
            setState((){});
            Navigator.pop(ctx);
          },child:const Text('保存')),
        ])),
      )));
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lc.dispose();
        pc.dispose();
      });
    }
  }

  void _onPort(int i, bool out) {
    if (_selectMode) return; // mask node ops during selection
    if(_connectingFromIdx<0){
      if(out) setState(()=>_connectingFromIdx=i);
    } else {
      if(!out){
        final f=widget.graph.nodes[_connectingFromIdx].id, t=widget.graph.nodes[i].id;
        final ex=widget.graph.edges.any((e)=>e.from==f&&e.to==t);
        ex?widget.graph.edges.removeWhere((e)=>e.from==f&&e.to==t):widget.graph.edges.add(PipelineEdge(from:f,to:t));
        widget.onChanged();
      }
      setState(()=>_connectingFromIdx=-1);
    }
  }

  /// Folder port: uses the group's first member as the edge endpoint.
  void _onFolderPort(int gid, bool out) {
    if (_selectMode) return;
    final memberIdx = widget.graph.nodes.indexWhere((n) => n.group == gid);
    if (memberIdx < 0) return;

    if (_connectingFromIdx < 0) {
      if (out) setState(() => _connectingFromIdx = memberIdx);
    } else {
      if (!out && memberIdx != _connectingFromIdx) {
        final f = widget.graph.nodes[_connectingFromIdx].id;
        final t = widget.graph.nodes[memberIdx].id;
        final ex = widget.graph.edges.any((e) => e.from == f && e.to == t);
        ex
            ? widget.graph.edges.removeWhere((e) => e.from == f && e.to == t)
            : widget.graph.edges.add(PipelineEdge(from: f, to: t));
        widget.onChanged();
      }
      setState(() => _connectingFromIdx = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Text('暂无节点',style:TextStyle(color:Colors.grey[400],fontSize:16)),
        const SizedBox(height:12),
        OutlinedButton.icon(icon:const Icon(Icons.add,size:16),label:const Text('添加节点'),onPressed:_addNode),
      ]));
    }

    final cw=max(600.0,_maxCol*PipelineGrid.gridW+200.0);
    final ch=max(400.0,_maxRow*PipelineGrid.gridH+200.0);

    return Column(children:[
      // Toolbar
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal:8,vertical:4),
        child: Row(children:[
          _toolbarBtn(_selectMode?Icons.close:Icons.checklist, _selectMode?'退出多选':'多选节点',
            ()=>setState((){_selectMode=!_selectMode;_selectedIds.clear();})),
          const SizedBox(width:8),
          _toolbarBtn(Icons.add, '新增节点', _addNode),
          const SizedBox(width:8),
          if(_selectMode)...[
            _toolbarBtn(Icons.group, '成组(${_selectedIds.length})', _selectedIds.length>=2?_groupSelected:null),
            const SizedBox(width:8),
            _toolbarBtn(Icons.open_with, '移动(${_selectedIds.length})', _selectedIds.isNotEmpty?()=>setState(()=>_multiMove=!_multiMove):null),
            const SizedBox(width:8),
            _toolbarBtn(Icons.delete, '删除(${_selectedIds.length})', _selectedIds.isNotEmpty?_deleteSelected:null),
          ],
          if(!_selectMode)...[
            const SizedBox(width:8),
            _toolbarBtn(Icons.restart_alt, '还原初始', _resetPipeline),
          ],
          const SizedBox(width:12),
          Text('${widget.graph.nodes.length}节点 · ${widget.graph.edges.length}连线',style:TextStyle(fontSize:11,color:Colors.grey[500])),
        ]),
      ),
      Expanded(child:Stack(children:[
        SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:SingleChildScrollView(scrollDirection:Axis.vertical,
            child:SizedBox(width:cw,height:ch,
              child:Stack(children:[
                // Standalone nodes
                for(int i=0;i<widget.graph.nodes.length;i++)
                  if(!widget.graph.nodes[i].isGrouped)
                    Positioned(left:_pos(widget.graph.nodes[i]).dx,top:_pos(widget.graph.nodes[i]).dy,
                      child:_NodeCard(node:widget.graph.nodes[i],connecting:_connectingFromIdx==i,moving:_movingIdx==i,
                        selected:_selectMode&&_selectedIds.contains(widget.graph.nodes[i].id),
                        onTap:()=>_selectMode
                          ?setState(()=>_selectedIds.contains(widget.graph.nodes[i].id)
                              ?_selectedIds.remove(widget.graph.nodes[i].id)
                              :_selectedIds.add(widget.graph.nodes[i].id))
                          :_showNodeMenu(i),
                        onDrag:(dx,dy){setState((){widget.graph.nodes[i].col=max(0,widget.graph.nodes[i].col+dx);widget.graph.nodes[i].row=max(0,widget.graph.nodes[i].row+dy);});widget.onChanged();},
                        onOut:()=>_onPort(i,true),onIn:()=>_onPort(i,false),
                        onLongPress:()=>_selectMode?setState((){_selectedIds.add(widget.graph.nodes[i].id);_showNodeMenu(i);}):_showNodeMenu(i),
                      )),
                // Folder cards for groups
                for(final gid in _groupIds())
                  Positioned(left:_folderPos(widget.graph.nodes.firstWhere((n)=>n.group==gid)).dx,
                    top:_folderPos(widget.graph.nodes.firstWhere((n)=>n.group==gid)).dy,
                    child:_FolderCard(
                      members:widget.graph.nodes.where((n)=>n.group==gid).toList(),
                      connecting:_connectingFromIdx>=0&&_connectingFromIdx<widget.graph.nodes.length&&widget.graph.nodes[_connectingFromIdx].group==gid,
                      onTap:()=>_showFolderMenu(gid),
                      onIn:()=>_onFolderPort(gid,false),
                      onOut:()=>_onFolderPort(gid,true),
                    )),
                // Edges on top of everything (IgnorePointer → never blocks taps)
                IgnorePointer(
                  child: CustomPaint(size:Size(cw,ch),painter:_EdgePainter(graph:widget.graph,nodes:widget.graph.nodes,posFn:_folderPos,rectFn:_rect)),
                ),
              ]),
            ))),
        // Floating move controls when moving a node, group, or multi-selection
        if((_movingIdx>=0 && _movingIdx<widget.graph.nodes.length) || (_movingGroup>=0 && _groupIds().contains(_movingGroup)) || _multiMove)
          Positioned(
            left:0,right:0,bottom:80,
            child:Center(child:Container(
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
              decoration:BoxDecoration(
                color:Theme.of(context).colorScheme.surface.withValues(alpha:0.95),
                borderRadius:BorderRadius.circular(10),
                boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:0.15),blurRadius:8)],
                border:Border.all(color:Colors.orange.withValues(alpha:0.4)),
              ),
              child:Column(mainAxisSize:MainAxisSize.min,children:[
                Text('移动：${_moveTargetLabel()}',style:TextStyle(fontSize:12,color:Colors.orange[800],fontWeight:FontWeight.w600)),
                const SizedBox(height:6),
                Row(mainAxisSize:MainAxisSize.min,children:[
                  _dirBtn(Icons.keyboard_arrow_left,()=>_doMove(-1,0)),
                  const SizedBox(width:4),
                  Column(mainAxisSize:MainAxisSize.min,children:[
                    _dirBtn(Icons.keyboard_arrow_up,()=>_doMove(0,-1)),
                    const SizedBox(height:4),
                    _dirBtn(Icons.keyboard_arrow_down,()=>_doMove(0,1)),
                  ]),
                  const SizedBox(width:4),
                  _dirBtn(Icons.keyboard_arrow_right,()=>_doMove(1,0)),
                  const SizedBox(width:12),
                  _dirBtn(Icons.check,()=>setState((){_movingIdx=-1;_movingGroup=-1;_multiMove=false;}),green:true),
                ]),
              ]),
            )),
          ),
      ])),
    ]);
  }

  Widget _toolbarBtn(IconData ic,String label,VoidCallback? cb)=>OutlinedButton.icon(
    onPressed:cb,icon:Icon(ic,size:16),label:Text(label,style:const TextStyle(fontSize:12)),
    style:OutlinedButton.styleFrom(visualDensity:VisualDensity.compact,padding:const EdgeInsets.symmetric(horizontal:8,vertical:4)),
  );

  void _move(int dc,int dr) {
    final n=widget.graph.nodes[_movingIdx];
    n.col=max(0,n.col+dc);
    n.row=max(0,n.row+dr);
    widget.onChanged();
    setState((){});
  }

  String _moveTargetLabel() {
    if (_multiMove) {
      return '多选(${_selectedIds.length})';
    }
    if (_movingIdx >= 0 && _movingIdx < widget.graph.nodes.length) {
      return widget.graph.nodes[_movingIdx].label;
    }
    if (_movingGroup >= 0) {
      final members = widget.graph.nodes.where((n) => n.group == _movingGroup).toList();
      return '分组(${members.length})';
    }
    return '';
  }

  void _doMove(int dc, int dr) {
    if (_multiMove) {
      _moveSelected(dc, dr);
    } else if (_movingIdx >= 0 && _movingIdx < widget.graph.nodes.length) {
      _move(dc, dr);
    } else if (_movingGroup >= 0) {
      _moveGroup(_movingGroup, dc, dr);
    }
  }

  void _groupSelected() {
    if (_selectedIds.length < 2) return;
    final gid = _nextGroup++;
    for (final n in widget.graph.nodes) {
      if (_selectedIds.contains(n.id)) {
        n.group = gid;
      }
    }
    _selectedIds.clear();
    _selectMode = false;
    widget.onChanged();
    setState((){});
  }

  void _deleteSelected() {
    for (final n in List.of(widget.graph.nodes)) {
      if (_selectedIds.contains(n.id)) {
        widget.assignedSlots.removeAll(n.slotKeys);
        widget.graph.edges.removeWhere((e) => e.from == n.id || e.to == n.id);
        widget.graph.nodes.remove(n);
      }
    }
    _selectedIds.clear();
    _selectMode = false;
    widget.onChanged();
    setState((){});
  }

  void _moveSelected(int dc, int dr) {
    for (final n in widget.graph.nodes) {
      if (_selectedIds.contains(n.id)) {
        n.col = max(0, n.col + dc);
        n.row = max(0, n.row + dr);
      }
    }
    widget.onChanged();
    setState((){});
  }

  void _resetPipeline() {
    widget.graph.nodes.clear();
    widget.graph.edges.clear();
    widget.assignedSlots.clear();
    widget.graph.nodes.add(PipelineNode(
      label: '起点', col: 0, row: 0,
    ));
    for (int i = 0; i < widget.allSlots.length; i++) {
      final slot = widget.allSlots[i];
      widget.graph.nodes.add(PipelineNode(
        label: slot.label, slotKeys: [slot.key], col: 1, row: i,
      ));
      widget.assignedSlots.add(slot.key);
    }
    _selectMode = false;
    _selectedIds.clear();
    _multiMove = false;
    _movingIdx = -1;
    _movingGroup = -1;
    widget.onChanged();
    setState((){});
  }

  void _ungroup(int gid) {
    for (final n in widget.graph.nodes) {
      if (n.group == gid) n.group = 0;
    }
    widget.onChanged();
    setState((){});
  }

  List<int> _groupIds() =>
      widget.graph.nodes.where((n) => n.isGrouped).map((n) => n.group).toSet().toList();

  void _moveGroup(int gid, int dc, int dr) {
    for (final n in widget.graph.nodes) {
      if (n.group == gid) {
        n.col = max(0, n.col + dc);
        n.row = max(0, n.row + dr);
      }
    }
    widget.onChanged();
    setState((){});
  }

  void _showFolderMenu(int gid) {
    final members = widget.graph.nodes.where((n) => n.group == gid).toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('分组 (${members.length}个节点)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...members.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('• ${m.label}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ),
                )),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('分组提示词'),
              onTap: () {
                Navigator.pop(ctx);
                _editGroupPrompt(gid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('移动位置'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _movingGroup = gid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_remove, color: Colors.purple),
              title: const Text('取消成组', style: TextStyle(color: Colors.purple)),
              onTap: () {
                Navigator.pop(ctx);
                _ungroup(gid);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _editGroupPrompt(int gid) {
    final pc = TextEditingController(
        text: widget.graph.groupPrompts[gid] ?? '');
    showAppSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('分组提示词', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: pc,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '整个分组共享的提示词，如：请按要求分点列出',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final text = pc.text.trim();
                if (text.isEmpty) {
                  widget.graph.groupPrompts.remove(gid);
                } else {
                  widget.graph.groupPrompts[gid] = text;
                }
                widget.onChanged();
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _dirBtn(IconData ic,VoidCallback cb,{bool green=false})=>InkWell(
    onTap:cb,borderRadius:BorderRadius.circular(8),
    child:Container(
      width:36,height:36,
      decoration:BoxDecoration(
        color:green?Colors.green.withValues(alpha:0.15):Colors.orange.withValues(alpha:0.1),
        borderRadius:BorderRadius.circular(8),
        border:Border.all(color:green?Colors.green:Colors.orange,width:1.5),
      ),
      child:Icon(ic,size:20,color:green?Colors.green[700]:Colors.orange[700]),
    ),
  );
}

class _NodeCard extends StatefulWidget {
  final PipelineNode node;final bool connecting;final bool moving;final bool selected;
  final VoidCallback onTap,onOut,onIn,onLongPress;
  final void Function(int,int) onDrag;
  const _NodeCard({required this.node,required this.connecting,required this.moving,required this.selected,required this.onTap,required this.onLongPress,required this.onDrag,required this.onOut,required this.onIn});
  @override State<_NodeCard> createState()=>_NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  @override Widget build(BuildContext context) {
    final co=widget.connecting;
    final mv=widget.moving;
    final sel=widget.selected;
    final grp=widget.node.isGrouped;
    final portD=PipelineGrid.portD;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Node body — fixed height so ports center correctly
        SizedBox(
          width:PipelineGrid.nodeW,
          height:PipelineGrid.nodeH,
          child:Stack(clipBehavior:Clip.none,children:[
            Positioned.fill(child:GestureDetector(
              behavior:HitTestBehavior.opaque,
              onTap:widget.onTap,
              onLongPress:widget.onLongPress,
              child:Container(decoration:BoxDecoration(
              color:sel?Colors.green.withValues(alpha:0.12):(mv?Colors.orange.withValues(alpha:0.08):(co?Colors.blue.withValues(alpha:0.05):(grp?Colors.purple.withValues(alpha:0.06):Theme.of(context).colorScheme.surface))),
              borderRadius:BorderRadius.circular(6),
              border:Border.all(color:sel?Colors.green:(mv?Colors.orange:(co?Colors.blue:(grp?Colors.purple.withValues(alpha:0.5):Theme.of(context).colorScheme.outline.withValues(alpha:0.2)))),width:mv||sel?2:1),
              boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:0.04),blurRadius:3)]),
              child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
                Text(widget.node.label,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:11)),
                if(widget.node.slotKeys.isNotEmpty)
                  Text('${widget.node.slotKeys.length}字段',style:TextStyle(fontSize:9,color:Colors.grey[500])),
              ]))))),
            // Selection checkbox — rendered last so it's on top
            // Input port — centered vertically, larger hit area
            Positioned(left:-portD/2,top:0,bottom:0,
              child:Center(child:GestureDetector(
                behavior:HitTestBehavior.opaque,
                onTap:widget.onIn,
                child:Container(
                  width:portD+14,height:portD+14,
                  alignment:Alignment.center,
                  child:_port(false),
                ),
              ))),
            // Output port
            Positioned(right:-portD/2,top:0,bottom:0,
              child:Center(child:GestureDetector(
                behavior:HitTestBehavior.opaque,
                onTap:widget.onOut,
                child:Container(
                  width:portD+14,height:portD+14,
                  alignment:Alignment.center,
                  child:_port(co),
                ),
              ))),
            if(sel)
              Positioned(left:2,top:2,child:Icon(Icons.check_circle,size:14,color:Colors.green)),
            if(grp&&!sel)
              Positioned(left:2,top:2,child:Icon(Icons.group,size:12,color:Colors.purple)),
          ]),
        ),
      ],
    );
  }
  Widget _port(bool a)=>Container(width:PipelineGrid.portD,height:PipelineGrid.portD,decoration:BoxDecoration(shape:BoxShape.circle,color:a?Colors.blue:Colors.white,border:Border.all(color:a?Colors.blue:Colors.grey[400]!,width:2)),child:a?Icon(Icons.arrow_forward,size:16,color:Colors.white):null);
}

class _FolderCard extends StatelessWidget {
  final List<PipelineNode> members;
  final VoidCallback onTap;
  final VoidCallback onIn;
  final VoidCallback onOut;
  final bool connecting;
  const _FolderCard({
    required this.members, required this.onTap,
    required this.onIn, required this.onOut,
    this.connecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final portD = PipelineGrid.portD;
    final w = PipelineGrid.nodeW;
    final h = PipelineGrid.nodeH * 2;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: connecting
                  ? Colors.blue.withValues(alpha: 0.08)
                  : Colors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: connecting
                    ? Colors.blue
                    : Colors.purple.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.folder, size: 16, color: Colors.purple),
                  const SizedBox(width: 4),
                  Text('分组 (${members.length})',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
                ]),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in members.take(2))
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: _memberLabel(m.label),
                        ),
                      if (members.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text('+${members.length - 2} 更多',
                              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
        // Input port — centered vertically
        Positioned(left: -portD / 2, top: 0, bottom: 0,
          child: Center(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onIn,
            child: Container(
              width: portD + 14, height: portD + 14,
              alignment: Alignment.center,
              child: _port(false),
            ),
          ))),
        // Output port
        Positioned(right: -portD / 2, top: 0, bottom: 0,
          child: Center(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOut,
            child: Container(
              width: portD + 14, height: portD + 14,
              alignment: Alignment.center,
              child: _port(connecting),
            ),
          ))),
      ]),
    );
  }

  Widget _memberLabel(String label) => Row(
        children: [
          Text('• ', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  Widget _port(bool a) => Container(
    width: PipelineGrid.portD, height: PipelineGrid.portD,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: a ? Colors.blue : Colors.white,
      border: Border.all(color: a ? Colors.blue : Colors.grey[400]!, width: 2),
    ),
    child: a ? const Icon(Icons.arrow_forward, size: 16, color: Colors.white) : null,
  );
}

class _EdgePainter extends CustomPainter {
  final PipelineGraph graph;final List<PipelineNode> nodes;
  final Offset Function(PipelineNode) posFn;final Rect Function(PipelineNode) rectFn;
  _EdgePainter({required this.graph,required this.nodes,required this.posFn,required this.rectFn});
  @override void paint(Canvas c, Size s) {
    final p=Paint()..color=Colors.blueGrey[300]!..strokeWidth=2..style=PaintingStyle.stroke;
    final m={for(final n in nodes)n.id:n};
    for(final e in graph.edges){
      final f=m[e.from],t=m[e.to];if(f==null||t==null)continue;
      final fr=rectFn(f),tr=rectFn(t);
      final start=Offset(fr.right,fr.center.dy),end=Offset(tr.left,tr.center.dy);
      final mx=(start.dx+end.dx)/2;
      c.drawPath(Path()..moveTo(start.dx,start.dy)..cubicTo(mx,start.dy,mx,end.dy,end.dx,end.dy),p);
      c.drawPath(Path()..moveTo(end.dx,end.dy)..lineTo(end.dx-8,end.dy-5)..lineTo(end.dx-8,end.dy+5)..close(),Paint()..color=Colors.blueGrey[300]!..style=PaintingStyle.fill);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter o)=>true;
}
