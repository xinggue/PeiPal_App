import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class PipelineNode {
  final String id;
  String label;
  int col;
  int row;
  List<String> slotKeys;
  int group;
  String prompt;

  PipelineNode({
    String? id,
    required this.label,
    this.col = 0,
    this.row = 0,
    List<String>? slotKeys,
    this.group = 0,
    this.prompt = '',
  })  : id = id ?? _uuid.v4(),
        slotKeys = slotKeys ?? [];

  bool get isGrouped => group > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'col': col,
        'row': row,
        'slotKeys': slotKeys,
        'group': group,
        if (prompt.isNotEmpty) 'prompt': prompt,
      };

  factory PipelineNode.fromJson(Map<String, dynamic> json) => PipelineNode(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        col: json['col'] as int? ?? 0,
        row: json['row'] as int? ?? 0,
        slotKeys: json['slotKeys'] != null
            ? List<String>.from(json['slotKeys'])
            : [],
        group: json['group'] as int? ?? 0,
        prompt: json['prompt'] as String? ?? '',
      );
}

class PipelineEdge {
  final String from;
  final String to;

  const PipelineEdge({required this.from, required this.to});

  Map<String, dynamic> toJson() => {'from': from, 'to': to};
  factory PipelineEdge.fromJson(Map<String, dynamic> json) =>
      PipelineEdge(from: json['from'] as String, to: json['to'] as String);
}

class PipelineGraph {
  List<PipelineNode> nodes;
  List<PipelineEdge> edges;
  Map<int, String> groupPrompts;

  PipelineGraph({
    List<PipelineNode>? nodes,
    List<PipelineEdge>? edges,
    Map<int, String>? groupPrompts,
  })  : nodes = nodes ?? [],
        edges = edges ?? [],
        groupPrompts = groupPrompts ?? {};

  String toJsonString() => jsonEncode({
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        if (groupPrompts.isNotEmpty)
          'groupPrompts': groupPrompts.map((k, v) => MapEntry(k.toString(), v)),
      });

  factory PipelineGraph.fromJsonString(String json) {
    if (json.isEmpty) return PipelineGraph();
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rawGroupPrompts = map['groupPrompts'] as Map<String, dynamic>?;
    return PipelineGraph(
      nodes: (map['nodes'] as List?)
              ?.map((n) => PipelineNode.fromJson(n))
              .toList() ??
          [],
      edges: (map['edges'] as List?)
              ?.map((e) => PipelineEdge.fromJson(e))
              .toList() ??
          [],
      groupPrompts: rawGroupPrompts?.map(
              (k, v) => MapEntry(int.parse(k), v.toString())) ??
          {},
    );
  }
}
