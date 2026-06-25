// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kumiho/kumiho.dart';
import '../models/models.dart';
import '../models/graph_node.dart';
import '../providers/auth_provider.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../services/asset_actions.dart';
import '../theme/kumiho_theme.dart';
import 'artifact_viewer.dart';
import 'lineage_graph_overlay.dart';
import 'share_dialog.dart';
import 'video_thumbnail.dart';
import 'windows_playlist_thumbnail.dart';

/// Resizable detail panel (right column)
class DetailPanel extends ConsumerWidget {
  const DetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);

    return Row(
      children: [
        // Resize handle
        _ResizeHandle(
          onDrag: (delta) => notifier.setDetailPanelWidth(state.detailPanelWidth - delta),
        ),
        // Detail panel content
        Container(
          width: state.detailPanelWidth,
          color: colors.backgroundSidebar,
          child: state.selectedItem == null
              ? const _EmptyState()
              : _DetailContent(item: state.selectedItem!, panelWidth: state.detailPanelWidth),
        ),
      ],
    );
  }
}

// ==================== RESIZE HANDLE ==================== //

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;

  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          decoration: BoxDecoration(
            color: colors.borderDark,
            border: Border(
              left: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: colors.textVeryDimmed,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== EMPTY STATE ==================== //

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 48, color: colors.textVeryDimmed.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Select an item to view details',
            style: TextStyle(color: colors.textDimmed.withValues(alpha: 0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ==================== DETAIL CONTENT ==================== //

class _DetailContent extends ConsumerStatefulWidget {
  final MediaItem item;
  final double panelWidth;

  const _DetailContent({
    required this.item,
    required this.panelWidth,
  });

  @override
  ConsumerState<_DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<_DetailContent> {
  bool _promptExpanded = false;
  MediaItem get item => widget.item;
  double get panelWidth => widget.panelWidth;

  @override
  Widget build(BuildContext context) {
    final playlistItems = ref.watch(browserProvider).playlistItems;
    final isInPlaylist = playlistItems.any((e) => e.id == widget.item.id);
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final canBrowse = ref.watch(canBrowseProvider);
    final colors = KumihoTheme.of(context);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Preview (top aligned)
        _buildPreview(context, ref, isInPlaylist, isAuthenticated),
        const SizedBox(height: 16),
        // File info
        _buildFileInfo(colors),
        const SizedBox(height: 16),
        const _Divider(),
        // Prompt section
        _buildPromptSection(colors),
        const SizedBox(height: 16),
        const _Divider(),
        // Model section
        _buildModelSection(colors),
        const SizedBox(height: 16),
        const _Divider(),
        // Settings section
        _buildSettingsSection(colors),
        const SizedBox(height: 16),
        const _Divider(),
        // Lineage section — available whenever browsing is possible
        // (authenticated cloud, self-hosted/CE, or anonymous tenant).
        if (canBrowse)
          _buildLineageSection(context, ref, colors),
      ],
    );
  }

  Future<void> _addThumbnail(
      BuildContext context, WidgetRef ref, String revisionKref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await AssetActions.addThumbnail(ref, revisionKref);
      if (path != null) {
        messenger?.showSnackBar(
            const SnackBar(content: Text('Thumbnail added')));
      }
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text('Failed to add thumbnail: $e')));
    }
  }

  /// Show the lineage graph overlay with real Kumiho data
  Future<void> _showLineageGraph(BuildContext context, WidgetRef ref) async {
    // Parse the item's kref to get hierarchy info
    final itemKref = item.id;  // This is the artifact kref
    
    Kref? krefObj;
    try {
      krefObj = Kref(itemKref);
    } catch (e) {
      debugPrint('Failed to parse kref: $itemKref - $e');
      _showFallbackGraph(context);
      return;
    }
    
    final projectName = krefObj.project;
    final spacePath = krefObj.space;
    final revisionNumber = krefObj.revision ?? 1;
    final revisionKref = krefObj.revisionKref?.uri ?? itemKref;
    final itemKrefUri = krefObj.itemKref.uri;
    
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // Build lineage graph params
      final params = LineageGraphParams(
        revisionKref: revisionKref,
        itemKref: itemKrefUri,
        itemName: item.name,
        itemKind: item.kind,
        projectName: projectName,
        spacePath: spacePath,
        revisionNumber: revisionNumber,
        tags: item.tags,
      );
      
      // Fetch the lineage graph
      final result = await ref.read(lineageGraphProvider(params).future);

      if (!context.mounted) return;

      // Close loading indicator
      Navigator.of(context).pop();
      
      if (result.isEmpty) {
        _showFallbackGraph(context);
        return;
      }
      
      // Convert to graph data
      final graphData = _convertToGraphData(result);
      
      LineageGraphOverlay.show(
        context: context,
        graphData: graphData,
        title: 'Lineage: ${item.name}',
      );
    } catch (e) {
      debugPrint('Failed to fetch lineage graph: $e');

      if (!context.mounted) return;

      Navigator.of(context).pop(); // Close loading
      _showFallbackGraph(context);
    }
  }
  
  /// Convert LineageGraphResult to LineageGraphData for the widget
  LineageGraphData _convertToGraphData(LineageGraphResult result) {
    GraphNode? rootNode;   // Project node for layout
    GraphNode? focusNode;  // Focus node for auto-selection
    
    final nodes = result.nodes.map((node) {
      final type = _mapNodeType(node.type);
      final graphNode = GraphNode(
        id: node.id,
        name: node.name,
        type: type,
        kref: node.kref,
        metadata: node.metadata,
        isSelected: node.isFocus,
      );
      
      // Find project node as layout root
      if (type == GraphNodeType.project && rootNode == null) {
        rootNode = graphNode;
      }
      
      // Find the focus node (the revision being viewed)
      if (node.isFocus) {
        focusNode = graphNode;
      }
      
      return graphNode;
    }).toList();
    
    final edges = result.edges.map((edge) {
      return GraphEdge(
        sourceId: edge.sourceId,
        targetId: edge.targetId,
        type: _mapEdgeType(edge.type),
      );
    }).toList();
    
    return LineageGraphData(
      nodes: nodes,
      edges: edges,
      rootNode: rootNode,
      focusNode: focusNode,
    );
  }
  
  /// Map string type to GraphNodeType
  GraphNodeType _mapNodeType(String type) {
    switch (type.toLowerCase()) {
      case 'project':
        return GraphNodeType.project;
      case 'space':
        return GraphNodeType.space;
      case 'subspace':
        return GraphNodeType.subSpace;
      case 'item':
        return GraphNodeType.item;
      case 'revision':
        return GraphNodeType.revision;
      case 'artifact':
        return GraphNodeType.artifact;
      case 'model':
        return GraphNodeType.model;
      case 'lora':
        return GraphNodeType.lora;
      case 'image':
        return GraphNodeType.image;
      case 'workflow':
        return GraphNodeType.workflow;
      default:
        return GraphNodeType.item;
    }
  }
  
  /// Map edge type string to GraphEdgeType
  GraphEdgeType _mapEdgeType(String type) {
    switch (type.toUpperCase()) {
      case 'BELONGS_TO':
      case 'CONTAINS':
        return GraphEdgeType.belongsTo;
      case 'CREATED_FROM':
        return GraphEdgeType.createdFrom;
      case 'REFERENCED':
        return GraphEdgeType.referenced;
      case 'DEPENDS_ON':
        return GraphEdgeType.dependsOn;
      case 'DERIVED_FROM':
        return GraphEdgeType.derivedFrom;
      default:
        return GraphEdgeType.referenced;
    }
  }
  
  /// Show a fallback graph when real data is unavailable
  void _showFallbackGraph(BuildContext context) {
    final meta = item.metadata;
    final modelName = meta?.model;
    
    final projectNode = GraphNode(
      id: 'project',
      name: 'Project',
      type: GraphNodeType.project,
      kref: 'kref://project',
    );
    
    final graphData = LineageGraphData(
      nodes: [
        projectNode,
        GraphNode(
          id: 'space',
          name: 'Space',
          type: GraphNodeType.space,
        ),
        GraphNode(
          id: 'item-${item.id}',
          name: item.name,
          type: GraphNodeType.item,
          metadata: {
            'name': item.name,
            'type': item.type,
            if (modelName != null) 'model': modelName,
          },
        ),
        if (modelName != null)
          GraphNode(
            id: 'model-lora',
            name: modelName,
            type: GraphNodeType.lora,
          ),
        GraphNode(
          id: 'revision-1',
          name: item.revision,
          type: GraphNodeType.revision,
        ),
      ],
      edges: [
        const GraphEdge(
          sourceId: 'project',
          targetId: 'space',
          type: GraphEdgeType.belongsTo,
        ),
        GraphEdge(
          sourceId: 'space',
          targetId: 'item-${item.id}',
          type: GraphEdgeType.belongsTo,
        ),
        GraphEdge(
          sourceId: 'item-${item.id}',
          targetId: 'revision-1',
          type: GraphEdgeType.belongsTo,
        ),
        if (modelName != null)
          const GraphEdge(
            sourceId: 'revision-1',
            targetId: 'model-lora',
            type: GraphEdgeType.dependsOn,
          ),
      ],
      rootNode: projectNode,
    );

    LineageGraphOverlay.show(
      context: context,
      graphData: graphData,
      title: 'Lineage: ${item.name}',
    );
  }

  /// Show the share dialog for the current item
  void _showShareDialog(BuildContext context, MediaItem item) {
    showShareDialog(context, item);
  }

  Widget _buildPreview(BuildContext context, WidgetRef ref, bool isInPlaylist, bool isAuthenticated) {
    final canBrowse = ref.watch(canBrowseProvider);
    // Offer "Add thumbnail" on a mutable (unpublished) revision that has no
    // 'thumbnail' artifact yet — mirrors the list view's Artifacts section.
    final revisionKref = item.revisionKref;
    bool showAddThumbnail = false;
    if (canBrowse &&
        revisionKref != null &&
        revisionKref.isNotEmpty &&
        !item.isPublished) {
      showAddThumbnail = ref.watch(revisionArtifactsProvider(revisionKref)).maybeWhen(
            data: (artifacts) => !artifacts.any((a) => a.name == 'thumbnail'),
            orElse: () => false,
          );
    }
    // Offer "View / edit" for markdown/text artifacts (the in-app editor).
    final location = item.location;
    final canOpenText = canBrowse &&
        location != null &&
        location.isNotEmpty &&
        ArtifactViewerDialog.isTextual(location);
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final previewLogical = (panelWidth - 32).clamp(0.0, 4096.0);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final previewPx = (previewLogical * dpr).round().clamp(256, 1024);

    return Container(
      width: double.infinity,
      height: panelWidth - 32, // Square preview
      decoration: BoxDecoration(
        color: item.isVideo ? const Color(0xFF2A2A2A) : item.thumbColor,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Show video thumbnail for video items
          if (item.isVideo && item.thumbnailPath != null && !_hasImageThumbnail)
            VideoThumbnail(
              videoPath: item.location ?? item.thumbnailPath!,
              fit: BoxFit.cover,
              placeholder: _buildLoadingPlaceholder(),
              errorWidget: _buildPlaceholder(),
            )
          // Show actual image if available
          else if (item.hasLocalThumbnail && _hasImageThumbnail)
            (isWindows
                ? WindowsPlaylistThumbnail(
                    uri: item.thumbnailPath!,
                    targetPx: previewPx,
                    placeholder: _buildPlaceholder(),
                    loading: _buildLoadingPlaceholder(),
                  )
                : Image.file(
                    io.File(item.thumbnailPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                  ))
          else if (item.hasHttpThumbnail)
            (isWindows
                ? WindowsPlaylistThumbnail(
                    uri: item.thumbnailPath!,
                    targetPx: previewPx,
                    placeholder: _buildPlaceholder(),
                    loading: _buildLoadingPlaceholder(),
                  )
                : Image.network(
                    item.thumbnailPath!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return _buildLoadingPlaceholder();
                    },
                  ))
          else
            _buildPlaceholder(),
          // Video play button overlay
          if (item.isVideo)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          // Action buttons
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                // Favorite/Playlist button
                _FavoriteButton(
                  isInPlaylist: isInPlaylist,
                  onTap: () {
                    final notifier = ref.read(browserProvider.notifier);
                    if (isInPlaylist) {
                      // Remove from playlist
                      final index = ref.read(browserProvider).playlistItems.indexWhere((e) => e.id == item.id);
                      if (index >= 0) {
                        notifier.removeFromPlaylist(index);
                      }
                    } else {
                      // Add to playlist
                      notifier.addToPlaylist(item);
                    }
                  },
                ),
                const SizedBox(width: 4),
                // Share button - only for authenticated (cloud) users.
                if (isAuthenticated) ...[
                  _ActionButton(
                    icon: Icons.share_outlined,
                    tooltip: 'Share',
                    onTap: () => _showShareDialog(context, item),
                  ),
                  const SizedBox(width: 4),
                ],
                // Lineage graph - available whenever browsing is possible
                // (cloud, self-hosted/CE, or anonymous tenant), not just when
                // signed in to Firebase.
                if (canBrowse)
                  _ActionButton(
                    icon: Icons.account_tree_outlined,
                    tooltip: 'Graph',
                    onTap: () => _showLineageGraph(context, ref),
                  ),
                // Add thumbnail - on a mutable revision with no thumbnail yet.
                if (showAddThumbnail) ...[
                  const SizedBox(width: 4),
                  _ActionButton(
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: 'Add thumbnail',
                    onTap: () => _addThumbnail(context, ref, revisionKref!),
                  ),
                ],
                // View / edit a markdown or text artifact.
                if (canOpenText) ...[
                  const SizedBox(width: 4),
                  _ActionButton(
                    icon: Icons.edit_note_outlined,
                    tooltip: 'View / edit',
                    onTap: () => ArtifactViewerDialog.show(
                      context,
                      artifactName: item.artifactName,
                      location: location!,
                      revisionMutable: !item.isPublished,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // File path overlay at bottom
          if (item.thumbnailPath != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  item.thumbnailPath!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Check if item has a valid image thumbnail (not a video file)
  bool get _hasImageThumbnail {
    if (item.thumbnailPath == null) return false;
    if (item.hasHttpThumbnail) return true;
    if (item.hasLocalThumbnail) {
      final path = item.thumbnailPath!.toLowerCase();
      return path.endsWith('.png') || 
             path.endsWith('.jpg') || 
             path.endsWith('.jpeg') || 
             path.endsWith('.webp') ||
             path.endsWith('.gif');
    }
    return false;
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: KumihoTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        item.type == 'mp4' ? Icons.play_circle_filled : Icons.image,
        color: Colors.white.withValues(alpha: 0.3),
        size: 64,
      ),
    );
  }

  Widget _buildFileInfo(KumihoColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _InfoBadge(text: item.type.toUpperCase()),
            _InfoBadge(text: item.revision),
            _InfoBadge(text: item.metadata?.resolution ?? '1024x1024'),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptSection(KumihoColors colors) {
    final fullPrompt = widget.item.metadata?.prompt ?? 'No prompt available';
    const truncateAt = 320;
    final isLong = fullPrompt.length > truncateAt;
    final displayPrompt = (!_promptExpanded && isLong)
        ? '${fullPrompt.substring(0, truncateAt)}…'
        : fullPrompt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionHeader(title: 'Prompt'),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.copy, size: 16, color: colors.textDimmed),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Copy prompt',
              onPressed: () => Clipboard.setData(ClipboardData(text: fullPrompt)),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: SelectableText(
            displayPrompt,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        if (isLong)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _promptExpanded = !_promptExpanded),
            child: Text(
              _promptExpanded ? 'Show less' : 'Read more',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ),
        if (widget.item.metadata?.negativePrompt != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            'Negative: ${widget.item.metadata!.negativePrompt}',
            style: TextStyle(
              color: Colors.red.shade300,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModelSection(KumihoColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Model & LoRAs'),
        _DetailRow(label: 'Model', value: item.metadata?.model ?? 'Unknown'),
        if (item.metadata?.loras != null && item.metadata!.loras!.isNotEmpty)
          _DetailRow(label: 'LoRAs', value: item.metadata!.loras!.join(', ')),
      ],
    );
  }

  Widget _buildSettingsSection(KumihoColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Generation Settings'),
        Row(
          children: [
            Expanded(child: _SettingTile(label: 'Seed', value: '${item.metadata?.seed ?? 0}')),
            const SizedBox(width: 8),
            Expanded(child: _SettingTile(label: 'Steps', value: '${item.metadata?.steps ?? 0}')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _SettingTile(label: 'CFG', value: '${item.metadata?.cfg ?? 0}')),
            const SizedBox(width: 8),
            Expanded(child: _SettingTile(label: 'Sampler', value: item.metadata?.sampler ?? 'Unknown')),
          ],
        ),
      ],
    );
  }

  Widget _buildLineageSection(BuildContext context, WidgetRef ref, KumihoColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Lineage'),
        InkWell(
          onTap: () => _showLineageGraph(context, ref),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KumihoTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KumihoTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree, color: KumihoTheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Lineage Graph',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'See all dependencies and outputs',
                        style: TextStyle(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textDimmed, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== HELPER WIDGETS ==================== //

class _FavoriteButton extends StatefulWidget {
  final bool isInPlaylist;
  final VoidCallback onTap;

  const _FavoriteButton({
    required this.isInPlaylist,
    required this.onTap,
  });

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) => _controller.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isInPlaylist ? 'Remove from Playlist' : 'Add to Playlist',
      child: GestureDetector(
        onTap: _handleTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.isInPlaylist ? KumihoTheme.error.withValues(alpha: 0.9) : Colors.black54,
              borderRadius: BorderRadius.circular(6),
              boxShadow: widget.isInPlaylist
                  ? [BoxShadow(color: KumihoTheme.error.withValues(alpha: 0.4), blurRadius: 8)]
                  : null,
            ),
            child: Icon(
              widget.isInPlaylist ? Icons.favorite : Icons.favorite_border,
              color: widget.isInPlaylist ? Colors.white : KumihoTheme.textSecondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: KumihoTheme.textSecondary, size: 16),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;

  const _InfoBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      height: 1,
      color: colors.backgroundCard,
      margin: const EdgeInsets.symmetric(vertical: 8),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textDimmed,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(color: colors.textDimmed, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String label;
  final String value;

  const _SettingTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.backgroundList,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: colors.textDimmed, fontSize: 9)),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 14, color: colors.textDimmed),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(ClipboardData(text: value)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
