// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/kumiho_provider.dart';
import '../theme/kumiho_theme.dart';
import 'video_player_widget.dart';

/// Shows a fullscreen image viewer overlay for the given media item.
/// 
/// Supports:
/// - Zoom in/out with mouse wheel or +/- keys
/// - Pan when zoomed in by dragging
/// - Reset zoom with 0 key or double-click
/// - Close with Escape or clicking outside
/// - Navigate with arrow keys if items list provided
void showImageViewer(
  BuildContext context, 
  MediaItem item, {
  List<MediaItem>? items,
  void Function(MediaItem)? onNavigate,
}) {
  // Backwards-compatible wrapper.
  showImageViewerAsync(context, item, items: items, onNavigate: onNavigate);
}

Future<void> showImageViewerAsync(
  BuildContext context,
  MediaItem item, {
  List<MediaItem>? items,
  void Function(MediaItem)? onNavigate,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    builder: (context) => ImageViewerOverlay(
      item: item,
      items: items,
      onNavigate: onNavigate,
    ),
  );
}

/// Fullscreen image viewer overlay with zoom and pan support
class ImageViewerOverlay extends ConsumerStatefulWidget {
  final MediaItem item;
  final List<MediaItem>? items;
  final void Function(MediaItem)? onNavigate;

  const ImageViewerOverlay({
    super.key,
    required this.item,
    this.items,
    this.onNavigate,
  });

  @override
  ConsumerState<ImageViewerOverlay> createState() => _ImageViewerOverlayState();
}

class _ImageViewerOverlayState extends ConsumerState<ImageViewerOverlay> {
  late MediaItem _currentItem;
  final TransformationController _transformController = TransformationController();
  
  // Zoom constraints
  static const double _minZoom = 0.5;
  static const double _maxZoom = 5.0;
  static const double _zoomStep = 0.25;
  
  double _currentZoom = 1.0;
  final FocusNode _focusNode = FocusNode();
  
  // GlobalKey to control video player
  final GlobalKey<VideoPlayerWidgetState> _videoPlayerKey = GlobalKey<VideoPlayerWidgetState>();

  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    // Request focus for keyboard input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _maybeResolvePreview();
  }

  Future<void> _maybeResolvePreview() async {
    final token = ++_previewGeneration;
    final item = _currentItem;

    // Nothing to resolve for videos or already-displayable images.
    if (item.isVideo || item.hasLocalThumbnail || item.hasHttpThumbnail) return;

    // Only base 'item' tiles lack thumbnail/location; try to resolve a preview.
    if (item.type != 'item') return;

    final preview = await ref.read(pagedItemsProvider.notifier).fetchPreviewForItem(item);
    if (!mounted || token != _previewGeneration) return;
    if (preview == null) return;

    setState(() {
      _currentItem = preview;
      _resetZoom();
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        break;
      case LogicalKeyboardKey.equal: // + key (with shift) or = key
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        if (!_currentItem.isVideo) _zoomIn();
        break;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        if (!_currentItem.isVideo) _zoomOut();
        break;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        if (!_currentItem.isVideo) _resetZoom();
        break;
      case LogicalKeyboardKey.keyF:
        // Fit to screen - for images only
        if (!_currentItem.isVideo) _resetZoom();
        break;
      case LogicalKeyboardKey.space:
        // Play/pause for videos
        if (_currentItem.isVideo) {
          _videoPlayerKey.currentState?.togglePlayPause();
        }
        break;
      case LogicalKeyboardKey.keyM:
        // Mute/unmute for videos
        if (_currentItem.isVideo) {
          _videoPlayerKey.currentState?.toggleMute();
        }
        break;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        _navigatePrevious();
        break;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        _navigateNext();
        break;
      case LogicalKeyboardKey.home:
        _navigateFirst();
        break;
      case LogicalKeyboardKey.end:
        _navigateLast();
        break;
    }
  }

  void _zoomIn() {
    final newZoom = math.min(_currentZoom + _zoomStep, _maxZoom);
    _setZoom(newZoom);
  }

  void _zoomOut() {
    final newZoom = math.max(_currentZoom - _zoomStep, _minZoom);
    _setZoom(newZoom);
  }

  void _setZoom(double zoom) {
    setState(() {
      // Get the current transform to preserve translation
      final currentMatrix = _transformController.value;
      final currentScale = _currentZoom;
      
      // Calculate the center of the viewport
      final viewportSize = MediaQuery.of(context).size;
      final centerX = viewportSize.width / 2;
      final centerY = viewportSize.height / 2;
      
      // Scale around the center point
      final scaleChange = zoom / currentScale;
      final newMatrix = Matrix4.identity()
        ..translateByDouble(centerX, centerY, 0, 1)
        ..scaleByDouble(scaleChange, scaleChange, scaleChange, 1)
        ..translateByDouble(-centerX, -centerY, 0, 1)
        ..multiply(currentMatrix);
      
      _currentZoom = zoom;
      _transformController.value = newMatrix;
    });
  }

  void _resetZoom() {
    setState(() {
      _currentZoom = 1.0;
      _transformController.value = Matrix4.identity();
    });
  }

  void _onScrollZoom(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy;
      // Zoom towards/from mouse position
      final mousePosition = event.localPosition;
      if (delta < 0) {
        _zoomAtPoint(math.min(_currentZoom + _zoomStep, _maxZoom), mousePosition);
      } else if (delta > 0) {
        _zoomAtPoint(math.max(_currentZoom - _zoomStep, _minZoom), mousePosition);
      }
    }
  }

  /// Zoom at a specific point (for mouse wheel zoom)
  void _zoomAtPoint(double newZoom, Offset focalPoint) {
    if (newZoom == _currentZoom) return;
    
    setState(() {
      final currentMatrix = _transformController.value;
      final scaleChange = newZoom / _currentZoom;
      
      // Scale around the focal point
      final newMatrix = Matrix4.identity()
        ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
        ..scaleByDouble(scaleChange, scaleChange, scaleChange, 1)
        ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1)
        ..multiply(currentMatrix);
      
      _currentZoom = newZoom;
      _transformController.value = newMatrix;
    });
  }

  void _navigatePrevious() {
    if (widget.items == null || widget.items!.length <= 1) return;
    final currentIndex = widget.items!.indexWhere((i) => i.id == _currentItem.id);
    if (currentIndex > 0) {
      setState(() {
        _currentItem = widget.items![currentIndex - 1];
        _resetZoom();
      });
      widget.onNavigate?.call(_currentItem);
      // Re-request focus to ensure keyboard events work after navigation
      _focusNode.requestFocus();
      _maybeResolvePreview();
    }
  }

  void _navigateNext() {
    if (widget.items == null || widget.items!.length <= 1) return;
    final currentIndex = widget.items!.indexWhere((i) => i.id == _currentItem.id);
    if (currentIndex < widget.items!.length - 1) {
      setState(() {
        _currentItem = widget.items![currentIndex + 1];
        _resetZoom();
      });
      widget.onNavigate?.call(_currentItem);
      // Re-request focus to ensure keyboard events work after navigation
      _focusNode.requestFocus();
      _maybeResolvePreview();
    }
  }

  void _navigateFirst() {
    if (widget.items == null || widget.items!.isEmpty) return;
    setState(() {
      _currentItem = widget.items!.first;
      _resetZoom();
    });
    widget.onNavigate?.call(_currentItem);
    _maybeResolvePreview();
  }

  void _navigateLast() {
    if (widget.items == null || widget.items!.isEmpty) return;
    setState(() {
      _currentItem = widget.items!.last;
      _resetZoom();
    });
    widget.onNavigate?.call(_currentItem);
    _maybeResolvePreview();
  }

  int get _currentIndex {
    if (widget.items == null) return 0;
    return widget.items!.indexWhere((i) => i.id == _currentItem.id);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        // Return handled to prevent event propagation for video/navigation keys
        if (event is KeyDownEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.space:
            case LogicalKeyboardKey.keyM:
            case LogicalKeyboardKey.arrowLeft:
            case LogicalKeyboardKey.arrowRight:
            case LogicalKeyboardKey.arrowUp:
            case LogicalKeyboardKey.arrowDown:
              return KeyEventResult.handled;
            default:
              break;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Main content area - video or image
          Positioned.fill(
            child: _currentItem.isVideo 
                ? _buildVideoPlayer()
                : GestureDetector(
                    onDoubleTap: _resetZoom,
                    child: Listener(
                      onPointerSignal: _onScrollZoom,
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: _minZoom,
                        maxScale: _maxZoom,
                        onInteractionEnd: (details) {
                          // Update current zoom level from transform
                          final scale = _transformController.value.getMaxScaleOnAxis();
                          setState(() => _currentZoom = scale);
                        },
                        child: Center(
                          child: _buildImage(),
                        ),
                      ),
                    ),
                  ),
          ),
          
          // Top bar with item info and close
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),
          
          // Bottom bar with zoom controls and navigation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
          
          // Navigation arrows (if multiple items)
          if (widget.items != null && widget.items!.length > 1) ...[
            // Left arrow
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavigationArrow(
                  icon: Icons.chevron_left,
                  onTap: _currentIndex > 0 ? _navigatePrevious : null,
                  tooltip: 'Previous (←)',
                ),
              ),
            ),
            // Right arrow
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavigationArrow(
                  icon: Icons.chevron_right,
                  onTap: _currentIndex < widget.items!.length - 1 ? _navigateNext : null,
                  tooltip: 'Next (→)',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    // Get the video file path from the item
    // For video items, thumbnailPath should contain the video file path
    final videoPath = _currentItem.location ?? _currentItem.thumbnailPath;
    
    if (videoPath == null) {
      return Center(
        child: _buildPlaceholder(),
      );
    }
    
    return VideoPlayerWidget(
      key: _videoPlayerKey, // Use GlobalKey to control player from keyboard
      source: videoPath,
      autoPlay: true,
      onFullscreenToggle: (_) {
        // Already in fullscreen mode, so toggle just closes
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildImage() {
    if (_currentItem.hasLocalThumbnail) {
      final filePath = _currentItem.location ?? _currentItem.thumbnailPath;
      if (filePath == null || filePath.isEmpty) {
        return _buildPlaceholder();
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.of(context).devicePixelRatio;
          final maxLogicalSide = math.max(constraints.maxWidth, constraints.maxHeight);
          // Decode roughly to viewport size (in physical pixels) to avoid huge
          // full-res decodes + GPU uploads that can hitch the UI on Windows.
          final cacheWidth = (maxLogicalSide * dpr).round().clamp(256, 4096);

          return Image.file(
            File(filePath),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return _buildPlaceholder();
            },
            errorBuilder: (context, error, stack) => _buildPlaceholder(),
          );
        },
      );
    } else if (_currentItem.hasHttpThumbnail) {
      return Image.network(
        _currentItem.thumbnailPath!,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
              color: KumihoTheme.primary,
            ),
          );
        },
        errorBuilder: (context, error, stack) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 400,
      height: 400,
      decoration: BoxDecoration(
        color: _currentItem.thumbColor.withAlpha(77),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _currentItem.isVideo ? Icons.videocam : Icons.image,
            size: 64,
            color: _currentItem.thumbColor,
          ),
          const SizedBox(height: 16),
          Text(
            _currentItem.name,
            style: const TextStyle(
              color: KumihoTheme.textPrimary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'No preview available',
            style: TextStyle(
              color: KumihoTheme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withAlpha(179),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentItem.name,
                  style: const TextStyle(
                    color: KumihoTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _currentItem.artifactName,
                      style: const TextStyle(
                        color: KumihoTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: KumihoTheme.primary.withAlpha(51),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _currentItem.revision,
                        style: const TextStyle(
                          color: KumihoTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Item counter for videos (moved from bottom to avoid obscuring video controls)
          if (_currentItem.isVideo && widget.items != null && widget.items!.length > 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: KumihoTheme.backgroundCard,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_currentIndex + 1} / ${widget.items!.length}',
                style: const TextStyle(
                  color: KumihoTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: KumihoTheme.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close (Esc)',
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withAlpha(179),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zoom controls - only for images, not videos
          if (!_currentItem.isVideo) ...[
            // Zoom out
            IconButton(
              icon: const Icon(Icons.remove, color: KumihoTheme.textPrimary, size: 20),
              onPressed: _currentZoom > _minZoom ? _zoomOut : null,
              tooltip: 'Zoom out (-)',
              splashRadius: 18,
            ),
            // Zoom indicator
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: KumihoTheme.backgroundCard,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(_currentZoom * 100).toInt()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KumihoTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Zoom in
            IconButton(
              icon: const Icon(Icons.add, color: KumihoTheme.textPrimary, size: 20),
              onPressed: _currentZoom < _maxZoom ? _zoomIn : null,
              tooltip: 'Zoom in (+)',
              splashRadius: 18,
            ),
            const SizedBox(width: 16),
            // Reset zoom
            IconButton(
              icon: const Icon(Icons.fit_screen, color: KumihoTheme.textPrimary, size: 20),
              onPressed: _resetZoom,
              tooltip: 'Fit to screen (F)',
              splashRadius: 18,
            ),
          ],
          // Item counter (if multiple items) - only for images, videos show it in top bar
          if (!_currentItem.isVideo && widget.items != null && widget.items!.length > 1) ...[
            const SizedBox(width: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: KumihoTheme.backgroundCard,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_currentIndex + 1} / ${widget.items!.length}',
                style: const TextStyle(
                  color: KumihoTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Navigation arrow button for prev/next
class _NavigationArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  const _NavigationArrow({
    required this.icon,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isEnabled 
                  ? KumihoTheme.backgroundCard.withAlpha(204)
                  : KumihoTheme.backgroundCard.withAlpha(77),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: isEnabled 
                  ? KumihoTheme.textPrimary 
                  : KumihoTheme.textDimmed,
            ),
          ),
        ),
      ),
    );
  }
}
