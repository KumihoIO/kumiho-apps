// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/browser_provider.dart';
import '../core/perf/perf_logger.dart';
import '../theme/kumiho_theme.dart';
import 'clip_container.dart';
import 'image_viewer.dart';

/// Resizable bottom playlist area
class PlaylistArea extends ConsumerWidget {
  const PlaylistArea({super.key});

  static const bool _disablePlaylistDnd =
      String.fromEnvironment('DISABLE_PLAYLIST_DND', defaultValue: '0') == '1';
  static const bool _forceEnablePlaylistDnd =
      String.fromEnvironment('FORCE_ENABLE_PLAYLIST_DND', defaultValue: '0') == '1';
  static const int _startupDisablePlaylistDndMs =
      int.fromEnvironment('STARTUP_DISABLE_PLAYLIST_DND_MS', defaultValue: 30000);

  static int _lastDndDisabledLogMs = -1000000;

  static bool _isPlaylistDndDisabledNow() {
    if (_forceEnablePlaylistDnd) return false;
    if (_disablePlaylistDnd) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
    if (_startupDisablePlaylistDndMs <= 0) return false;
    return PerfLogger.sinceStartMs() < _startupDisablePlaylistDndMs;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);

    final dndDisabled = _isPlaylistDndDisabledNow();

    // Calculate clip size based on playlist height AND zoom factor
    // Use ClipContainer.minSize as minimum to prevent RenderFlex overflow
    final availableHeight = state.playlistHeight - 34;
    final baseClipSize = (availableHeight - 16).clamp(ClipContainer.minSize, 200.0);
    // Apply zoom: 0.0 = 50% size, 0.5 = 100% size, 1.0 = 150% size
    final zoomMultiplier = 0.5 + state.playlistZoom;
    final clipSize = (baseClipSize * zoomMultiplier).clamp(ClipContainer.minSize, 300.0);

    if (dndDisabled && PerfLogger.enabled) {
      final now = PerfLogger.sinceStartMs();
      if (now - _lastDndDisabledLogMs >= 2000) {
        _lastDndDisabledLogMs = now;
        PerfLogger.log('PlaylistArea: DND disabled during startup');
      }
    }

    return Column(
      children: [
        // Resize handle
        _ResizeHandle(
          onDrag: (delta) => notifier.setPlaylistHeight(state.playlistHeight - delta),
        ),
        // Playlist content (optionally wrapped in DragTarget for internal drops)
        Builder(
          builder: (context) {
            Widget buildContent({required bool isHovering}) {
              final colors = KumihoTheme.of(context);
              return Container(
                height: state.playlistHeight,
                decoration: BoxDecoration(
                  color: colors.backgroundSidebar,
                  border: isHovering
                      ? Border.all(color: KumihoTheme.primary, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    _PlaylistHeader(
                      playlistName: state.selectedPlaylist?.name,
                      itemCount: state.playlistItems.length,
                      zoom: state.playlistZoom,
                      onZoomChanged: notifier.setPlaylistZoom,
                    ),
                    Expanded(
                      child: state.playlistItems.isEmpty
                          ? _EmptyPlaylist(dndDisabled: dndDisabled)
                          : _PlaylistItems(
                              items: state.playlistItems,
                              clipSize: clipSize,
                              selectedItemId: state.selectedItem?.id,
                              onItemTap: notifier.selectItem,
                              onRemove: notifier.removeFromPlaylist,
                              onReorder: notifier.reorderPlaylist,
                            ),
                    ),
                  ],
                ),
              );
            }

            if (dndDisabled) {
              return buildContent(isHovering: false);
            }

            return DragTarget<List<MediaItem>>(
              onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
              onAcceptWithDetails: (details) {
                notifier.addMultipleToPlaylist(details.data);
              },
              builder: (context, candidateData, rejectedData) {
                return buildContent(isHovering: candidateData.isNotEmpty);
              },
            );
          },
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
      onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: 6,
          decoration: BoxDecoration(
            color: colors.borderDark,
            border: Border(
              top: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 3,
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

// ==================== PLAYLIST HEADER ==================== //

class _PlaylistHeader extends ConsumerWidget {
  final String? playlistName;
  final int itemCount;
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const _PlaylistHeader({
    required this.playlistName,
    required this.itemCount,
    required this.zoom,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final notifier = ref.read(browserProvider.notifier);
    
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
      ),
      child: Row(
        children: [
          // Collapse/minimize button
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: 16, color: colors.textMuted),
            onPressed: notifier.toggleShowPlaylistArea,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            tooltip: 'Minimize playlist',
          ),
          const SizedBox(width: 4),
          const Icon(Icons.playlist_play, size: 16, color: KumihoTheme.primary),
          const SizedBox(width: 8),
          Text(
            playlistName ?? 'No Playlist Selected',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$itemCount items',
            style: TextStyle(color: colors.textDimmed, fontSize: 10),
          ),
          const Spacer(),
          // Playlist zoom
          Icon(Icons.photo_size_select_small, size: 12, color: colors.textVeryDimmed),
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: KumihoTheme.primary,
                inactiveTrackColor: colors.borderLight,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: zoom,
                onChanged: onZoomChanged,
                min: 0.0,
                max: 1.0,
                divisions: 100,
              ),
            ),
          ),
          Icon(Icons.photo_size_select_large, size: 12, color: colors.textVeryDimmed),
        ],
      ),
    );
  }
}

// ==================== EMPTY PLAYLIST ==================== //

class _EmptyPlaylist extends ConsumerWidget {
  final bool dndDisabled;

  const _EmptyPlaylist({required this.dndDisabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    Widget buildEmpty({required bool isHovering, required int itemCount}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isHovering ? KumihoTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHovering ? KumihoTheme.primary : colors.borderSubtle.withValues(alpha: 0.3),
            width: isHovering ? 2 : 1,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHovering ? Icons.add_circle : Icons.drag_indicator,
                size: 24,
                color: isHovering ? KumihoTheme.primary : colors.textVeryDimmed.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              Text(
                isHovering
                    ? 'Drop to add ${itemCount > 1 ? "$itemCount items" : "item"} to playlist'
                    : 'Drag clips here to add to playlist',
                style: TextStyle(
                  color: isHovering ? KumihoTheme.primary : colors.textVeryDimmed.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: isHovering ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (dndDisabled) {
      return buildEmpty(isHovering: false, itemCount: 0);
    }

    return DragTarget<List<MediaItem>>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        ref.read(browserProvider.notifier).addMultipleToPlaylist(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final itemCount = isHovering ? candidateData.first?.length ?? 0 : 0;
        return buildEmpty(isHovering: isHovering, itemCount: itemCount);
      },
    );
  }
}

// ==================== PLAYLIST ITEMS ==================== //

class _PlaylistItems extends ConsumerStatefulWidget {
  final List<MediaItem> items;
  final double clipSize;
  final String? selectedItemId;
  final ValueChanged<MediaItem> onItemTap;
  final ValueChanged<int> onRemove;
  final void Function(int fromIndex, int toIndex) onReorder;

  const _PlaylistItems({
    required this.items,
    required this.clipSize,
    required this.selectedItemId,
    required this.onItemTap,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  ConsumerState<_PlaylistItems> createState() => _PlaylistItemsState();
}

class _PlaylistItemsState extends ConsumerState<_PlaylistItems> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Escape hatch for troubleshooting.
  static const bool _disablePlaylistThumbnails =
      String.fromEnvironment('DISABLE_PLAYLIST_THUMBNAILS', defaultValue: '0') == '1';

  bool _allowPlaylistThumbnailsNow() {
    return !_disablePlaylistThumbnails;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPlaylistFocused() {
    ref.read(browserProvider.notifier).setActiveContext(BrowserContext.playlist);
  }

  void _onItemTapped(MediaItem item) {
    // Request focus and set context so Space key works in playlist context
    _focusNode.requestFocus();
    _onPlaylistFocused();
    widget.onItemTap(item);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    // Space key opens the image viewer in playlist context (only when this Focus has keyboard focus)
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final selectedId = widget.selectedItemId;
      if (selectedId != null) {
        final selectedItem = widget.items.firstWhere(
          (i) => i.id == selectedId,
          orElse: () => widget.items.first,
        );
        ref.read(playbackModeActiveProvider.notifier).state = true;
        showImageViewerAsync(
          context,
          selectedItem,
          items: widget.items, // Use playlist items for navigation context
          onNavigate: (item) {
            widget.onItemTap(item);
          },
        ).whenComplete(() {
          ref.read(playbackModeActiveProvider.notifier).state = false;
        });
        return KeyEventResult.handled;
      }
    }
    
    // Delete key removes selected item from playlist
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      final selectedId = widget.selectedItemId;
      if (selectedId != null) {
        final index = widget.items.indexWhere((i) => i.id == selectedId);
        if (index >= 0) {
          widget.onRemove(index);
          return KeyEventResult.handled;
        }
      }
    }
    
    // Arrow keys for navigation within playlist
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _navigatePlaylist(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _navigatePlaylist(1);
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
  
  void _navigatePlaylist(int delta) {
    if (widget.items.isEmpty) return;
    
    final selectedId = widget.selectedItemId;
    int currentIndex = 0;
    
    if (selectedId != null) {
      currentIndex = widget.items.indexWhere((i) => i.id == selectedId);
      if (currentIndex < 0) currentIndex = 0;
    }
    
    final newIndex = (currentIndex + delta).clamp(0, widget.items.length - 1);
    widget.onItemTap(widget.items[newIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus) _onPlaylistFocused();
      },
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: widget.items.length * 2 + 1,
            itemBuilder: (context, index) {
              if (index.isEven) {
                final insertIndex = index ~/ 2;
                return _DropZone(
                  insertIndex: insertIndex,
                  clipSize: widget.clipSize,
                  onReorder: widget.onReorder,
                );
              }

              final itemIndex = index ~/ 2;
              final item = widget.items[itemIndex];
              return PlaylistClip(
                item: item,
                index: itemIndex,
                size: widget.clipSize,
                isSelected: widget.selectedItemId == item.id,
                allowThumbnails: _allowPlaylistThumbnailsNow(),
                onTap: () => _onItemTapped(item),
                onRemove: () => widget.onRemove(itemIndex),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ==================== DROP ZONE ==================== //

class _DropZone extends ConsumerStatefulWidget {
  final int insertIndex;
  final double clipSize;
  final void Function(int fromIndex, int toIndex) onReorder;

  const _DropZone({
    required this.insertIndex,
    required this.clipSize,
    required this.onReorder,
  });

  @override
  ConsumerState<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends ConsumerState<_DropZone> {
  static const bool _disablePlaylistDropZones =
      String.fromEnvironment('DISABLE_PLAYLIST_DROPZONES', defaultValue: '0') == '1';

  @override
  Widget build(BuildContext context) {
    if (_disablePlaylistDropZones || PlaylistArea._isPlaylistDndDisabledNow()) {
      return const SizedBox.shrink();
    }

    final colors = KumihoTheme.of(context);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Accept int for reordering existing items (internal playlist drag)
        DragTarget<int>(
          onWillAcceptWithDetails: (details) =>
              details.data != widget.insertIndex && details.data != widget.insertIndex - 1,
          onAcceptWithDetails: (details) => widget.onReorder(details.data, widget.insertIndex),
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isHovering ? KumihoTheme.dropZoneHoverWidth : KumihoTheme.dropZoneWidth,
              height: widget.clipSize,
              margin: EdgeInsets.symmetric(horizontal: isHovering ? 4 : 2),
              decoration: BoxDecoration(
                color: isHovering ? KumihoTheme.primary : colors.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          },
        ),
        // Accept List<MediaItem> from Flutter Draggable for adding new items from browser
        DragTarget<List<MediaItem>>(
          onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
          onAcceptWithDetails: (details) {
            ref.read(browserProvider.notifier).addMultipleToPlaylist(details.data);
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            final count = isHovering ? candidateData.first?.length ?? 0 : 0;
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isHovering ? KumihoTheme.dropZoneHoverWidth : 0,
              height: widget.clipSize,
              margin: EdgeInsets.symmetric(horizontal: isHovering ? 4 : 0),
              decoration: BoxDecoration(
                color: KumihoTheme.success.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isHovering
                  ? Center(
                      child: count > 1
                          ? Text('+$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                          : const Icon(Icons.add, color: Colors.white, size: 20),
                    )
                  : null,
            );
          },
        ),
      ],
    );
  }
}
