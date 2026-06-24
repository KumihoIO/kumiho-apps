// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/kumiho_theme.dart';
import 'clip_container.dart';
import 'image_viewer.dart';

Color _chipAccent(BuildContext context, Color base) {
  if (KumihoTheme.isDarkMode(context)) return base;
  final hsl = HSLColor.fromColor(base);
  return hsl
  // Keep the hue cue but avoid looking heavy in light theme.
      .withLightness((hsl.lightness * 0.74).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
      .toColor();
}

Color _chipTextAccent(BuildContext context, Color base) {
  if (KumihoTheme.isDarkMode(context)) return base;
  final accent = _chipAccent(context, base);
  final hsl = HSLColor.fromColor(accent);
  // Slightly darker than the accent fill so text reads better.
  return hsl.withLightness((hsl.lightness * 0.82).clamp(0.0, 1.0)).toColor();
}

double _chipBgAlpha(BuildContext context) => KumihoTheme.isDarkMode(context) ? 0.15 : 0.20;
double _chipBorderAlpha(BuildContext context) => KumihoTheme.isDarkMode(context) ? 0.30 : 0.46;
double _chipIconAlpha(BuildContext context) => KumihoTheme.isDarkMode(context) ? 0.60 : 0.70;

/// Grid view for media items
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({super.key});

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final pagedState = ref.read(pagedItemsProvider);
    // Avoid repeatedly triggering pagination while we're already loading.
    // This became particularly important after introducing a placeholder GridView
    // for the first paint, where maxScrollExtent can be 0.
    if (pagedState.isLoading || !pagedState.hasMore) return;

    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;

    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(pagedItemsProvider.notifier).loadNextPage();
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, MediaItem? selectedItem, List<MediaItem> items, int columnsCount) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    // Space key opens the image viewer (only when this Focus has keyboard focus)
    if (event.logicalKey == LogicalKeyboardKey.space && selectedItem != null) {
      ref.read(playbackModeActiveProvider.notifier).state = true;
      showImageViewerAsync(
        context,
        selectedItem,
        items: items,
        onNavigate: (item) {
          ref.read(browserProvider.notifier).selectItem(item);
        },
      ).whenComplete(() {
        ref.read(playbackModeActiveProvider.notifier).state = false;
      });
      return KeyEventResult.handled; // Consume the event
    }
    
    // Arrow key navigation in grid
    if (items.isNotEmpty) {
      final currentIndex = selectedItem != null 
          ? items.indexWhere((i) => i.id == selectedItem.id)
          : -1;
      int? newIndex;
      
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          if (currentIndex > 0) newIndex = currentIndex - 1;
          break;
        case LogicalKeyboardKey.arrowRight:
          if (currentIndex < items.length - 1) newIndex = currentIndex + 1;
          else if (currentIndex < 0) newIndex = 0;
          break;
        case LogicalKeyboardKey.arrowUp:
          if (currentIndex >= columnsCount) {
            newIndex = currentIndex - columnsCount;
          } else if (currentIndex < 0) {
            newIndex = 0;
          }
          break;
        case LogicalKeyboardKey.arrowDown:
          if (currentIndex < 0) {
            newIndex = 0;
          } else if (currentIndex + columnsCount < items.length) {
            newIndex = currentIndex + columnsCount;
          } else if (currentIndex < items.length - 1) {
            // Go to last item if we can't go down a full row
            newIndex = items.length - 1;
          }
          break;
      }
      
      if (newIndex != null && newIndex >= 0 && newIndex < items.length) {
        ref.read(browserProvider.notifier).selectItem(items[newIndex]);
        return KeyEventResult.handled;
      }
    }
    
    return KeyEventResult.ignored;
  }

  void _onGridFocused() {
    ref.read(browserProvider.notifier).setActiveContext(BrowserContext.grid);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);
    final canBrowse = ref.watch(canBrowseProvider);
    final pagedState = ref.watch(pagedItemsProvider);
    
    // Calculate grid dimensions with minimum size protection
    final itemSize = (100.0 + (state.gridZoom * 140.0)).clamp(ClipContainer.minSize, 300.0);
    const gridSpacing = 8.0;

    // Use Kumiho items if we can browse (authenticated OR anonymous with tenant ID)
    if (canBrowse) {
      final items = ref.watch(kumihoMediaItemsProvider);
      final spacePath = ref.watch(selectedSpacePathProvider);
      final project = ref.watch(selectedProjectNameProvider);

      final colors = KumihoTheme.of(context);

          // Project-root loading: show a few placeholder tiles immediately so
          // the grid paints instantly while the first item list is fetched.
          if (spacePath.isEmpty && pagedState.isLoading && pagedState.items.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final columnsCount = _FixedTileSizeGridDelegate.computeCrossAxisCount(
                  crossAxisExtent: constraints.maxWidth,
                  tileSize: itemSize,
                  crossAxisSpacing: gridSpacing,
                ).clamp(1, 100);

                final placeholderCount = (columnsCount * 2).clamp(5, 12);

                Widget placeholderTile(int i) {
                  // Keep this extremely lightweight; ClipContainer does a fair
                  // amount of layout work which defeats the purpose of a fast
                  // first paint.
                  final colorHash = i.hashCode;
                  final hue = (colorHash % 360).abs().toDouble();
                  final fill = HSVColor.fromAHSV(1.0, hue, 0.08, 0.22).toColor();
                  return Container(
                    width: itemSize,
                    height: itemSize,
                    decoration: BoxDecoration(
                      color: colors.backgroundList,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderLight),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ColoredBox(
                        color: fill,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted.withValues(alpha: 0.7)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  // Intentionally do NOT attach the main scroll controller here.
                  // Attaching it while maxScrollExtent is 0 can cause _onScroll()
                  // to spam loadNextPage(), which hurts drag/drop responsiveness.
                  primary: false,
                  padding: const EdgeInsets.all(12),
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: _FixedTileSizeGridDelegate(
                    tileSize: itemSize,
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                  ),
                  itemCount: placeholderCount,
                  itemBuilder: (context, index) {
                    return placeholderTile(index);
                  },
                );
              },
            );
          }

          if (items.isEmpty && spacePath.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: colors.textDimmed.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No items in this space',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items created in ComfyUI will appear here',
                    style: TextStyle(
                      color: colors.textDimmed,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }
          
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_upward, size: 48, color: colors.textDimmed.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    project == null ? 'Select a project to browse items' : 'No items in project',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }
          
          return LayoutBuilder(
            builder: (context, constraints) {
              // Calculate number of columns for arrow key navigation
              final columnsCount = _FixedTileSizeGridDelegate.computeCrossAxisCount(
                crossAxisExtent: constraints.maxWidth,
                tileSize: itemSize,
                crossAxisSpacing: gridSpacing,
              ).clamp(1, 100);
              
              return Focus(
                focusNode: _focusNode,
                autofocus: true,
                onFocusChange: (hasFocus) {
                  if (hasFocus) _onGridFocused();
                },
                onKeyEvent: (node, event) => _handleKeyEvent(event, state.selectedItem, items, columnsCount),
                child: GestureDetector(
                  onTap: () {
                    _focusNode.requestFocus();
                    _onGridFocused();
                  },
                  behavior: HitTestBehavior.translucent,
                  // Use SliverGridDelegateWithMaxCrossAxisExtent for responsive layout
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: _FixedTileSizeGridDelegate(
                      tileSize: itemSize,
                      mainAxisSpacing: gridSpacing,
                      crossAxisSpacing: gridSpacing,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];

                      return DraggableClipContainer(
                        key: ValueKey(item.id),
                        item: item,
                        isSelected: state.selectedItem?.id == item.id,
                        onTap: () {
                          _focusNode.requestFocus();  // Request focus on grid
                          _onGridFocused();
                          notifier.selectItem(item);
                        },
                        allItems: items, // Pass all items for multi-select support
                      );
                    },
                  ),
                ),
              );
            },
          );
    }

    // Show sign-in prompt when not authenticated and no tenant ID
    final colors = KumihoTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 80,
            color: colors.textDimmed.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Sign in to browse your assets',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Connect your Kumiho account to view and manage\nyour projects, spaces, and media items.',
            style: TextStyle(
              color: colors.textDimmed,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'Sign in via the profile icon, or set a Tenant ID\nin Settings to browse public projects anonymously.',
            style: TextStyle(
              color: colors.textDimmed.withValues(alpha: 0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A grid delegate that keeps each tile at a fixed size (in pixels) rather than
/// stretching tiles to fill available width. This makes zooming feel linear
/// because tile size changes continuously with the zoom value.
class _FixedTileSizeGridDelegate extends SliverGridDelegate {
  final double tileSize;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const _FixedTileSizeGridDelegate({
    required this.tileSize,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
  });

  static int computeCrossAxisCount({
    required double crossAxisExtent,
    required double tileSize,
    required double crossAxisSpacing,
  }) {
    // Max tiles that fit without overflow, leaving any remaining space at the end.
    final raw = ((crossAxisExtent + crossAxisSpacing) / (tileSize + crossAxisSpacing)).floor();
    return raw.clamp(1, 1000000);
  }

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final crossAxisCount = computeCrossAxisCount(
      crossAxisExtent: constraints.crossAxisExtent,
      tileSize: tileSize,
      crossAxisSpacing: crossAxisSpacing,
    );

    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: tileSize + mainAxisSpacing,
      crossAxisStride: tileSize + crossAxisSpacing,
      childMainAxisExtent: tileSize,
      childCrossAxisExtent: tileSize,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant _FixedTileSizeGridDelegate oldDelegate) {
    return tileSize != oldDelegate.tileSize ||
        mainAxisSpacing != oldDelegate.mainAxisSpacing ||
        crossAxisSpacing != oldDelegate.crossAxisSpacing;
  }
}

/// List view for media items (Item-centric for list view mode)
/// Shows items with their kind, author, created/modified dates
class MediaList extends ConsumerStatefulWidget {
  const MediaList({super.key});

  @override
  ConsumerState<MediaList> createState() => _MediaListState();
}

class _MediaListState extends ConsumerState<MediaList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final spacePath = ref.read(selectedSpacePathProvider);
      if (spacePath.isEmpty) {
        ref.read(pagedItemsProvider.notifier).loadNextPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canBrowse = ref.watch(canBrowseProvider);
    final colors = KumihoTheme.of(context);
    
    if (canBrowse) {
      // Use combined provider for spaces + items
      final entriesAsync = ref.watch(listViewEntriesProvider);
      
      return entriesAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            final spacePath = ref.watch(selectedSpacePathProvider);
            if (spacePath.isNotEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: colors.textDimmed.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Empty space',
                      style: TextStyle(color: colors.textMuted, fontSize: 16),
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_upward, size: 48, color: colors.textDimmed.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Select a project to browse',
                    style: TextStyle(color: colors.textMuted, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          
          return Column(
            children: [
              const _ItemListHeader(),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return switch (entry) {
                      SpaceEntry(:final space) => _SpaceListRow(
                          space: space,
                          index: index,
                        ),
                      ItemEntry(:final item) => _ItemListRow(
                          item: item,
                          index: index,
                        ),
                    };
                  },
                ),
              ),
            ],
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: KumihoTheme.primary),
              const SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: colors.textMuted)),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text('Error loading content', style: TextStyle(color: colors.textMuted, fontSize: 16)),
              const SizedBox(height: 8),
              Text(error.toString(), style: TextStyle(color: colors.textDimmed, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // Show sign-in prompt when not authenticated and no tenant ID
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 80,
            color: colors.textDimmed.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Sign in to browse your assets',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sign in via the profile icon, or set a Tenant ID\\nin Settings to browse public projects anonymously.',
            style: TextStyle(
              color: colors.textDimmed,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ==================== SPACE LIST ROW ==================== //

/// Row widget for displaying a space (folder) in list view
/// Double-click to navigate into the space
class _SpaceListRow extends ConsumerWidget {
  final SpaceListEntry space;
  final int index;

  const _SpaceListRow({
    required this.space,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final accent = _chipAccent(context, space.color);
    final textAccent = _chipTextAccent(context, space.color);
    
    return GestureDetector(
      onDoubleTap: () => _navigateToSpace(ref),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide date columns on narrow screens
          final showDates = constraints.maxWidth > 600;
          final showHint = constraints.maxWidth > 500;
          
          return Container(
            height: 44.0,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: index.isEven ? colors.backgroundList : colors.background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                // Folder icon
                _FolderIconBadge(space: space),
                const SizedBox(width: 12),
                // Space name
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          space.name,
                          style: TextStyle(
                            color: space.deprecated ? colors.textDimmed : colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: space.deprecated ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Folder indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: _chipBgAlpha(context)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subdirectory_arrow_right, size: 10, color: textAccent),
                            const SizedBox(width: 2),
                            Text(
                              'Space',
                              style: TextStyle(
                                color: textAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Kind column (shows "Folder")
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: _chipBgAlpha(context)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: accent.withValues(alpha: _chipBorderAlpha(context))),
                        ),
                        child: Text(
                          'Folder',
                          style: TextStyle(
                            color: textAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Author
                Expanded(
                  flex: 2,
                  child: Text(
                    space.username.isNotEmpty ? space.username : space.author,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Created date - hide on narrow screens
                if (showDates) ...[
                  SizedBox(
                    width: 100,
                    child: Text(
                      _formatDate(space.createdAt),
                      style: TextStyle(color: colors.textDimmed, fontSize: 11),
                    ),
                  ),
                  // Modified date
                  SizedBox(
                    width: 100,
                    child: Text(
                      _formatDate(space.modifiedAt),
                      style: TextStyle(color: colors.textDimmed, fontSize: 11),
                    ),
                  ),
                ],
                // Double-click hint - hide on narrow screens
                if (showHint)
                  SizedBox(
                    width: 60,
                    child: Tooltip(
                      message: 'Double-click to open',
                      child: Icon(
                        Icons.keyboard_double_arrow_right,
                        size: 16,
                        color: accent.withValues(alpha: _chipIconAlpha(context)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigateToSpace(WidgetRef ref) {
    // Extract the space name from the path and add it to the current path
    final pathParts = space.spacePath.split('/').where((p) => p.isNotEmpty).toList();
    if (pathParts.length >= 2) {
      // pathParts[0] is project name, rest are space path
      final newSpacePath = pathParts.sublist(1);
      
      // Clear any existing selection when navigating
      ref.read(listViewSelectionNotifierProvider.notifier).clearAll();
      
      // Update the space path
      ref.read(selectedSpacePathProvider.notifier).state = newSpacePath;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}mo ago';
    }
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

// ==================== FOLDER ICON BADGE ==================== //

/// Icon badge for folders/spaces
class _FolderIconBadge extends StatelessWidget {
  final SpaceListEntry space;

  const _FolderIconBadge({required this.space});

  @override
  Widget build(BuildContext context) {
    final accent = _chipAccent(context, space.color);
    final isDark = KumihoTheme.isDarkMode(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.35 : 0.38),
            accent.withValues(alpha: isDark ? 0.20 : 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.40 : 0.48),
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main folder icon
          Icon(
            Icons.folder_rounded,
            color: accent,
            size: 18,
          ),
          // Deprecated indicator
          if (space.deprecated)
            Positioned(
              left: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(color: KumihoTheme.backgroundCard, width: 1),
                ),
                child: const Icon(Icons.close, size: 6, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== ITEM ICON BADGE ==================== //

/// Creative icon badge for items in list view
/// Shows kind-based icon with gradient background and subtle decorations
class _ItemIconBadge extends StatelessWidget {
  final ItemListEntry item;
  final bool isSelected;

  const _ItemIconBadge({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final baseColor = _chipAccent(context, item.kindColor);
    final iconColor = _chipTextAccent(context, item.kindColor);
    final isDark = KumihoTheme.isDarkMode(context);
    
    // Create a unique but consistent secondary color based on item name
    final hue = (item.name.hashCode % 60 - 30).toDouble();
    final secondaryColor = HSLColor.fromColor(baseColor)
        .withHue((HSLColor.fromColor(baseColor).hue + hue) % 360)
        .toColor();

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withValues(alpha: isSelected ? 0.32 : (isDark ? 0.25 : 0.20)),
            secondaryColor.withValues(alpha: isSelected ? 0.24 : (isDark ? 0.15 : 0.12)),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? baseColor
              : baseColor.withValues(alpha: isDark ? 0.30 : 0.26),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: baseColor.withValues(alpha: isDark ? 0.30 : 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background pattern for some kinds
          if (_hasPattern(item.kind))
            Positioned(
              right: -2,
              bottom: -2,
              child: Icon(
                _getPatternIcon(item.kind),
                size: 14,
                color: baseColor.withValues(alpha: isDark ? 0.20 : 0.14),
              ),
            ),
          // Main icon
          Icon(
            item.kindIcon,
            color: isSelected ? iconColor : iconColor.withValues(alpha: 0.9),
            size: 16,
          ),
          // Revision count indicator (if > 1)
          if (item.revisionCount > 1)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: KumihoTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: baseColor.withValues(alpha: 0.5), width: 0.5),
                ),
                child: Text(
                  '${item.revisionCount}',
                  style: TextStyle(
                    color: baseColor,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // Deprecated indicator
          if (item.deprecated)
            Positioned(
              left: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(color: KumihoTheme.backgroundCard, width: 1),
                ),
                child: const Icon(Icons.close, size: 6, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasPattern(String kind) {
    return ['workflow', 'model', 'checkpoint', 'lora'].contains(kind.toLowerCase());
  }

  IconData _getPatternIcon(String kind) {
    switch (kind.toLowerCase()) {
      case 'workflow':
        return Icons.share;
      case 'model':
      case 'checkpoint':
        return Icons.memory;
      case 'lora':
        return Icons.tune;
      default:
        return Icons.circle;
    }
  }
}

// ==================== ITEM LIST HEADER (New) ==================== //

class _ItemListHeader extends ConsumerWidget {
  const _ItemListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    
    return Container(
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.backgroundList,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide date columns on narrow screens
          final showDates = constraints.maxWidth > 600;
          final showRevisions = constraints.maxWidth > 500;
          
          return Row(
            children: [
              const SizedBox(width: 32), // Icon column
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _headerText(context, 'Item Name')),
              Expanded(flex: 2, child: _headerText(context, 'Kind')),
              Expanded(flex: 2, child: _headerText(context, 'Author')),
              if (showDates) ...[
                SizedBox(width: 100, child: _headerText(context, 'Created')),
                SizedBox(width: 100, child: _headerText(context, 'Modified')),
              ],
              if (showRevisions) const SizedBox(width: 60), // Revisions count
            ],
          );
        },
      ),
    );
  }

  Widget _headerText(BuildContext context, String text) {
    final colors = KumihoTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: colors.textDimmed,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ==================== ITEM LIST ROW (New) ==================== //

class _ItemListRow extends ConsumerWidget {
  final ItemListEntry item;
  final int index;

  const _ItemListRow({
    required this.item,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(listViewSelectionNotifierProvider);
    final isSelected = selection.selectedItem?.itemKref == item.itemKref;
    final colors = KumihoTheme.of(context);
    final kindAccent = _chipAccent(context, item.kindColor);
    final kindTextAccent = _chipTextAccent(context, item.kindColor);
    
    return GestureDetector(
      onTap: () {
        ref.read(listViewSelectionNotifierProvider.notifier).selectItem(item);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide date columns on narrow screens
          final showDates = constraints.maxWidth > 600;
          final showRevisions = constraints.maxWidth > 500;
          
          return Container(
            height: 44.0,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? KumihoTheme.primary.withValues(alpha: 0.2)
                  : (index.isEven ? colors.backgroundList : colors.background),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? KumihoTheme.primary : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Creative item icon badge
                _ItemIconBadge(item: item, isSelected: isSelected),
                const SizedBox(width: 12),
                // Item name
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            color: item.deprecated ? colors.textDimmed : colors.textPrimary,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                            decoration: item.deprecated ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.latestTags.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ...item.latestTags.take(2).map((tag) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: RevisionListEntry.getTagColor(tag),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(color: Colors.white, fontSize: 8),
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                // Kind
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kindAccent.withValues(alpha: _chipBgAlpha(context)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: kindAccent.withValues(alpha: _chipBorderAlpha(context))),
                        ),
                        child: Text(
                          item.kind,
                          style: TextStyle(
                            color: kindTextAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Author
                Expanded(
                  flex: 2,
                  child: Text(
                    item.username.isNotEmpty ? item.username : item.author,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Created date - hide on narrow screens
                if (showDates) ...[
                  SizedBox(
                    width: 100,
                    child: Text(
                      _formatDate(item.createdAt),
                      style: TextStyle(color: colors.textDimmed, fontSize: 11),
                    ),
                  ),
                  // Modified date
                  SizedBox(
                    width: 100,
                    child: Text(
                      _formatDate(item.modifiedAt),
                      style: TextStyle(color: colors.textDimmed, fontSize: 11),
                    ),
                  ),
                ],
                // Revision count - hide on narrow screens
                if (showRevisions)
                  SizedBox(
                    width: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.history, size: 12, color: colors.textDimmed),
                        const SizedBox(width: 4),
                        Text(
                          item.revisionCount < 0 ? '—' : '${item.revisionCount}',
                          style: TextStyle(color: colors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

// ==================== LIST HEADER ==================== //

class _ListHeader extends StatelessWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.backgroundList,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48), // Thumb column
          const SizedBox(width: 12),
          Expanded(flex: 3, child: _headerText(context, 'Name')),
          Expanded(flex: 2, child: _headerText(context, 'Revision / Tags')),
          Expanded(flex: 2, child: _headerText(context, 'Artifact')),
          Expanded(flex: 1, child: _headerText(context, 'Author')),
          SizedBox(width: 80, child: _headerText(context, 'Date')),
        ],
      ),
    );
  }

  Widget _headerText(BuildContext context, String text) {
    final colors = KumihoTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: colors.textDimmed,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ==================== LIST ITEM ==================== //

class _ListItem extends ConsumerWidget {
  final MediaItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final List<MediaItem> allItems;

  const _ListItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.allItems,
  });

  List<MediaItem> _getSelectedItems(WidgetRef ref) {
    final state = ref.read(browserProvider);
    return allItems.where((i) => state.selectedItemIds.contains(i.id)).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(browserProvider.select((s) => s.selectedItemIds));
    final isMultiSelected = selectedIds.contains(item.id);
    final selectedCount = selectedIds.length;
    final colors = KumihoTheme.of(context);
    
    return GestureDetector(
      onTap: () {
        // Check for Ctrl key for multi-select
        if (HardwareKeyboard.instance.isControlPressed) {
          ref.read(browserProvider.notifier).toggleItemSelection(item);
        } else {
          onTap();
        }
      },
      child: Draggable<List<MediaItem>>(
        data: selectedCount > 1 && isMultiSelected
            ? _getSelectedItems(ref)
            : [item],
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: item.thumbColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KumihoTheme.primary, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildThumbnailContent(),
              ),
              if (selectedCount > 1 && isMultiSelected)
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
                      '$selectedCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected || isMultiSelected
                ? KumihoTheme.primary.withValues(alpha: 0.2) 
                : colors.backgroundList,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected || isMultiSelected ? KumihoTheme.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.thumbColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Icon(
                    item.type == 'mp4' ? Icons.play_circle_outline : Icons.image,
                    color: colors.textMuted,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name
              Expanded(
                flex: 3,
                child: Text(
                  item.name,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Revision & Tags
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: KumihoTheme.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.revision,
                        style: TextStyle(color: colors.textSecondary, fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...item.tags.take(2).map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: KumihoTheme.getTagColor(tag),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(color: Colors.white, fontSize: 8),
                        ),
                      ),
                    )),
                  ],
                ),
              ),
              // Artifact name
              Expanded(
                flex: 2,
                child: Text(
                  item.artifactName,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Author
              Expanded(
                flex: 1,
                child: Text(
                  item.author,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Date
              SizedBox(
                width: 80,
                child: Text(
                  ClipContainer.formatDate(item.date),
                  style: TextStyle(color: colors.textDimmed, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (item.hasLocalThumbnail) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    } else if (item.hasHttpThumbnail) {
      return Image.network(
        item.thumbnailPath!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
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
}
