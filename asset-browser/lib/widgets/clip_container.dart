// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../core/perf/perf_logger.dart';
import '../theme/kumiho_theme.dart';
import 'video_thumbnail.dart';
import 'windows_playlist_thumbnail.dart';

/// Reusable clip container widget for both grid/list views and playlist
class ClipContainer extends StatelessWidget {
  final MediaItem item;
  final bool isSelected;
  final VoidCallback? onTap;
  final double? size;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final bool deferThumbnailsDuringStartup;
  final bool forcePlaceholderThumbnail;

  /// Minimum size for clip containers to prevent RenderFlex overflow
  static const double minSize = 60.0;

  const ClipContainer({
    super.key,
    required this.item,
    this.isSelected = false,
    this.onTap,
    this.size,
    this.showCloseButton = false,
    this.onClose,
    this.deferThumbnailsDuringStartup = false,
    this.forcePlaceholderThumbnail = false,
  });

  static int _startupDeferPlaylistThumbsMs() {
    const env = int.fromEnvironment('STARTUP_DEFER_PLAYLIST_THUMBNAILS_MS', defaultValue: -1);
    if (env >= 0) return env;
    // Default to no hard deferral; use per-item staggering instead.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return 0;
    return 0;
  }

  bool _shouldDeferThumbnailNow() {
    if (!deferThumbnailsDuringStartup) return false;
    final ms = _startupDeferPlaylistThumbsMs();
    if (ms <= 0) return false;
    return PerfLogger.sinceStartMs() < ms;
  }

  int? _thumbnailCacheSizePx(BuildContext context, double? sizeLogicalPx) {
    if (sizeLogicalPx == null) return null;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = (sizeLogicalPx * dpr).round();
    if (px <= 0) return null;

    // Playlist thumbnails are small and numerous. On Windows, aggressively cap
    // their decode size to keep UI-thread codec work bounded.
    final int maxPx = (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            showCloseButton)
        ? 384
        : 768;
    // Clamp to keep decode work bounded while still looking sharp.
    final clamped = px.clamp(64, maxPx);
    // Bucket sizes so slight resizes don't cause constant re-decodes.
    const bucket = 256;
    final bucketed = ((clamped / bucket).round() * bucket).clamp(64, maxPx);
    return bucketed;
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    // Ensure size is at least minSize to prevent overflow
    final effectiveSize = size?.clamp(minSize, double.infinity);

    return Opacity(
      opacity: item.deprecated ? 0.25 : 1.0,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: effectiveSize,
        height: effectiveSize,
        constraints: const BoxConstraints(
          minWidth: minSize,
          minHeight: minSize,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundList,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? KumihoTheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Top overlay - Date & Revision
            _buildTopOverlay(colors, effectiveSize),
            // Center - Thumbnail
            _buildThumbnail(context, colors, effectiveSize),
            // Bottom overlay - Name & Type
            _buildBottomOverlay(colors, effectiveSize),
            // Close button (optional)
            if (showCloseButton) _buildCloseButton(colors),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTopOverlay(KumihoColors colors, [double? effectiveSize]) {
    final actualSize = effectiveSize ?? size;
    final isDark = colors.background == KumihoTheme.background;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: actualSize != null && actualSize < 100 ? 6 : 8,
          vertical: actualSize != null && actualSize < 100 ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.black.withValues(alpha: 0.5)
              : colors.backgroundCard.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Date
            Flexible(
              child: Text(
                formatDate(item.date),
                style: TextStyle(
                  color: isDark ? Colors.white70 : colors.textSecondary,
                  fontSize: actualSize != null && actualSize < 100 ? 8 : 9,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // Revision badge - compact
            if (item.revision.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: actualSize != null && actualSize < 100 ? 4 : 5,
                  vertical: actualSize != null && actualSize < 100 ? 1 : 2,
                ),
                decoration: BoxDecoration(
                  color: KumihoTheme.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(actualSize != null && actualSize < 100 ? 2 : 3),
                ),
                child: Text(
                  item.revision,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: actualSize != null && actualSize < 100 ? 7 : 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, KumihoColors colors, [double? effectiveSize]) {
    final actualSize = effectiveSize ?? size;
    final topMargin = actualSize != null && actualSize < 100 ? 22.0 : 28.0;
    final bottomMargin = actualSize != null && actualSize < 100 ? 24.0 : 32.0;
    final horizontalMargin = actualSize != null && actualSize < 100 ? 6.0 : 8.0;
    final iconSize = actualSize != null ? actualSize * 0.25 : 36.0;

    // Use dark background for videos without thumbnails, otherwise use thumbColor
    final backgroundColor = item.isVideo && !_hasThumbnail 
        ? const Color(0xFF2A2A2A)
        : item.thumbColor;

    return Positioned.fill(
      top: topMargin,
      bottom: bottomMargin,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumbnailContent(context, iconSize, colors, actualSize),
              // Video play overlay
              if (item.isVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white.withAlpha(230),
                      size: iconSize.clamp(16.0, 28.0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Check if item has a valid thumbnail
  bool get _hasThumbnail {
    if (item.thumbnailPath == null) return false;
    if (item.hasHttpThumbnail) return true;
    if (item.hasLocalThumbnail) {
      // For local files, check if it's an image file (not the video itself)
      final path = item.thumbnailPath!.toLowerCase();
      return path.endsWith('.png') || 
             path.endsWith('.jpg') || 
             path.endsWith('.jpeg') || 
             path.endsWith('.webp') ||
             path.endsWith('.gif');
    }
    return false;
  }

  Widget _buildThumbnailContent(BuildContext context, double iconSize, KumihoColors colors, double? actualSize) {
    if (forcePlaceholderThumbnail) {
      return _buildPlaceholderIcon(iconSize);
    }
    if (_shouldDeferThumbnailNow()) {
      return _buildPlaceholderIcon(iconSize);
    }

    final cachePx = _thumbnailCacheSizePx(context, actualSize);
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final isWindowsPlaylist = isWindows && showCloseButton;
    final useWindowsBgThumbs = isWindows;

    // For video items without an image thumbnail, extract from video.
    // In the playlist strip on Windows, avoid triggering extraction.
    if (item.isVideo && item.thumbnailPath != null && !_hasThumbnail) {
      if (isWindowsPlaylist) {
        return _buildPlaceholderIcon(iconSize);
      }
      return VideoThumbnail(
        videoPath: item.location ?? item.thumbnailPath!,
        fit: BoxFit.cover,
        placeholder: _buildLoadingIndicator(colors),
        errorWidget: _buildPlaceholderIcon(iconSize),
      );
    }
    
    // Try to load thumbnail from file path
    if (item.thumbnailPath != null) {
      // HTTP URL
      if (item.hasHttpThumbnail) {
        if (useWindowsBgThumbs) {
          return WindowsPlaylistThumbnail(
            uri: item.thumbnailPath!,
            targetPx: cachePx ?? 256,
            placeholder: _buildPlaceholderIcon(iconSize),
            loading: _buildLoadingIndicator(colors),
          );
        }
        return Image.network(
          item.thumbnailPath!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
          errorBuilder: (_, __, ___) => _buildPlaceholderIcon(iconSize),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
                strokeWidth: 2,
                color: colors.textMuted,
              ),
            );
          },
        );
      }
      
      // Local file (image thumbnail)
      if (item.hasLocalThumbnail && _hasThumbnail) {
        if (useWindowsBgThumbs) {
          return WindowsPlaylistThumbnail(
            uri: item.thumbnailPath!,
            targetPx: cachePx ?? 256,
            placeholder: _buildPlaceholderIcon(iconSize),
            loading: _buildLoadingIndicator(colors),
          );
        }
        final file = File(item.thumbnailPath!);
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
          errorBuilder: (_, __, ___) => _buildPlaceholderIcon(iconSize),
        );
      }
    }
    
    // Fallback to placeholder
    return _buildPlaceholderIcon(iconSize);
  }

  Widget _buildLoadingIndicator(KumihoColors colors) {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderIcon(double iconSize) {
    return Center(
      child: Icon(
        item.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
        color: Colors.white.withValues(alpha: 0.4),
        size: iconSize.clamp(20.0, 36.0),
      ),
    );
  }

  Widget _buildBottomOverlay(KumihoColors colors, [double? effectiveSize]) {
    final actualSize = effectiveSize ?? size;
    final isDark = colors.background == KumihoTheme.background;
    final isVerySmall = actualSize != null && actualSize < 80;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: actualSize != null && actualSize < 100 ? 6 : 8,
          vertical: actualSize != null && actualSize < 100 ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.black.withValues(alpha: 0.6)
              : colors.backgroundCard.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Item name on left
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  color: item.deprecated
                      ? Colors.redAccent
                      : (isDark ? Colors.white : colors.textPrimary),
                  fontSize: actualSize != null && actualSize < 100 ? 8 : 10,
                  fontWeight: FontWeight.w500,
                  decoration: item.deprecated ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Hide badges on very small clips to prevent overflow
            if (!isVerySmall) ...[
              const SizedBox(width: 4),
              // Kind and file type badges on right - wrap in Flexible to prevent overflow
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Item kind badge
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: actualSize != null && actualSize < 100 ? 3 : 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _getKindColor(item.kind).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          item.kind.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: actualSize != null && actualSize < 100 ? 6 : 7,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    // File type badge
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: actualSize != null && actualSize < 100 ? 3 : 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          item.type.toUpperCase(),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: actualSize != null && actualSize < 100 ? 6 : 7,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Get color for item kind
  Color _getKindColor(String kind) {
    switch (kind.toLowerCase()) {
      case 'model':
        return const Color(0xFF5C6BC0); // Indigo
      case 'texture':
        return const Color(0xFF26A69A); // Teal
      case 'workflow':
        return const Color(0xFFFF7043); // Deep Orange
      case 'image':
        return const Color(0xFF66BB6A); // Green
      case 'video':
        return const Color(0xFFAB47BC); // Purple
      case 'animation':
        return const Color(0xFFFFCA28); // Amber
      case 'material':
        return const Color(0xFF42A5F5); // Blue
      default:
        return KumihoTheme.primary;
    }
  }

  Widget _buildCloseButton(KumihoColors colors) {
    return Positioned(
      top: 2,
      right: 2,
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(Icons.close, size: 10, color: colors.textSecondary),
        ),
      ),
    );
  }

  /// Format date to relative string
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}

/// Draggable version of ClipContainer for grid/list views
/// Supports multi-select dragging when multiple items are selected
class DraggableClipContainer extends ConsumerStatefulWidget {
  final MediaItem item;
  final bool isSelected;
  final VoidCallback? onTap;
  final double? size;
  final List<MediaItem>? allItems; // For multi-select support

  const DraggableClipContainer({
    super.key,
    required this.item,
    this.isSelected = false,
    this.onTap,
    this.size,
    this.allItems,
  });

  @override
  ConsumerState<DraggableClipContainer> createState() => _DraggableClipContainerState();
}

class _DraggableClipContainerState extends ConsumerState<DraggableClipContainer> {
  Timer? _autoExpandTimer;
  String? _scheduledForItemId;

  MediaItem get item => widget.item;
  List<MediaItem>? get allItems => widget.allItems;
  bool get isSelected => widget.isSelected;
  VoidCallback? get onTap => widget.onTap;
  double? get size => widget.size;

  @override
  void dispose() {
    _autoExpandTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoExpandIfNeeded() {
    final item = widget.item;

    // Lazy-load revisions/artifacts only when the base item card becomes
    // visible. This avoids expanding every item's full revision history up
    // front (which is very slow for items with many revisions).
    if (item.type != 'item' || item.revision.isNotEmpty || item.kind.toLowerCase() == 'bundle') {
      return;
    }

    // Don't start new expansion while the fullscreen viewer is open.
    // This prevents Space-to-preview from being delayed by expensive gRPC/protobuf work.
    if (ref.read(playbackModeActiveProvider)) {
      return;
    }

    final pending = ref.read(pagedItemsProvider).pendingDetails;
    final maxPending = defaultTargetPlatform == TargetPlatform.windows ? 2 : 12;
    if (pending >= maxPending) {
      return;
    }

    // Avoid rescheduling repeatedly on rebuild.
    if (_scheduledForItemId == item.id && _autoExpandTimer?.isActive == true) {
      return;
    }

    _autoExpandTimer?.cancel();
    _scheduledForItemId = item.id;
    _autoExpandTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (ref.read(playbackModeActiveProvider)) return;

      final stillPending = ref.read(pagedItemsProvider).pendingDetails;
      if (stillPending >= maxPending) return;
      ref.read(pagedItemsProvider.notifier).fetchDetails(item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoadMoreTile = item.metadata?.prompt == '__kumiho_load_more__';

    _scheduleAutoExpandIfNeeded();

    if (isLoadMoreTile) {
      // No drag, no selection, no context menu; just a lightweight placeholder
      // that triggers fetchDetails when it becomes visible.
      return ClipContainer(
        item: item,
        isSelected: false,
        size: size,
      );
    }

    final selectedIds = ref.watch(browserProvider.select((s) => s.selectedItemIds));
    final isMultiSelected = selectedIds.contains(item.id);
    final selectedCount = selectedIds.length;
    
    // Use only Flutter's Draggable for internal drag operations
    // super_drag_and_drop is removed to fix gesture conflicts
    return GestureDetector(
      onTap: () {
        // Check for Ctrl key for multi-select
        if (HardwareKeyboard.instance.isControlPressed) {
          ref.read(browserProvider.notifier).toggleItemSelection(item);
        } else {
          onTap?.call();
        }
      },
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, ref);
      },
      // Internal Draggable for playlist drops within the app
      child: Draggable<List<MediaItem>>(
        data: selectedCount > 1 && isMultiSelected
            ? _getSelectedItems(ref)
            : [item],
        feedback: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          child: _buildDragFeedback(context, selectedCount > 1 && isMultiSelected ? selectedCount : 1),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: ClipContainer(
            item: item,
            isSelected: isSelected || isMultiSelected,
            size: size,
          ),
        ),
        child: ClipContainer(
          item: item,
          isSelected: isSelected || isMultiSelected,
          size: size,
        ),
      ),
    );
  }

  List<MediaItem> _getSelectedItems(WidgetRef ref) {
    final state = ref.read(browserProvider);
    // Use allItems if provided, otherwise fall back to state.mediaItems
    final itemsSource = allItems ?? state.mediaItems;
    return itemsSource.where((i) => state.selectedItemIds.contains(i.id)).toList();
  }

  Widget _buildDragFeedback(BuildContext context, int count) {
    // Use dark background for videos
    final backgroundColor = item.isVideo ? const Color(0xFF2A2A2A) : item.thumbColor;
    
    return Stack(
      children: [
        // Main thumbnail
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KumihoTheme.primary, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumbnailContent(context),
              // Video play overlay
              if (item.isVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Count badge for multi-select
        if (count > 1)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: KumihoTheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
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

  Widget _buildThumbnailContent(BuildContext context) {
    final rawPx = (100 * MediaQuery.of(context).devicePixelRatio).round();
    final clamped = rawPx.clamp(64, 768);
    const bucket = 64;
    final cachePx = ((clamped / bucket).round() * bucket).clamp(64, 768);

    // For video items without an image thumbnail, use VideoThumbnail
    if (item.isVideo && item.thumbnailPath != null && !_hasImageThumbnail) {
      return VideoThumbnail(
        videoPath: item.thumbnailPath!,
        fit: BoxFit.cover,
        placeholder: _buildPlaceholder(),
        errorWidget: _buildPlaceholder(),
      );
    }
    
    // Image thumbnail
    if (item.hasLocalThumbnail && _hasImageThumbnail) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    } else if (item.hasHttpThumbnail) {
      return Image.network(
        item.thumbnailPath!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        item.isVideo ? Icons.videocam : Icons.image,
        color: Colors.white.withValues(alpha: 0.5),
        size: 32,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, WidgetRef ref) {
    final colors = KumihoTheme.of(context);

    final browserState = ref.read(browserProvider);
    final selectedIds = browserState.selectedItemIds;
    final isSelectionContext = selectedIds.contains(item.id) && selectedIds.length > 1;

    final allItems = ref.read(kumihoMediaItemsProvider);
    final targetItems = isSelectionContext
      ? allItems.where((i) => selectedIds.contains(i.id)).toList()
        : <MediaItem>[item];

    final canRestore = targetItems.any((i) => i.deprecated);
    final canDeprecate = targetItems.any((i) => !i.deprecated);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: colors.surfaceLighter,
      items: [
        if (canRestore) ...[
          PopupMenuItem<String>(
            value: 'restore',
            child: Row(
              children: [
                Icon(Icons.restore_from_trash_outlined, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSelectionContext ? 'Restore selection (un-deprecate)' : 'Restore (un-deprecate)',
                    style: TextStyle(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canDeprecate) ...[
          PopupMenuItem<String>(
            value: 'deprecate',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSelectionContext ? 'Move selection to trash (deprecate)' : 'Move to trash (deprecate)',
                    style: TextStyle(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canRestore || canDeprecate) const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'kref',
          child: Row(
            children: [
              Icon(Icons.link, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copy Kref',
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'location',
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copy Location',
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;

      if (value == 'restore') {
        try {
          final client = await ref.read(kumihoClientProvider.future);
          if (client == null) throw Exception('Client unavailable');

          final restoreTargets = targetItems.where((i) => i.deprecated).toList();
          for (final target in restoreTargets) {
            final kref = target.revisionKref ?? target.kref ?? target.id;
            await client.setDeprecated(kref, false);
          }

          if (isSelectionContext) {
            ref.read(browserProvider.notifier).clearSelection();
          }
          ref.read(kumihoRefreshTriggerProvider.notifier).state++;

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  restoreTargets.length == 1
                      ? 'Restored (un-deprecated)'
                      : 'Restored ${restoreTargets.length} items (un-deprecated)',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to restore: $e'),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return;
      }

      if (value == 'deprecate') {
        try {
          final client = await ref.read(kumihoClientProvider.future);
          if (client == null) throw Exception('Client unavailable');

          final deprecateTargets = targetItems.where((i) => !i.deprecated).toList();
          for (final target in deprecateTargets) {
            final kref = target.revisionKref ?? target.kref ?? target.id;
            await client.setDeprecated(kref, true);
          }

          if (isSelectionContext) {
            ref.read(browserProvider.notifier).clearSelection();
          }
          ref.read(kumihoRefreshTriggerProvider.notifier).state++;

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  deprecateTargets.length == 1
                      ? 'Moved to trash (deprecated)'
                      : 'Moved ${deprecateTargets.length} items to trash (deprecated)',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to deprecate: $e'),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return;
      }
      
      String textToCopy;
      String message;
      
      if (value == 'kref') {
        textToCopy = item.kref ?? item.id;
        message = 'Kref copied to clipboard';
      } else {
        textToCopy = item.location ?? item.thumbnailPath ?? '';
        message = 'Location copied to clipboard';
      }
      
      Clipboard.setData(ClipboardData(text: textToCopy));
      
      // Show snackbar confirmation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }
}

/// Reorderable playlist clip with drag handle and close button
/// Uses Flutter `Draggable<int>` for internal reordering
class PlaylistClip extends ConsumerStatefulWidget {
  final MediaItem item;
  final int index;
  final double size;
  final bool isSelected;
  final bool allowThumbnails;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const PlaylistClip({
    super.key,
    required this.item,
    required this.index,
    required this.size,
    this.isSelected = false,
    this.allowThumbnails = true,
    this.onTap,
    this.onRemove,
  });

  @override
  ConsumerState<PlaylistClip> createState() => _PlaylistClipState();
}

class _PlaylistClipState extends ConsumerState<PlaylistClip> {
  static const bool _disablePlaylistDrag =
      String.fromEnvironment('DISABLE_PLAYLIST_DRAG', defaultValue: '0') == '1';

  MediaItem get item => widget.item;
  double get size => widget.size;

  @override
  Widget build(BuildContext context) {
    final content = ClipContainer(
      item: widget.item,
      isSelected: widget.isSelected,
      onTap: widget.onTap,
      size: widget.size,
      showCloseButton: true,
      onClose: widget.onRemove,
      deferThumbnailsDuringStartup: !widget.allowThumbnails,
      forcePlaceholderThumbnail: !widget.allowThumbnails,
    );

    if (_disablePlaylistDrag) {
      return GestureDetector(
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: content,
      );
    }

    // Use only Flutter's Draggable for internal reordering.
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: Draggable<int>(
        data: widget.index,
        feedback: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          child: _buildDragFeedback(context),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: ClipContainer(
            item: widget.item,
            isSelected: widget.isSelected,
            size: widget.size,
            showCloseButton: true,
            onClose: widget.onRemove,
            deferThumbnailsDuringStartup: !widget.allowThumbnails,
            forcePlaceholderThumbnail: !widget.allowThumbnails,
          ),
        ),
        child: content,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final colors = KumihoTheme.of(context);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: colors.surfaceLighter,
      items: [
        PopupMenuItem<String>(
          value: 'kref',
          child: Row(
            children: [
              Icon(Icons.link, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copy Kref',
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'location',
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copy Location',
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      
      String textToCopy;
      String message;
      
      if (value == 'kref') {
        textToCopy = item.kref ?? item.id;
        message = 'Kref copied to clipboard';
      } else {
        textToCopy = item.location ?? item.thumbnailPath ?? '';
        message = 'Location copied to clipboard';
      }
      
      Clipboard.setData(ClipboardData(text: textToCopy));
      
      // Show snackbar confirmation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Widget _buildDragFeedback(BuildContext context) {
    // Use dark background for videos
    final backgroundColor = item.isVideo ? const Color(0xFF2A2A2A) : item.thumbColor;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KumihoTheme.primary, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailContent(context),
          // Video play overlay
          if (item.isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: size * 0.2,
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

  Widget _buildThumbnailContent(BuildContext context) {
    final cachePx = (size * MediaQuery.of(context).devicePixelRatio).round().clamp(64, 768);

    // For video items without an image thumbnail, use VideoThumbnail
    if (item.isVideo && item.thumbnailPath != null && !_hasImageThumbnail) {
      return VideoThumbnail(
        videoPath: item.thumbnailPath!,
        fit: BoxFit.cover,
        placeholder: _buildPlaceholder(),
        errorWidget: _buildPlaceholder(),
      );
    }
    
    // Image thumbnail
    if (item.hasLocalThumbnail && _hasImageThumbnail) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    } else if (item.hasHttpThumbnail) {
      return Image.network(
        item.thumbnailPath!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        item.isVideo ? Icons.videocam : Icons.image,
        color: Colors.white.withAlpha(128),
        size: size * 0.25,
      ),
    );
  }
}
