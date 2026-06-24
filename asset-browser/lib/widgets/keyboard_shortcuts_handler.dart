// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../providers/settings_provider.dart';
import 'settings_dialog.dart';

/// Global focus node for the search input, used by Ctrl+F shortcut
final searchFocusNodeProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'SearchInput');
  ref.onDispose(() => node.dispose());
  return node;
});

/// Widget that handles global keyboard shortcuts for the application.
/// Wraps the entire app content and intercepts keyboard events.
class KeyboardShortcutsHandler extends ConsumerWidget {
  final Widget child;

  const KeyboardShortcutsHandler({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    
    // If shortcuts are disabled, just return the child
    if (!settings.keyboardShortcutsEnabled) {
      return child;
    }

    return CallbackShortcuts(
      bindings: _buildShortcuts(context, ref),
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcuts(BuildContext context, WidgetRef ref) {
    final browserNotifier = ref.read(browserProvider.notifier);

    return {
      // Ctrl+G: Toggle View Mode (Grid/List)
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): () {
        final currentState = ref.read(browserProvider);
        browserNotifier.setGridView(!currentState.isGridView);
      },

      // Ctrl+Plus: Zoom In
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
        final currentState = ref.read(browserProvider);
        final newZoom = (currentState.gridZoom + 0.1).clamp(0.0, 1.0);
        browserNotifier.setGridZoom(newZoom);
      },
      // Ctrl+NumpadAdd: Zoom In (numpad)
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () {
        final currentState = ref.read(browserProvider);
        final newZoom = (currentState.gridZoom + 0.1).clamp(0.0, 1.0);
        browserNotifier.setGridZoom(newZoom);
      },

      // Ctrl+Minus: Zoom Out
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
        final currentState = ref.read(browserProvider);
        final newZoom = (currentState.gridZoom - 0.1).clamp(0.0, 1.0);
        browserNotifier.setGridZoom(newZoom);
      },
      // Ctrl+NumpadSubtract: Zoom Out (numpad)
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () {
        final currentState = ref.read(browserProvider);
        final newZoom = (currentState.gridZoom - 0.1).clamp(0.0, 1.0);
        browserNotifier.setGridZoom(newZoom);
      },

      // Ctrl+F: Focus Search Input
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
        ref.read(searchFocusNodeProvider).requestFocus();
      },

      // Ctrl+A: Select All Items in Grid
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
        _selectAllItems(ref);
      },

      // F5: Refresh
      const SingleActivator(LogicalKeyboardKey.f5): () {
        ref.read(kumihoRefreshTriggerProvider.notifier).state++;
      },

      // Ctrl+Comma: Open Settings
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        showSettingsDialog(context);
      },

      // Ctrl+B: Toggle Left Playlist Sidebar
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
        browserNotifier.togglePlaylistCollapsed();
      },

      // Ctrl+Shift+B: Toggle Bottom Playlist Area
      const SingleActivator(LogicalKeyboardKey.keyB, control: true, shift: true): () {
        browserNotifier.toggleShowPlaylistArea();
      },
    };
  }

  void _selectAllItems(WidgetRef ref) {
    final browserState = ref.read(browserProvider);
    final browserNotifier = ref.read(browserProvider.notifier);
    
    // Only work in grid view
    if (!browserState.isGridView) return;
    
    // Get current items from the provider
    final items = ref.read(kumihoMediaItemsProvider);
    if (items.isEmpty) return;

    // Select all item IDs
    final allIds = items.map((item) => item.id).toSet();
    browserNotifier.selectAllItems(allIds, items.first);
  }
}
