// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/playlist_service.dart';
import 'settings_provider.dart';

/// Tracks which UI area the user is actively working in
enum BrowserContext { grid, playlist }

/// True while the fullscreen viewer is open (Space “playback mode”).
///
/// Used to pause expensive background expansion work so user interactions and
/// rendering stay responsive.
final playbackModeActiveProvider = StateProvider<bool>((ref) => false);

// ==================== BROWSER STATE ==================== //

/// Holds the current state of the browser UI
class BrowserState {
  final bool isPlaylistCollapsed;
  final bool isGridView;
  final double gridZoom;
  final double playlistZoom;
  final double detailPanelWidth;
  final double playlistHeight;
  final String? selectedProject;
  final String? selectedSpace;
  final String? selectedSubSpace;
  final String searchQuery;
  final MediaItem? selectedItem;
  final Set<String> selectedItemIds;  // Multi-select support
  final Playlist? selectedPlaylist;
  final List<Playlist> playlists;  // All playlists
  final List<MediaItem> playlistItems;
  final List<MediaItem> mediaItems;
  // Track playlist state before list view for restoration
  final bool playlistCollapsedBeforeListView;
  final bool showPlaylistArea;  // Controls bottom playlist visibility
  final BrowserContext activeContext;  // Which area user is working in

  const BrowserState({
    this.isPlaylistCollapsed = false,
    this.isGridView = true,
    this.gridZoom = 0.5,
    this.playlistZoom = 0.5,
    this.detailPanelWidth = 500.0,
    this.playlistHeight = 140.0,
    this.selectedProject,
    this.selectedSpace,
    this.selectedSubSpace,
    this.searchQuery = '',
    this.selectedItem,
    this.selectedItemIds = const {},
    this.selectedPlaylist,
    this.playlists = const [],
    this.playlistItems = const [],
    this.mediaItems = const [],
    this.playlistCollapsedBeforeListView = false,
    this.showPlaylistArea = true,
    this.activeContext = BrowserContext.grid,
  });

  BrowserState copyWith({
    bool? isPlaylistCollapsed,
    bool? isGridView,
    double? gridZoom,
    double? playlistZoom,
    double? detailPanelWidth,
    double? playlistHeight,
    String? selectedProject,
    String? selectedSpace,
    String? selectedSubSpace,
    String? searchQuery,
    MediaItem? selectedItem,
    Set<String>? selectedItemIds,
    Playlist? selectedPlaylist,
    List<Playlist>? playlists,
    List<MediaItem>? playlistItems,
    List<MediaItem>? mediaItems,
    bool clearSelectedItem = false,
    bool clearSelectedSpace = false,
    bool clearSelectedSubSpace = false,
    bool? playlistCollapsedBeforeListView,
    bool? showPlaylistArea,
    BrowserContext? activeContext,
  }) {
    return BrowserState(
      isPlaylistCollapsed: isPlaylistCollapsed ?? this.isPlaylistCollapsed,
      isGridView: isGridView ?? this.isGridView,
      gridZoom: gridZoom ?? this.gridZoom,
      playlistZoom: playlistZoom ?? this.playlistZoom,
      detailPanelWidth: detailPanelWidth ?? this.detailPanelWidth,
      playlistHeight: playlistHeight ?? this.playlistHeight,
      selectedProject: selectedProject ?? this.selectedProject,
      selectedSpace: clearSelectedSpace ? null : (selectedSpace ?? this.selectedSpace),
      selectedSubSpace: clearSelectedSubSpace ? null : (selectedSubSpace ?? this.selectedSubSpace),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedItem: clearSelectedItem ? null : (selectedItem ?? this.selectedItem),
      selectedItemIds: selectedItemIds ?? this.selectedItemIds,
      selectedPlaylist: selectedPlaylist ?? this.selectedPlaylist,
      playlists: playlists ?? this.playlists,
      playlistItems: playlistItems ?? this.playlistItems,
      mediaItems: mediaItems ?? this.mediaItems,
      playlistCollapsedBeforeListView: playlistCollapsedBeforeListView ?? this.playlistCollapsedBeforeListView,
      showPlaylistArea: showPlaylistArea ?? this.showPlaylistArea,
      activeContext: activeContext ?? this.activeContext,
    );
  }
}

// ==================== BROWSER NOTIFIER ==================== //

class BrowserNotifier extends StateNotifier<BrowserState> {
  BrowserNotifier({bool defaultToListView = false}) 
      : super(BrowserState(isGridView: !defaultToListView)) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Load playlists from disk (user's saved playlists persist regardless of auth state)
    final savedPlaylists = await PlaylistService.loadPlaylists();
    
    // Use saved playlists only - no mock playlists
    final playlists = savedPlaylists;
    
    // Use items from the first playlist if available
    final firstPlaylist = playlists.isNotEmpty ? playlists.first : null;
    final playlistItems = firstPlaylist?.items ?? [];
    
    state = state.copyWith(
      mediaItems: [],  // No mock items - real items come from Kumiho API
      playlists: playlists,
      playlistItems: playlistItems,
      selectedPlaylist: firstPlaylist,
      // No default project/space - user selects after signing in
    );
  }

  /// Save current playlist to disk (call after modifications)
  Future<void> _saveCurrentPlaylist() async {
    final playlist = state.selectedPlaylist;
    if (playlist == null) return;
    
    // Update the playlist with current items
    final updatedPlaylist = playlist.copyWith(
      items: state.playlistItems,
      itemCount: state.playlistItems.length,
      updatedAt: DateTime.now(),
    );
    
    // Update in state
    final updatedPlaylists = state.playlists.map((p) {
      return p.id == updatedPlaylist.id ? updatedPlaylist : p;
    }).toList();
    
    state = state.copyWith(
      selectedPlaylist: updatedPlaylist,
      playlists: updatedPlaylists,
    );
    
    // Save to disk
    await PlaylistService.savePlaylists(updatedPlaylists);
  }

  // Layout actions
  void togglePlaylistCollapsed() {
    state = state.copyWith(isPlaylistCollapsed: !state.isPlaylistCollapsed);
  }

  void setGridView(bool isGrid) {
    if (!isGrid && state.isGridView) {
      // Switching TO list view - auto-collapse playlist panels
      state = state.copyWith(
        isGridView: false,
        // Store current collapsed state for restoration
        playlistCollapsedBeforeListView: state.isPlaylistCollapsed,
        // Collapse sidebar and hide bottom playlist area
        isPlaylistCollapsed: true,
        showPlaylistArea: false,
      );
    } else if (isGrid && !state.isGridView) {
      // Switching TO grid view - restore playlist state
      state = state.copyWith(
        isGridView: true,
        // Restore previous collapsed state
        isPlaylistCollapsed: state.playlistCollapsedBeforeListView,
        showPlaylistArea: true,
      );
    }
  }

  void setGridZoom(double zoom) {
    state = state.copyWith(gridZoom: zoom.clamp(0.0, 1.0));
  }

  void setPlaylistZoom(double zoom) {
    state = state.copyWith(playlistZoom: zoom.clamp(0.0, 1.0));
  }

  void setDetailPanelWidth(double width) {
    state = state.copyWith(detailPanelWidth: width.clamp(280.0, 500.0));
  }

  /// Set the active context (grid or playlist) for Space key behavior
  void setActiveContext(BrowserContext context) {
    state = state.copyWith(activeContext: context);
  }

  void setPlaylistHeight(double height) {
    // Minimum height should accommodate header (28px) + at least one clip row with padding
    final clamped = height.clamp(100.0, 400.0);
    // Snap to small increments so resizing doesn't rebuild everything for every
    // tiny pointer delta (which can be very frequent on desktop).
    const step = 4.0;
    final snapped = (clamped / step).round() * step;
    if (snapped == state.playlistHeight) return;
    state = state.copyWith(playlistHeight: snapped);
  }

  /// Toggle the bottom playlist area visibility
  void toggleShowPlaylistArea() {
    state = state.copyWith(showPlaylistArea: !state.showPlaylistArea);
  }

  // Selection actions
  void selectProject(String? project) {
    // Clear space selection when changing projects - actual spaces come from Kumiho API
    state = state.copyWith(
      selectedProject: project,
      clearSelectedSpace: true,
      clearSelectedSubSpace: true,
    );
  }

  void selectSpace(String? space) {
    state = state.copyWith(
      selectedSpace: space,
      clearSelectedSubSpace: true,
    );
  }

  void selectSubSpace(String? subSpace) {
    state = state.copyWith(selectedSubSpace: subSpace);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void selectItem(MediaItem? item) {
    // Single select - clear multi-selection
    state = state.copyWith(
      selectedItem: item,
      selectedItemIds: item != null ? {item.id} : {},
    );
  }

  /// Toggle selection of an item (for Ctrl+click multi-select)
  void toggleItemSelection(MediaItem item) {
    final newSelection = Set<String>.from(state.selectedItemIds);
    if (newSelection.contains(item.id)) {
      newSelection.remove(item.id);
    } else {
      newSelection.add(item.id);
    }
    // Always update selectedItem to the last clicked item for details view
    state = state.copyWith(
      selectedItem: item,
      selectedItemIds: newSelection,
    );
  }

  /// Clear all selection
  void clearSelection() {
    state = state.copyWith(
      selectedItemIds: {},
      clearSelectedItem: true,
    );
  }

  /// Select all items (for Ctrl+A)
  void selectAllItems(Set<String> ids, MediaItem? firstItem) {
    state = state.copyWith(
      selectedItemIds: ids,
      selectedItem: firstItem,
    );
  }

  void selectPlaylist(Playlist? playlist) {
    if (playlist?.id == state.selectedPlaylist?.id) return; // Same playlist, no-op
    
    // Save current playlist items before switching
    _saveCurrentPlaylist();
    
    // Load items from new playlist (use its stored items)
    final items = playlist?.items ?? [];
    state = state.copyWith(
      selectedPlaylist: playlist,
      playlistItems: List<MediaItem>.from(items),
    );
  }

  /// Create a new playlist
  Future<Playlist> createPlaylist(String name, {Color? color}) async {
    final newPlaylist = PlaylistService.createNewPlaylist(
      name: name,
      color: color,
    );
    
    final updatedPlaylists = [...state.playlists, newPlaylist];
    state = state.copyWith(playlists: updatedPlaylists);
    
    await PlaylistService.savePlaylists(updatedPlaylists);
    return newPlaylist;
  }

  /// Rename a playlist
  Future<void> renamePlaylist(String playlistId, String newName) async {
    await updatePlaylist(playlistId, name: newName);
  }

  /// Update playlist metadata (name/color).
  Future<void> updatePlaylist(
    String playlistId, {
    String? name,
    Color? color,
  }) async {
    final updatedPlaylists = state.playlists.map((p) {
      if (p.id != playlistId) return p;
      return p.copyWith(
        name: name ?? p.name,
        color: color ?? p.color,
        updatedAt: DateTime.now(),
      );
    }).toList();

    // Update selectedPlaylist if it's the one being changed
    Playlist? updatedSelected = state.selectedPlaylist;
    if (state.selectedPlaylist?.id == playlistId) {
      updatedSelected = updatedPlaylists.firstWhere((p) => p.id == playlistId);
    }

    state = state.copyWith(
      playlists: updatedPlaylists,
      selectedPlaylist: updatedSelected,
    );

    await PlaylistService.savePlaylists(updatedPlaylists);
  }

  /// Delete a playlist
  Future<void> deletePlaylist(String playlistId) async {
    final updatedPlaylists = state.playlists.where((p) => p.id != playlistId).toList();
    
    // If we're deleting the current playlist, switch to another
    Playlist? newSelected = state.selectedPlaylist;
    List<MediaItem> newItems = state.playlistItems;
    
    if (state.selectedPlaylist?.id == playlistId) {
      newSelected = updatedPlaylists.isNotEmpty ? updatedPlaylists.first : null;
      newItems = newSelected?.items ?? [];
    }
    
    state = state.copyWith(
      playlists: updatedPlaylists,
      selectedPlaylist: newSelected,
      playlistItems: newItems,
    );
    
    await PlaylistService.deletePlaylist(playlistId);
  }

  // Playlist actions
  void addToPlaylist(MediaItem item) {
    if (!state.playlistItems.any((e) => e.id == item.id)) {
      state = state.copyWith(
        playlistItems: [...state.playlistItems, item],
      );
      _saveCurrentPlaylist();
    }
  }

  /// Add multiple items to playlist
  void addMultipleToPlaylist(List<MediaItem> items) {
    final existingIds = state.playlistItems.map((e) => e.id).toSet();
    final newItems = items.where((item) => !existingIds.contains(item.id)).toList();
    if (newItems.isNotEmpty) {
      state = state.copyWith(
        playlistItems: [...state.playlistItems, ...newItems],
      );
      _saveCurrentPlaylist();
    }
  }

  void removeFromPlaylist(int index) {
    final newList = List<MediaItem>.from(state.playlistItems);
    newList.removeAt(index);
    state = state.copyWith(playlistItems: newList);
    _saveCurrentPlaylist();
  }

  void reorderPlaylist(int fromIndex, int toIndex) {
    final newList = List<MediaItem>.from(state.playlistItems);
    final item = newList.removeAt(fromIndex);
    final adjustedIndex = fromIndex < toIndex ? toIndex - 1 : toIndex;
    newList.insert(adjustedIndex.clamp(0, newList.length), item);
    state = state.copyWith(playlistItems: newList);
    _saveCurrentPlaylist();
  }
}

// ==================== PROVIDERS ==================== //

final browserProvider = StateNotifierProvider<BrowserNotifier, BrowserState>((ref) {
  // Read initial settings for default view mode
  final defaultToListView = ref.read(defaultToListViewProvider);
  return BrowserNotifier(defaultToListView: defaultToListView);
});

// Convenience providers for specific state slices
final selectedItemProvider = Provider<MediaItem?>((ref) {
  return ref.watch(browserProvider).selectedItem;
});

final selectedPlaylistProvider = Provider<Playlist?>((ref) {
  return ref.watch(browserProvider).selectedPlaylist;
});

final playlistItemsProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(browserProvider).playlistItems;
});

final mediaItemsProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(browserProvider).mediaItems;
});

final isGridViewProvider = Provider<bool>((ref) {
  return ref.watch(browserProvider).isGridView;
});
