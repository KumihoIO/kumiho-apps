// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../core/perf/perf_logger.dart';
import '../services/asset_actions.dart';
import '../theme/kumiho_theme.dart';

const bool _disablePlaylistDnd =
  String.fromEnvironment('DISABLE_PLAYLIST_DND', defaultValue: '0') == '1';
const bool _forceEnablePlaylistDnd =
  String.fromEnvironment('FORCE_ENABLE_PLAYLIST_DND', defaultValue: '0') == '1';
const int _startupDisablePlaylistDndMs =
  int.fromEnvironment('STARTUP_DISABLE_PLAYLIST_DND_MS', defaultValue: 30000);

bool _isPlaylistDndDisabledNow() {
  if (_forceEnablePlaylistDnd) return false;
  if (_disablePlaylistDnd) return true;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
  if (_startupDisablePlaylistDndMs <= 0) return false;
  return PerfLogger.sinceStartMs() < _startupDisablePlaylistDndMs;
}

class _PlaylistColorSwatches extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelected;

  const _PlaylistColorSwatches({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: KumihoTheme.playlistSwatchColors.map((color) {
        final isSelected = color.toARGB32() == selected.toARGB32();
        return InkWell(
          onTap: () => onSelected(color),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? colors.textPrimary : colors.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Collapsible playlist sidebar (left column)
class PlaylistSidebar extends ConsumerWidget {
  const PlaylistSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);

    return AnimatedContainer(
      duration: KumihoTheme.animationFast,
      clipBehavior: Clip.hardEdge,
      width: state.isPlaylistCollapsed 
          ? KumihoTheme.sidebarCollapsedWidth 
          : KumihoTheme.sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: colors.backgroundSidebar,
        border: Border(
          right: BorderSide(color: colors.borderDark, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use actual width to determine what to show, not just state
          // This prevents overflow during animation
          final showExpanded = constraints.maxWidth > KumihoTheme.sidebarCollapsedWidth + 20;
          
          return Column(
            children: [
              // Header with collapse toggle
              _SidebarHeader(
                isCollapsed: state.isPlaylistCollapsed,
                onToggle: notifier.togglePlaylistCollapsed,
              ),
              // Playlist list - show based on actual available width
              Expanded(
                child: showExpanded
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: state.playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = state.playlists[index];
                          return PlaylistItem(
                            playlist: playlist,
                            isSelected: state.selectedPlaylist?.id == playlist.id,
                            onTap: () => notifier.selectPlaylist(playlist),
                            onContextMenu: (position) => _showPlaylistContextMenu(
                              context, ref, notifier, playlist, position,
                            ),
                            onDrop: (items) {
                              // Switch to this playlist and add items
                              notifier.selectPlaylist(playlist);
                              notifier.addMultipleToPlaylist(items);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added ${items.length} item(s) to ${playlist.name}'),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: playlist.color,
                                ),
                              );
                            },
                          );
                        },
                      )
                    : const _CollapsedLabel(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPlaylistContextMenu(
    BuildContext context,
    WidgetRef ref,
    BrowserNotifier notifier,
    Playlist playlist,
    Offset position,
  ) {
    final colors = KumihoTheme.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: colors.backgroundSidebar,
      items: [
        PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Rename', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save_kumiho',
          child: Row(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Save to Kumiho', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'rename') {
        _showRenameDialog(context, notifier, playlist);
      } else if (value == 'save_kumiho') {
        _savePlaylistToKumiho(context, ref, playlist);
      } else if (value == 'delete') {
        _confirmDeletePlaylist(context, notifier, playlist);
      }
    });
  }

  Future<void> _savePlaylistToKumiho(
      BuildContext context, WidgetRef ref, Playlist playlist) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final projectName = ref.read(selectedProjectNameProvider);
    if (projectName == null || projectName.isEmpty) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('Select a project first to save the playlist')));
      return;
    }
    if (playlist.items.isEmpty) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('Playlist is empty')));
      return;
    }
    messenger?.showSnackBar(SnackBar(
        content: Text('Saving "${playlist.name}" to Kumiho...'),
        duration: const Duration(seconds: 1)));
    try {
      final pinned =
          playlist.items.where((i) => (i.revisionKref ?? '').isNotEmpty).length;
      await AssetActions.savePlaylistToKumiho(ref, playlist, projectName);
      messenger?.showSnackBar(SnackBar(
          content: Text('Saved "${playlist.name}" to $projectName/playlists '
              '($pinned of ${playlist.items.length} items pinned)')));
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text('Failed to save playlist: $e')));
    }
  }

  void _showRenameDialog(BuildContext context, BrowserNotifier notifier, Playlist playlist) {
    final colors = KumihoTheme.of(context);
    final controller = TextEditingController(text: playlist.name);
    Color selectedColor = playlist.color;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.backgroundSidebar,
          title: Text('Edit Playlist', style: TextStyle(color: colors.textPrimary)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Playlist name',
                    hintStyle: TextStyle(color: colors.textDimmed),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colors.borderLight),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: KumihoTheme.primary),
                    ),
                  ),
                  onSubmitted: (_) {
                    final newName = controller.text.trim();
                    if (newName.isEmpty) return;
                    notifier.updatePlaylist(
                      playlist.id,
                      name: newName,
                      color: selectedColor,
                    );
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 12),
                Text('Label color', style: TextStyle(color: colors.textDimmed, fontSize: 11)),
                const SizedBox(height: 8),
                _PlaylistColorSwatches(
                  selected: selectedColor,
                  onSelected: (color) => setState(() => selectedColor = color),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isEmpty) return;
                notifier.updatePlaylist(
                  playlist.id,
                  name: newName,
                  color: selectedColor,
                );
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePlaylist(BuildContext context, BrowserNotifier notifier, Playlist playlist) {
    final colors = KumihoTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.backgroundSidebar,
        title: Text('Delete Playlist', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?\nThis action cannot be undone.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notifier.deletePlaylist(playlist.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted "${playlist.name}"'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ==================== SIDEBAR HEADER ==================== //

class _SidebarHeader extends ConsumerWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _SidebarHeader({
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final notifier = ref.read(browserProvider.notifier);
    
    return InkWell(
      onTap: onToggle,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: colors.backgroundHeader,
          border: Border(
            bottom: BorderSide(color: colors.borderDark, width: 1),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use actual width to determine layout, not just isCollapsed state
            final showExpanded = constraints.maxWidth > KumihoTheme.sidebarCollapsedWidth + 20;
            
            if (!showExpanded) {
              return Center(
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textMuted,
                ),
              );
            }
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.chevron_left,
                    size: 18,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PLAYLISTS',
                      style: TextStyle(
                        color: colors.textDimmed,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, size: 16, color: colors.textMuted),
                    onPressed: () => _showCreatePlaylistDialog(context, notifier),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24),
                    tooltip: 'Add Playlist',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, BrowserNotifier notifier) {
    final colors = KumihoTheme.of(context);
    final controller = TextEditingController(text: 'New Playlist');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);

    Color selectedColor = KumihoTheme.playlistSwatchColors.first;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.backgroundSidebar,
          title: Text('Create Playlist', style: TextStyle(color: colors.textPrimary)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Playlist name',
                    hintStyle: TextStyle(color: colors.textDimmed),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colors.borderLight),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: KumihoTheme.primary),
                    ),
                  ),
                  onSubmitted: (_) {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    notifier.createPlaylist(name, color: selectedColor);
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 12),
                Text('Label color', style: TextStyle(color: colors.textDimmed, fontSize: 11)),
                const SizedBox(height: 8),
                _PlaylistColorSwatches(
                  selected: selectedColor,
                  onSelected: (color) => setState(() => selectedColor = color),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                notifier.createPlaylist(name, color: selectedColor);
                Navigator.of(context).pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== COLLAPSED LABEL ==================== //

class _CollapsedLabel extends StatelessWidget {
  const _CollapsedLabel();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Center(
      child: RotatedBox(
        quarterTurns: -1,
        child: Text(
          'PLAYLISTS',
          style: TextStyle(
            color: colors.textVeryDimmed,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

// ==================== PLAYLIST ITEM ==================== //

class PlaylistItem extends ConsumerWidget {
  final Playlist playlist;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
  final ValueChanged<List<MediaItem>> onDrop;

  const PlaylistItem({
    super.key,
    required this.playlist,
    required this.isSelected,
    required this.onTap,
    this.onContextMenu,
    required this.onDrop,
  });

  static int _lastDndDisabledLogMs = -1000000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);

    final dndDisabled = _isPlaylistDndDisabledNow();
    if (dndDisabled && PerfLogger.enabled) {
      final now = PerfLogger.sinceStartMs();
      if (now - _lastDndDisabledLogMs >= 2000) {
        _lastDndDisabledLogMs = now;
        PerfLogger.log('PlaylistItem: DND disabled during startup');
      }
    }
    
    Widget buildTile({required bool isHovering, required int itemCount}) {
      return GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (details) => onContextMenu?.call(details.globalPosition),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHovering
                ? playlist.color.withValues(alpha: 0.3)
                : (isSelected ? KumihoTheme.primary.withValues(alpha: 0.15) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: isHovering
                ? Border.all(color: playlist.color, width: 2)
                : (isSelected
                    ? Border.all(color: KumihoTheme.primary.withValues(alpha: 0.5), width: 1)
                    : null),
          ),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: playlist.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: TextStyle(
                        color: isSelected ? colors.textPrimary : colors.textSecondary,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isHovering
                          ? '+$itemCount item${itemCount > 1 ? 's' : ''}'
                          : '${playlist.items.length} items',
                      style: TextStyle(
                        color: isHovering ? playlist.color : colors.textDimmed,
                        fontSize: 10,
                        fontWeight: isHovering ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (dndDisabled) {
      return buildTile(isHovering: false, itemCount: 0);
    }

    return DragTarget<List<MediaItem>>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final itemCount = isHovering ? candidateData.first?.length ?? 0 : 0;
        return buildTile(isHovering: isHovering, itemCount: itemCount);
      },
    );
  }
}
