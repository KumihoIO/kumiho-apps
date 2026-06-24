import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import '../models/graph_node.dart';
import '../theme/kumiho_theme.dart';

/// Interactive lineage graph widget for visualizing asset dependencies
/// Styled after Unreal Engine Blueprint nodes (dark) and Unity Bolt (light)
class LineageGraphWidget extends StatefulWidget {
  final LineageGraphData graphData;
  final Function(GraphNode)? onNodeSelected;
  final Function(LineageGraphData)? onGraphUpdated;

  const LineageGraphWidget({
    super.key,
    required this.graphData,
    this.onNodeSelected,
    this.onGraphUpdated,
  });

  @override
  State<LineageGraphWidget> createState() => _LineageGraphWidgetState();
}

class _LineageGraphWidgetState extends State<LineageGraphWidget> {
  late LineageGraphData _graphData;
  String? _selectedNodeId;
  String? _draggingNodeId;
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;
  Offset? _lastFocalPoint;

  // Blueprint-style node sizing (compact)
  static const double nodeWidth = 160.0;
  static const double nodeHeight = 52.0;
  static const double nodeRadius = 4.0;
  static const double titleBarHeight = 18.0;
  static const double pinSize = 8.0;
  
  // Theme-aware colors (computed in build based on context)
  bool _isDarkMode = true;
  
  // Dark theme colors (Unreal Blueprint style)
  static const Color _darkBackground = Color(0xFF1A1A1A);
  static const Color _darkNodeBackground = Color(0xFF242424);
  static const Color _darkGridColor = Color(0xFF2A2A2A);
  static const Color _darkBorderColor = Color(0xFF3A3A3A);
  static const Color _darkOverlayColor = Color(0xFF242424);
  
  // Light theme colors (Unity Bolt style - matching the provided image)
  static const Color _lightBackground = Color(0xFFCCCCD4);  // Light gray canvas
  static const Color _lightNodeBackground = Color(0xFFFFFFFF);  // White nodes
  static const Color _lightGridColor = Color(0xFFB8B8C0);  // Subtle grid
  static const Color _lightBorderColor = Color(0xFFA0A0A8);  // Node borders
  static const Color _lightOverlayColor = Color(0xFFE8E8F0);  // Overlays

  @override
  void initState() {
    super.initState();
    _graphData = widget.graphData;
    _autoLayoutNodes();
  }

  @override
  void didUpdateWidget(LineageGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.graphData != oldWidget.graphData) {
      _graphData = widget.graphData;
      _autoLayoutNodes();
    }
  }

  /// Auto-layout nodes in a hierarchical structure
  void _autoLayoutNodes() {
    if (_graphData.nodes.isEmpty) return;

    // Find root node or use first node
    final rootId = _graphData.rootNode?.id ?? _graphData.nodes.first.id;
    
    // Build adjacency map
    final Map<String, List<String>> children = {};
    final Map<String, String?> parents = {};
    
    for (final node in _graphData.nodes) {
      children[node.id] = [];
      parents[node.id] = null;
    }
    
    for (final edge in _graphData.edges) {
      if (edge.type == GraphEdgeType.belongsTo || edge.type == GraphEdgeType.contains) {
        children[edge.sourceId]?.add(edge.targetId);
        parents[edge.targetId] = edge.sourceId;
      } else {
        children[edge.sourceId]?.add(edge.targetId);
      }
    }

    // Calculate levels using BFS
    final Map<String, int> levels = {};
    final List<String> queue = [rootId];
    levels[rootId] = 0;
    
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentLevel = levels[current] ?? 0;
      
      for (final childId in children[current] ?? []) {
        if (!levels.containsKey(childId)) {
          levels[childId] = currentLevel + 1;
          queue.add(childId);
        }
      }
    }

    // Assign remaining nodes
    for (final node in _graphData.nodes) {
      if (!levels.containsKey(node.id)) {
        levels[node.id] = 0;
      }
    }

    // Group nodes by level
    final Map<int, List<String>> levelNodes = {};
    for (final entry in levels.entries) {
      levelNodes.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // Position nodes
    const horizontalSpacing = 200.0;
    const verticalSpacing = 120.0;
    
    final updatedNodes = <GraphNode>[];
    
    for (final node in _graphData.nodes) {
      final level = levels[node.id] ?? 0;
      final nodesAtLevel = levelNodes[level] ?? [node.id];
      final indexAtLevel = nodesAtLevel.indexOf(node.id);
      final totalAtLevel = nodesAtLevel.length;
      
      // Only update position if node hasn't been positioned
      if (node.position == Offset.zero) {
        final x = level * horizontalSpacing + 100;
        final y = (indexAtLevel - (totalAtLevel - 1) / 2) * verticalSpacing + 300;
        updatedNodes.add(node.copyWith(position: Offset(x, y)));
      } else {
        updatedNodes.add(node);
      }
    }

    _graphData = _graphData.copyWith(nodes: updatedNodes);
  }

  void _handleNodeTap(GraphNode node) {
    setState(() {
      _selectedNodeId = node.id;
    });
    widget.onNodeSelected?.call(node);
  }

  void _handleNodeDragStart(GraphNode node) {
    setState(() {
      _draggingNodeId = node.id;
    });
  }

  void _handleNodeDragUpdate(GraphNode node, Offset delta) {
    if (_draggingNodeId != node.id) return;
    
    setState(() {
      final updatedNodes = _graphData.nodes.map((n) {
        if (n.id == node.id) {
          return n.copyWith(position: n.position + delta / _scale);
        }
        return n;
      }).toList();
      
      _graphData = _graphData.copyWith(nodes: updatedNodes);
    });
  }

  void _handleNodeDragEnd() {
    if (_draggingNodeId != null) {
      widget.onGraphUpdated?.call(_graphData);
    }
    setState(() {
      _draggingNodeId = null;
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_draggingNodeId != null) return;
    
    setState(() {
      // Handle zoom when pinching (scale != 1.0)
      if (details.scale != 1.0) {
        final newScale = (_scale * details.scale).clamp(0.3, 3.0);
        // Zoom towards focal point
        final focalPoint = details.localFocalPoint;
        final oldScale = _scale;
        _scale = newScale;
        
        // Adjust pan to zoom towards focal point
        _panOffset = focalPoint - (focalPoint - _panOffset) * (_scale / oldScale);
      }
      
      // Handle pan (single finger drag or two finger pan)
      if (_lastFocalPoint != null) {
        _panOffset += details.localFocalPoint - _lastFocalPoint!;
      }
      _lastFocalPoint = details.localFocalPoint;
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        final scaleDelta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
        final newScale = (_scale * scaleDelta).clamp(0.3, 3.0);
        
        // Zoom towards cursor position
        final cursorPosition = event.localPosition;
        final oldScale = _scale;
        _scale = newScale;
        
        _panOffset = cursorPosition - (cursorPosition - _panOffset) * (_scale / oldScale);
      });
    }
  }

  void _resetView() {
    setState(() {
      _panOffset = Offset.zero;
      _scale = 1.0;
    });
  }

  void _fitToView() {
    if (_graphData.nodes.isEmpty) return;
    
    // Calculate bounds
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    
    for (final node in _graphData.nodes) {
      minX = math.min(minX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxX = math.max(maxX, node.position.dx + nodeWidth);
      maxY = math.max(maxY, node.position.dy + nodeHeight);
    }
    
    // Get available size (approximate)
    final size = context.size ?? const Size(800, 600);
    const padding = 100.0;
    
    final graphWidth = maxX - minX + padding * 2;
    final graphHeight = maxY - minY + padding * 2;
    
    final scaleX = size.width / graphWidth;
    final scaleY = size.height / graphHeight;
    
    setState(() {
      _scale = math.min(scaleX, scaleY).clamp(0.3, 2.0);
      _panOffset = Offset(
        size.width / 2 - (minX + (maxX - minX) / 2) * _scale,
        size.height / 2 - (minY + (maxY - minY) / 2) * _scale,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Detect theme mode
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = _isDarkMode ? _darkBackground : _lightBackground;
    final gridColor = _isDarkMode ? _darkGridColor : _lightGridColor;
    
    return Stack(
      children: [
        // Graph canvas
        Listener(
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            onScaleStart: (_) => _lastFocalPoint = null,
            onScaleUpdate: _handleScaleUpdate,
            onScaleEnd: _handleScaleEnd,
            child: Container(
              color: backgroundColor,
              child: CustomPaint(
                painter: _GraphPainter(
                  graphData: _graphData,
                  selectedNodeId: _selectedNodeId,
                  panOffset: _panOffset,
                  scale: _scale,
                  nodeWidth: nodeWidth,
                  nodeHeight: nodeHeight,
                  isDarkMode: _isDarkMode,
                  gridColor: gridColor,
                ),
                child: Stack(
                  children: _graphData.nodes.map((node) {
                    return _buildNodeWidget(node);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        
        // Controls
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _buildControlButton(Icons.add, () {
                setState(() {
                  _scale = (_scale * 1.2).clamp(0.3, 3.0);
                });
              }),
              const SizedBox(height: 8),
              _buildControlButton(Icons.remove, () {
                setState(() {
                  _scale = (_scale / 1.2).clamp(0.3, 3.0);
                });
              }),
              const SizedBox(height: 8),
              _buildControlButton(Icons.fit_screen, _fitToView),
              const SizedBox(height: 8),
              _buildControlButton(Icons.center_focus_strong, _resetView),
            ],
          ),
        ),
        
        // Legend
        Positioned(
          bottom: 16,
          left: 16,
          child: _buildLegend(),
        ),
        
        // Scale indicator
        Positioned(
          bottom: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isDarkMode ? _darkOverlayColor : _lightOverlayColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _isDarkMode ? _darkBorderColor : _lightBorderColor),
            ),
            child: Text(
              '${(_scale * 100).toInt()}%',
              style: TextStyle(
                color: _isDarkMode ? Colors.white70 : const Color(0xFF3A3A44),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNodeWidget(GraphNode node) {
    final position = node.position * _scale + _panOffset;
    final isSelected = _selectedNodeId == node.id;
    final nodeColor = _getNodeColor(node.type);
    
    // Theme-aware colors
    final nodeBackground = _isDarkMode ? _darkNodeBackground : _lightNodeBackground;
    final borderColor = _isDarkMode ? _darkBorderColor : _lightBorderColor;
    final textColor = _isDarkMode ? Colors.white.withAlpha(230) : const Color(0xFF1A1A1E);
    final shadowColor = _isDarkMode ? Colors.black.withAlpha(102) : Colors.black.withAlpha(38);

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: () => _handleNodeTap(node),
        onPanStart: (_) => _handleNodeDragStart(node),
        onPanUpdate: (details) => _handleNodeDragUpdate(node, details.delta),
        onPanEnd: (_) => _handleNodeDragEnd(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: nodeWidth * _scale,
          height: nodeHeight * _scale,
          decoration: BoxDecoration(
            color: nodeBackground,
            borderRadius: BorderRadius.circular(nodeRadius * _scale),
            border: Border.all(
              color: isSelected ? KumihoTheme.primary : borderColor,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              if (isSelected)
                BoxShadow(
                  color: KumihoTheme.primary.withAlpha(102),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(nodeRadius * _scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title bar (Blueprint style colored header)
                Container(
                  height: titleBarHeight * _scale,
                  padding: EdgeInsets.symmetric(horizontal: 8 * _scale),
                  decoration: BoxDecoration(
                    color: nodeColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular((nodeRadius - 1) * _scale),
                      topRight: Radius.circular((nodeRadius - 1) * _scale),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getNodeIcon(node.type),
                        size: 12 * _scale,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4 * _scale),
                      Expanded(
                        child: Text(
                          node.type.name.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9 * _scale,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Content area
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 * _scale,
                      vertical: 4 * _scale,
                    ),
                    child: Row(
                      children: [
                        // Left pin (incoming connections)
                        _buildPin(isInput: true, color: nodeColor),
                        SizedBox(width: 4 * _scale),
                        // Name
                        Expanded(
                          child: Text(
                            node.name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 10 * _scale,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 4 * _scale),
                        // Right pin (outgoing connections)
                        _buildPin(isInput: false, color: nodeColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPin({required bool isInput, required Color color}) {
    return Container(
      width: pinSize * _scale,
      height: pinSize * _scale,
      decoration: BoxDecoration(
        color: color.withAlpha(77),
        shape: BoxShape.circle,
        border: Border.all(
          color: color,
          width: 1.5 * _scale,
        ),
      ),
      child: Center(
        child: Container(
          width: 4 * _scale,
          height: 4 * _scale,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: _isDarkMode ? _darkOverlayColor : _lightOverlayColor,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _isDarkMode ? _darkBorderColor : _lightBorderColor),
          ),
          child: Icon(icon, color: _isDarkMode ? Colors.white70 : const Color(0xFF4A4A56), size: 20),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final bgColor = _isDarkMode ? _darkOverlayColor : _lightOverlayColor;
    final borderColor = _isDarkMode ? _darkBorderColor : _lightBorderColor;
    final titleColor = _isDarkMode ? Colors.white : const Color(0xFF1A1A1E);
    final textColor = _isDarkMode ? Colors.white70 : const Color(0xFF4A4A56);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Node Types',
            style: TextStyle(
              color: titleColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...GraphNodeType.values.map((type) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getNodeColor(type),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  type.name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Color _getNodeColor(GraphNodeType type) {
    return type.color;
  }

  IconData _getNodeIcon(GraphNodeType type) {
    switch (type) {
      case GraphNodeType.project:
        return Icons.folder_special;
      case GraphNodeType.space:
        return Icons.folder;
      case GraphNodeType.subSpace:
        return Icons.folder_open;
      case GraphNodeType.item:
        return Icons.inventory_2;
      case GraphNodeType.revision:
        return Icons.history;
      case GraphNodeType.artifact:
        return Icons.attach_file;
      case GraphNodeType.model:
        return Icons.smart_toy;
      case GraphNodeType.lora:
        return Icons.auto_fix_high;
      case GraphNodeType.image:
        return Icons.image;
      case GraphNodeType.workflow:
        return Icons.schema;
    }
  }
}

/// Custom painter for drawing Blueprint-style edges between nodes
class _GraphPainter extends CustomPainter {
  final LineageGraphData graphData;
  final String? selectedNodeId;
  final Offset panOffset;
  final double scale;
  final double nodeWidth;
  final double nodeHeight;
  final bool isDarkMode;
  final Color gridColor;

  // Pin positioning constants (matching the widget)
  static const double titleBarHeight = 18.0;
  static const double pinOffset = 8.0;

  _GraphPainter({
    required this.graphData,
    required this.selectedNodeId,
    required this.panOffset,
    required this.scale,
    required this.nodeWidth,
    required this.nodeHeight,
    this.isDarkMode = true,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    _drawGrid(canvas, size);
    
    // Draw edges
    for (final edge in graphData.edges) {
      final sourceNode = graphData.nodes.firstWhere(
        (n) => n.id == edge.sourceId,
        orElse: () => graphData.nodes.first,
      );
      final targetNode = graphData.nodes.firstWhere(
        (n) => n.id == edge.targetId,
        orElse: () => graphData.nodes.first,
      );

      if (sourceNode.id == targetNode.id) continue;

      _drawEdge(canvas, sourceNode, targetNode, edge);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final gridSize = 40.0 * scale;
    final offsetX = panOffset.dx % gridSize;
    final offsetY = panOffset.dy % gridSize;

    for (double x = offsetX; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = offsetY; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawEdge(Canvas canvas, GraphNode source, GraphNode target, GraphEdge edge) {
    // Calculate pin Y position (in the content area below the title bar)
    final pinY = titleBarHeight + (nodeHeight - titleBarHeight) / 2;
    
    // Determine pin positions based on edge type:
    // - BELONGS_TO: source right -> target left (hierarchical flow)
    // - DEPENDS_ON: source left <- target right (dependency flows INTO the source)
    // - DERIVED_FROM: source left <- target right (derivation flows INTO the source)
    // - REFERENCED: source left <- target right (reference flows INTO the source)
    // - CREATED_FROM: source left <- target right (creation flows INTO)
    // - CONTAINS: source right -> target left (containment flows OUT)
    
    final bool isIncomingRelationship = edge.type == GraphEdgeType.dependsOn || 
                                         edge.type == GraphEdgeType.derivedFrom ||
                                         edge.type == GraphEdgeType.createdFrom ||
                                         edge.type == GraphEdgeType.referenced;
    
    Offset sourcePin;
    Offset targetPin;
    
    if (isIncomingRelationship) {
      // For dependency-type edges: draw from target (the dependency) to source (the dependent)
      // Target's right pin -> Source's left pin
      // This visually shows "source depends on target" with arrow pointing to source
      sourcePin = Offset(
        target.position.dx * scale + panOffset.dx + nodeWidth * scale - pinOffset * scale,
        target.position.dy * scale + panOffset.dy + pinY * scale,
      );
      targetPin = Offset(
        source.position.dx * scale + panOffset.dx + pinOffset * scale,
        source.position.dy * scale + panOffset.dy + pinY * scale,
      );
    } else {
      // For hierarchical/reference edges: draw from source to target
      // Source's right pin -> Target's left pin
      sourcePin = Offset(
        source.position.dx * scale + panOffset.dx + nodeWidth * scale - pinOffset * scale,
        source.position.dy * scale + panOffset.dy + pinY * scale,
      );
      targetPin = Offset(
        target.position.dx * scale + panOffset.dx + pinOffset * scale,
        target.position.dy * scale + panOffset.dy + pinY * scale,
      );
    }

    final color = edge.type.color;
    final isHighlighted = selectedNodeId == source.id || selectedNodeId == target.id;

    final paint = Paint()
      ..color = isHighlighted ? color : color.withAlpha(153)
      ..strokeWidth = isHighlighted ? 2.5 : 2.0
      ..style = PaintingStyle.stroke;

    // Draw Blueprint-style bezier curve (horizontal spline)
    final dx = (targetPin.dx - sourcePin.dx).abs() * 0.5;
    
    final path = Path()
      ..moveTo(sourcePin.dx, sourcePin.dy)
      ..cubicTo(
        sourcePin.dx + dx, sourcePin.dy,  // First control point (horizontal from source)
        targetPin.dx - dx, targetPin.dy,  // Second control point (horizontal to target)
        targetPin.dx, targetPin.dy,        // End point
      );

    canvas.drawPath(path, paint);

    // Draw small circle at target pin (connection indicator)
    final dotPaint = Paint()
      ..color = isHighlighted ? color : color.withAlpha(153)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetPin, 4 * scale, dotPaint);

    // Draw edge label on hover/selection
    if (isHighlighted) {
      final midX = (sourcePin.dx + targetPin.dx) / 2;
      final midY = (sourcePin.dy + targetPin.dy) / 2;
      _drawEdgeLabel(canvas, midX, midY - 12, edge.type.label);
    }
  }

  void _drawEdgeLabel(Canvas canvas, double x, double y, String label) {
    final bgColor = isDarkMode ? const Color(0xFF242424) : const Color(0xFFFFFFFF);
    final borderColor = isDarkMode ? const Color(0xFF3A3A3A) : const Color(0xFFA0A0A8);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1A1A1E);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Draw background pill
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, y),
        width: textPainter.width + 12,
        height: textPainter.height + 6,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(bgRect, Paint()..color = bgColor);
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Draw text
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) {
    return oldDelegate.graphData != graphData ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale;
  }
}
