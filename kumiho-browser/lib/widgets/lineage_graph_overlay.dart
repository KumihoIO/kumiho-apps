import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/graph_node.dart';
import '../theme/kumiho_theme.dart';
import 'lineage_graph.dart';

/// Overlay widget for displaying the lineage graph as a modal
class LineageGraphOverlay extends ConsumerStatefulWidget {
  final LineageGraphData graphData;
  final String title;
  final VoidCallback onClose;
  final Function(GraphNode)? onNodeSelected;

  const LineageGraphOverlay({
    super.key,
    required this.graphData,
    required this.title,
    required this.onClose,
    this.onNodeSelected,
  });

  /// Show the lineage graph overlay
  static Future<void> show({
    required BuildContext context,
    required LineageGraphData graphData,
    String title = 'Lineage Graph',
    Function(GraphNode)? onNodeSelected,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => LineageGraphOverlay(
        graphData: graphData,
        title: title,
        onClose: () => Navigator.of(context).pop(),
        onNodeSelected: onNodeSelected,
      ),
    );
  }

  @override
  ConsumerState<LineageGraphOverlay> createState() => _LineageGraphOverlayState();
}

class _LineageGraphOverlayState extends ConsumerState<LineageGraphOverlay> {
  GraphNode? _selectedNode;
  bool _showPropertyPanel = true;

  @override
  void initState() {
    super.initState();
    // Handle escape key to close
    ServicesBinding.instance.keyboard.addHandler(_handleKeyPress);
    
    // Auto-select focus node (revision) to show details panel on load
    _selectedNode = widget.graphData.focusNode;
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyPress);
    super.dispose();
  }

  bool _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return true;
    }
    return false;
  }

  void _handleNodeSelected(GraphNode node) {
    setState(() {
      _selectedNode = node;
    });
    widget.onNodeSelected?.call(node);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final colors = KumihoTheme.of(context);
    final isDarkMode = KumihoTheme.isDarkMode(context);
    
    // Calculate 75% of screen size for the dialog
    final dialogWidth = screenSize.width * 0.75;
    final dialogHeight = screenSize.height * 0.75;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      // Use 12.5% padding on each side to achieve 75% coverage
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.125,  // 12.5% padding = 75% width
        vertical: screenSize.height * 0.125,   // 12.5% padding = 75% height
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          color: colors.background,
          child: Column(
            children: [
              // Header
              _buildHeader(context),
              
              // Content
              Expanded(
                child: Row(
                  children: [
                    // Graph
                    Expanded(
                      child: LineageGraphWidget(
                        graphData: widget.graphData,
                        onNodeSelected: _handleNodeSelected,
                      ),
                    ),
                    
                    // Property panel
                    if (_showPropertyPanel && _selectedNode != null)
                      _buildPropertyPanel(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_tree,
            color: colors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            widget.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          
          // Toggle property panel
          IconButton(
            icon: Icon(
              _showPropertyPanel ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              color: colors.textSecondary,
              size: 20,
            ),
            tooltip: _showPropertyPanel ? 'Hide Properties' : 'Show Properties',
            onPressed: () {
              setState(() {
                _showPropertyPanel = !_showPropertyPanel;
              });
            },
          ),
          
          // Close button
          IconButton(
            icon: Icon(
              Icons.close,
              color: colors.textSecondary,
              size: 20,
            ),
            tooltip: 'Close (Esc)',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyPanel(BuildContext context) {
    final node = _selectedNode!;
    final colors = KumihoTheme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    // Panel width is 25% of dialog width (which is 75% of screen)
    final panelWidth = (screenSize.width * 0.75 * 0.28).clamp(280.0, 400.0);
    
    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: colors.backgroundSidebar,
        border: Border(
          left: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildNodeTypeChip(node.type, context),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: colors.textMuted,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _selectedNode = null;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  node.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (node.kref != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    node.kref!,
                    style: TextStyle(
                      color: colors.textDimmed,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Connections
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Connections', context),
                  const SizedBox(height: 8),
                  _buildConnectionsList(node, context),
                  
                  const SizedBox(height: 24),
                  _buildSectionTitle('Metadata', context),
                  const SizedBox(height: 8),
                  _buildMetadataList(node, context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTypeChip(GraphNodeType type, BuildContext context) {
    final nodeColor = _getNodeColor(type);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: nodeColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getNodeIcon(type),
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            type.name.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Text(
      title,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildConnectionsList(GraphNode node, BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    // Find edges connected to this node
    final incomingEdges = widget.graphData.edges
        .where((e) => e.targetId == node.id)
        .toList();
    final outgoingEdges = widget.graphData.edges
        .where((e) => e.sourceId == node.id)
        .toList();

    if (incomingEdges.isEmpty && outgoingEdges.isEmpty) {
      return Text(
        'No connections',
        style: TextStyle(color: colors.textDimmed, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (incomingEdges.isNotEmpty) ...[
          Text(
            'Incoming',
            style: TextStyle(color: colors.textDimmed, fontSize: 10),
          ),
          const SizedBox(height: 4),
          ...incomingEdges.map((edge) => _buildEdgeRow(edge, isIncoming: true, context: context)),
          const SizedBox(height: 12),
        ],
        if (outgoingEdges.isNotEmpty) ...[
          Text(
            'Outgoing',
            style: TextStyle(color: colors.textDimmed, fontSize: 10),
          ),
          const SizedBox(height: 4),
          ...outgoingEdges.map((edge) => _buildEdgeRow(edge, isIncoming: false, context: context)),
        ],
      ],
    );
  }

  Widget _buildEdgeRow(GraphEdge edge, {required bool isIncoming, required BuildContext context}) {
    final colors = KumihoTheme.of(context);
    final otherNodeId = isIncoming ? edge.sourceId : edge.targetId;
    final otherNode = widget.graphData.nodes.firstWhere(
      (n) => n.id == otherNodeId,
      orElse: () => GraphNode(
        id: otherNodeId,
        name: 'Unknown',
        type: GraphNodeType.item,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _handleNodeSelected(otherNode),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.backgroundCard,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                isIncoming ? Icons.arrow_back : Icons.arrow_forward,
                size: 12,
                color: edge.type.color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherNode.name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      edge.type.label,
                      style: TextStyle(
                        color: edge.type.color,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _getNodeIcon(otherNode.type),
                size: 14,
                color: _getNodeColor(otherNode.type),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataList(GraphNode node, BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    if (node.metadata.isEmpty) {
      return Text(
        'No metadata',
        style: TextStyle(color: colors.textDimmed, fontSize: 12),
      );
    }

    return Column(
      children: node.metadata.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  entry.value.toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
