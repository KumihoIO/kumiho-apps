// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:ui';

/// Types of nodes in the lineage graph
enum GraphNodeType {
  project,
  space,
  subSpace,
  item,
  revision,
  artifact,
  model,     // AI/3D model
  lora,      // LoRA model
  image,     // Input image
  workflow,  // ComfyUI workflow
}

/// Extension for GraphNodeType display properties
extension GraphNodeTypeExtension on GraphNodeType {
  String get label {
    switch (this) {
      case GraphNodeType.project:
        return 'Project';
      case GraphNodeType.space:
        return 'Space';
      case GraphNodeType.subSpace:
        return 'Sub-Space';
      case GraphNodeType.item:
        return 'Item';
      case GraphNodeType.revision:
        return 'Revision';
      case GraphNodeType.artifact:
        return 'Artifact';
      case GraphNodeType.model:
        return 'Model';
      case GraphNodeType.lora:
        return 'LoRA';
      case GraphNodeType.image:
        return 'Image';
      case GraphNodeType.workflow:
        return 'Workflow';
    }
  }

  Color get color {
    switch (this) {
      case GraphNodeType.project:
        return const Color(0xFF4A4A4A);  // Dark grey (matching browser UI)
      case GraphNodeType.space:
        return const Color(0xFF4ECDC4);  // Teal
      case GraphNodeType.subSpace:
        return const Color(0xFF45B7AA);  // Darker teal
      case GraphNodeType.item:
        return const Color(0xFFFF6B6B);  // Coral red
      case GraphNodeType.revision:
        return const Color(0xFFD4A574);  // Warm amber (softer, better readability)
      case GraphNodeType.artifact:
        return const Color(0xFF95E1D3);  // Mint
      case GraphNodeType.model:
        return const Color(0xFFE17055);  // Orange
      case GraphNodeType.lora:
        return const Color(0xFFFFB347);  // Orange-yellow
      case GraphNodeType.image:
        return const Color(0xFF74B9FF);  // Light blue
      case GraphNodeType.workflow:
        return const Color(0xFFA29BFE);  // Lavender
    }
  }

  String get icon {
    switch (this) {
      case GraphNodeType.project:
        return '📁';
      case GraphNodeType.space:
        return '📂';
      case GraphNodeType.subSpace:
        return '📄';
      case GraphNodeType.item:
        return '🎬';
      case GraphNodeType.revision:
        return '🔄';
      case GraphNodeType.artifact:
        return '📦';
      case GraphNodeType.model:
        return '🤖';
      case GraphNodeType.lora:
        return '🎨';
      case GraphNodeType.image:
        return '🖼️';
      case GraphNodeType.workflow:
        return '⚙️';
    }
  }
}

/// Represents a node in the lineage graph
class GraphNode {
  final String id;
  final String name;
  final GraphNodeType type;
  final String? kref;
  final Map<String, dynamic> metadata;
  Offset position;
  bool isSelected;

  GraphNode({
    required this.id,
    required this.name,
    required this.type,
    this.kref,
    this.metadata = const {},
    this.position = Offset.zero,
    this.isSelected = false,
  });

  GraphNode copyWith({
    String? id,
    String? name,
    GraphNodeType? type,
    String? kref,
    Map<String, dynamic>? metadata,
    Offset? position,
    bool? isSelected,
  }) {
    return GraphNode(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      kref: kref ?? this.kref,
      metadata: metadata ?? this.metadata,
      position: position ?? this.position,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

/// Types of edges in the lineage graph
enum GraphEdgeType {
  belongsTo,
  createdFrom,
  referenced,
  dependsOn,
  derivedFrom,
  contains,
}

/// Extension for GraphEdgeType display properties
extension GraphEdgeTypeExtension on GraphEdgeType {
  String get label {
    switch (this) {
      case GraphEdgeType.belongsTo:
        return 'belongs to';
      case GraphEdgeType.createdFrom:
        return 'created from';
      case GraphEdgeType.referenced:
        return 'references';
      case GraphEdgeType.dependsOn:
        return 'depends on';
      case GraphEdgeType.derivedFrom:
        return 'derived from';
      case GraphEdgeType.contains:
        return 'contains';
    }
  }

  Color get color {
    switch (this) {
      case GraphEdgeType.belongsTo:
        return const Color(0xFF888888);
      case GraphEdgeType.createdFrom:
        return const Color(0xFF4ECDC4);
      case GraphEdgeType.referenced:
        return const Color(0xFF74B9FF);
      case GraphEdgeType.dependsOn:
        return const Color(0xFFFF6B6B);
      case GraphEdgeType.derivedFrom:
        return const Color(0xFFFFE66D);
      case GraphEdgeType.contains:
        return const Color(0xFFA29BFE);
    }
  }

  static GraphEdgeType fromString(String type) {
    switch (type.toUpperCase()) {
      case 'BELONGS_TO':
        return GraphEdgeType.belongsTo;
      case 'CREATED_FROM':
        return GraphEdgeType.createdFrom;
      case 'REFERENCED':
        return GraphEdgeType.referenced;
      case 'DEPENDS_ON':
        return GraphEdgeType.dependsOn;
      case 'DERIVED_FROM':
        return GraphEdgeType.derivedFrom;
      case 'CONTAINS':
        return GraphEdgeType.contains;
      default:
        return GraphEdgeType.referenced;
    }
  }
}

/// Represents an edge (connection) in the lineage graph
class GraphEdge {
  final String sourceId;
  final String targetId;
  final GraphEdgeType type;
  final Map<String, String> metadata;

  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.metadata = const {},
  });
}

/// Represents the complete lineage graph data
class LineageGraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final GraphNode? rootNode;   // Used for layout (typically project)
  final GraphNode? focusNode;  // Used for auto-selection (the revision being viewed)

  const LineageGraphData({
    this.nodes = const [],
    this.edges = const [],
    this.rootNode,
    this.focusNode,
  });

  LineageGraphData copyWith({
    List<GraphNode>? nodes,
    List<GraphEdge>? edges,
    GraphNode? rootNode,
    GraphNode? focusNode,
  }) {
    return LineageGraphData(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      rootNode: rootNode ?? this.rootNode,
      focusNode: focusNode ?? this.focusNode,
    );
  }
}
