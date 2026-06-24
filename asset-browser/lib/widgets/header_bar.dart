// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumiho/kumiho.dart';
import '../providers/auth_provider.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/kumiho_theme.dart';
import 'settings_dialog.dart';
import 'safe_network_image.dart';

/// Top header bar with logo, project/space dropdowns, view toggle, zoom, settings, user
class HeaderBar extends ConsumerWidget {
  const HeaderBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    // Avoid rebuilding the entire header (and especially dropdown item lists)
    // on unrelated state changes like selection, playlist state, etc.
    final isGridView = ref.watch(browserProvider.select((s) => s.isGridView));
    final gridZoom = ref.watch(browserProvider.select((s) => s.gridZoom));
    final notifier = ref.read(browserProvider.notifier);
    final canBrowse = ref.watch(canBrowseProvider);

    return Container(
      constraints: BoxConstraints(
        minHeight: KumihoTheme.headerHeight,
        maxHeight: KumihoTheme.headerHeight + 36, // Allow extra height for wrapped dropdowns
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate available width to determine which elements to show
          final availableWidth = constraints.maxWidth;
          final showZoomSlider = availableWidth > 900;
          final showRefreshButton = availableWidth > 700;
          // Calculate max dropdowns based on available space
          final maxDropdowns = availableWidth > 1000 ? 4 : (availableWidth > 800 ? 3 : 2);
          
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              const _Logo(),
              const SizedBox(width: 24),
              // Project/Space dropdowns - use real data if authenticated
              // Use Expanded with SingleChildScrollView to handle overflow
              Expanded(
                child: canBrowse
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _ProjectDropdown(),
                            const SizedBox(width: 12),
                            _CascadingSpaceDropdowns(maxDropdowns: maxDropdowns),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.borderDark),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: colors.textDimmed),
                            const SizedBox(width: 8),
                            Text(
                              'Sign in or set Tenant ID to browse',
                              style: TextStyle(color: colors.textDimmed, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              // Refresh button - hide on narrow screens
              if (showRefreshButton) ...[
                const _RefreshButton(),
                const SizedBox(width: 8),
              ],
              // Delete actions (revisions in grid view, items in list view)
              const _RestoreSelectionButton(),
              const SizedBox(width: 8),
              const _DeleteSelectionButton(),
              const SizedBox(width: 8),
              // View toggle
              _ViewToggle(
                isGridView: isGridView,
                onToggle: notifier.setGridView,
              ),
              // Zoom slider - hide on narrow screens
              if (showZoomSlider) ...[
                const SizedBox(width: 16),
                _ZoomSlider(
                  value: gridZoom,
                  onChanged: notifier.setGridZoom,
                ),
              ],
              const SizedBox(width: 16),
              // Settings
              IconButton(
                icon: Icon(Icons.settings_outlined, size: 20, color: colors.textMuted),
                onPressed: () => showSettingsDialog(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
                tooltip: 'Settings',
              ),
              const SizedBox(width: 8),
              // User account button
              const _UserAccountButton(),
            ],
          );
        },
      ),
    );
  }
}

// ==================== DELETE SELECTED ==================== //

class _DeleteSelectionButton extends ConsumerWidget {
  const _DeleteSelectionButton();

  Future<void> _deleteRevisionCompat(KumihoClient client, String kref, {bool force = false}) async {
    try {
      await Function.apply(client.deleteRevision, [kref], {#force: force});
    } catch (_) {
      await Function.apply(client.deleteRevision, [kref]);
    }
  }

  Future<void> _deleteItemCompat(KumihoClient client, String kref, {bool force = false}) async {
    try {
      await Function.apply(client.deleteItem, [kref], {#force: force});
    } catch (_) {
      await Function.apply(client.deleteItem, [kref]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browserState = ref.watch(browserProvider);
    final colors = KumihoTheme.of(context);

    // Grid view: delete selected revisions
    if (browserState.isGridView) {
      final selectedIds = browserState.selectedItemIds;
      if (selectedIds.isEmpty) return const SizedBox.shrink();

      final items = ref.watch(kumihoMediaItemsProvider);
      final selectedItems = items.where((i) => selectedIds.contains(i.id)).toList();
      final revisionKrefs = selectedItems.map((i) => i.revisionKref).whereType<String>().toList();
      final canDelete = revisionKrefs.isNotEmpty;

      return IconButton(
        icon: Icon(Icons.delete_outline, size: 20, color: canDelete ? Colors.redAccent : colors.textMuted),
        tooltip: canDelete
            ? 'Deprecate ${revisionKrefs.length} revision${revisionKrefs.length == 1 ? '' : 's'}'
            : 'No revisions selected',
        onPressed: canDelete ? () => _confirmDeleteRevisions(context, ref, revisionKrefs) : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36),
      );
    }

    // List view: delete selected item
    final selection = ref.watch(listViewSelectionNotifierProvider);
    final item = selection.selectedItem;
    if (item == null) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
      tooltip: 'Deprecate item',
      onPressed: () => _confirmDeleteItem(context, ref, item.itemKref, item.name),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36),
    );
  }

  Future<void> _confirmDeleteRevisions(BuildContext context, WidgetRef ref, List<String> revisionKrefs) async {
    final colors = KumihoTheme.of(context);
    var hardDelete = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: colors.backgroundCard,
          title: Text('Remove revisions', style: TextStyle(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default action: deprecate ${revisionKrefs.length} selected revision${revisionKrefs.length == 1 ? '' : 's'} (hidden from searches).',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: hardDelete,
                onChanged: (v) => setState(() => hardDelete = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: const Text('Hard delete (permanent)', style: TextStyle(color: Colors.redAccent)),
                subtitle: Text(
                  'Permanently deletes the selected revisions.',
                  style: TextStyle(color: colors.textSecondary),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                hardDelete ? 'Delete' : 'Deprecate',
                style: TextStyle(color: hardDelete ? Colors.redAccent : colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final client = await ref.read(kumihoClientProvider.future);
      if (client == null) throw Exception('Client unavailable');

      for (final kref in revisionKrefs) {
        if (hardDelete) {
          await _deleteRevisionCompat(client, kref, force: true);
        } else {
          await client.setDeprecated(kref, true);
        }
      }

      // Clear selection and refresh
      ref.read(browserProvider.notifier).clearSelection();
      ref.read(kumihoRefreshTriggerProvider.notifier).state++;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hardDelete
                  ? 'Deleted ${revisionKrefs.length} revision${revisionKrefs.length == 1 ? '' : 's'}'
                  : 'Deprecated ${revisionKrefs.length} revision${revisionKrefs.length == 1 ? '' : 's'}',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteItem(BuildContext context, WidgetRef ref, String itemKref, String name) async {
    final colors = KumihoTheme.of(context);
    var hardDelete = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: colors.backgroundCard,
          title: Text('Remove item', style: TextStyle(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default action: deprecate "$name" (hidden from searches).',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: hardDelete,
                onChanged: (v) => setState(() => hardDelete = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: const Text('Hard delete (permanent)', style: TextStyle(color: Colors.redAccent)),
                subtitle: Text(
                  'Permanently deletes the item and all revisions/artifacts.',
                  style: TextStyle(color: colors.textSecondary),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                hardDelete ? 'Delete' : 'Deprecate',
                style: TextStyle(color: hardDelete ? Colors.redAccent : colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final client = await ref.read(kumihoClientProvider.future);
      if (client == null) throw Exception('Client unavailable');

      if (hardDelete) {
        await _deleteItemCompat(client, itemKref, force: true);
      } else {
        await client.setDeprecated(itemKref, true);
      }

      // Clear selection and refresh
      ref.read(listViewSelectionNotifierProvider.notifier).clearAll();
      ref.read(kumihoRefreshTriggerProvider.notifier).state++;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hardDelete ? 'Deleted "$name"' : 'Deprecated "$name"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete item: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

// ==================== RESTORE SELECTED (UN-DEPRECATE) ==================== //

class _RestoreSelectionButton extends ConsumerWidget {
  const _RestoreSelectionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final includeDeprecated = ref.watch(includeDeprecatedProvider);
    if (!includeDeprecated) return const SizedBox.shrink();

    final browserState = ref.watch(browserProvider);
    final colors = KumihoTheme.of(context);

    if (browserState.isGridView) {
      final selectedIds = browserState.selectedItemIds;
      if (selectedIds.isEmpty) return const SizedBox.shrink();

      final items = ref.watch(kumihoMediaItemsProvider);
      final selectedItems = items.where((i) => selectedIds.contains(i.id)).toList();
      final restoreKrefs = selectedItems
          .where((i) => i.deprecated)
          .map((i) => i.revisionKref)
          .whereType<String>()
          .toList();
      final canRestore = restoreKrefs.isNotEmpty;

      return IconButton(
        icon: Icon(
          Icons.restore_from_trash_outlined,
          size: 20,
          color: canRestore ? colors.textPrimary : colors.textMuted,
        ),
        tooltip: canRestore
            ? 'Restore ${restoreKrefs.length} deprecated revision${restoreKrefs.length == 1 ? '' : 's'}'
            : 'No deprecated revisions selected',
        onPressed: canRestore ? () => _confirmRestoreRevisions(context, ref, restoreKrefs) : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36),
      );
    }

    // List view: restore selected item if deprecated
    final selection = ref.watch(listViewSelectionNotifierProvider);
    final item = selection.selectedItem;
    if (item == null || !item.deprecated) return const SizedBox.shrink();

    return IconButton(
      icon: Icon(Icons.restore_from_trash_outlined, size: 20, color: colors.textPrimary),
      tooltip: 'Restore item',
      onPressed: () => _confirmRestoreItem(context, ref, item.itemKref, item.name),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36),
    );
  }

  Future<void> _confirmRestoreRevisions(BuildContext context, WidgetRef ref, List<String> revisionKrefs) async {
    final colors = KumihoTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.backgroundCard,
        title: Text('Restore revisions', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Restore ${revisionKrefs.length} deprecated revision${revisionKrefs.length == 1 ? '' : 's'}?\nThey will appear in searches again.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Restore', style: TextStyle(color: colors.textPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = await ref.read(kumihoClientProvider.future);
      if (client == null) throw Exception('Client unavailable');

      for (final kref in revisionKrefs) {
        await client.setDeprecated(kref, false);
      }

      ref.read(browserProvider.notifier).clearSelection();
      ref.read(kumihoRefreshTriggerProvider.notifier).state++;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored ${revisionKrefs.length} revision${revisionKrefs.length == 1 ? '' : 's'}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _confirmRestoreItem(BuildContext context, WidgetRef ref, String itemKref, String name) async {
    final colors = KumihoTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.backgroundCard,
        title: Text('Restore item', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Restore "$name"? It will appear in searches again.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Restore', style: TextStyle(color: colors.textPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = await ref.read(kumihoClientProvider.future);
      if (client == null) throw Exception('Client unavailable');

      await client.setDeprecated(itemKref, false);

      ref.read(listViewSelectionNotifierProvider.notifier).clearAll();
      ref.read(kumihoRefreshTriggerProvider.notifier).state++;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored "$name"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore item: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

// ==================== PROJECT DROPDOWN (REAL DATA) ==================== //

class _ProjectDropdown extends ConsumerWidget {
  const _ProjectDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectNamesProvider);
    final selectedProject = ref.watch(selectedProjectNameProvider);
    final cachedNames = ref.watch(projectNamesMemoryCacheProvider);

    return projectsAsync.when(
      data: (projectNames) {
        if (projectNames.isEmpty) {
          return _HeaderDropdown(
            value: null,
            items: const [],
            onChanged: (_) {},
            hint: 'No projects',
          );
        }
        return _HeaderDropdown(
          value: selectedProject,
          items: projectNames,
          onChanged: (name) {
            ref.read(selectedProjectNameProvider.notifier).state = name;
            // Clear space path when project changes
            ref.read(selectedSpacePathProvider.notifier).state = [];
            ref.read(selectedSpaceNameProvider.notifier).state = null;
            
            // Trigger load for project items
            ref.read(pagedItemsProvider.notifier).loadFirstPage();
          },
          hint: 'Select project',
        );
      },
      loading: () => _HeaderDropdown(
        // If this is a refresh/reload, keep showing the last project list so
        // opening the dropdown stays responsive.
        value: selectedProject,
        items: projectsAsync.valueOrNull ?? cachedNames,
        onChanged: (name) {
          if (name == null) return;
          ref.read(selectedProjectNameProvider.notifier).state = name;
          // Clear space path when project changes
          ref.read(selectedSpacePathProvider.notifier).state = [];
          ref.read(selectedSpaceNameProvider.notifier).state = null;

          // Trigger load for project items
          ref.read(pagedItemsProvider.notifier).loadFirstPage();
        },
        hint: (projectsAsync.valueOrNull?.isNotEmpty ?? false) ? 'Select project' : 'Loading...',
        isLoading: projectsAsync.valueOrNull == null,
      ),
      error: (e, _) => _HeaderDropdown(
        value: null,
        items: const [],
        onChanged: (_) {},
        hint: 'Error loading',
      ),
    );
  }
}

// ==================== CASCADING SPACE DROPDOWNS ==================== //

/// Widget that displays cascading space dropdowns
/// Shows one dropdown for each level of the space hierarchy
/// Limited by maxDropdowns to prevent overflow on narrow screens
class _CascadingSpaceDropdowns extends ConsumerStatefulWidget {
  final int maxDropdowns;
  
  const _CascadingSpaceDropdowns({this.maxDropdowns = 4});

  @override
  ConsumerState<_CascadingSpaceDropdowns> createState() => _CascadingSpaceDropdownsState();
}

class _CascadingSpaceDropdownsState extends ConsumerState<_CascadingSpaceDropdowns> {
  @override
  Widget build(BuildContext context) {
    final selectedProject = ref.watch(selectedProjectNameProvider);
    if (selectedProject == null) {
      return const SizedBox.shrink();
    }

    final spacePath = ref.watch(selectedSpacePathProvider);
    final colors = KumihoTheme.of(context);
    
    // Build list of dropdowns: one for root + one for each level in path
    // We show depth 0 always, then depth 1..N based on path length
    final dropdowns = <Widget>[];
    
    // Root level dropdown (depth 0) - always shown
    dropdowns.add(_SpaceDropdownAtDepth(key: const ValueKey('depth_0'), depth: 0));
    
    // Additional dropdowns for each selected level in the path
    // Each dropdown shows children of the selected space at that level
    // But limit to maxDropdowns - 1 (since root is always shown)
    final maxAdditional = widget.maxDropdowns - 1;
    final pathToShow = spacePath.length > maxAdditional 
        ? spacePath.sublist(spacePath.length - maxAdditional)
        : spacePath;
    final startDepth = spacePath.length > maxAdditional 
        ? spacePath.length - maxAdditional 
        : 0;
    
    // Show ellipsis if we're hiding some path levels
    if (spacePath.length > maxAdditional) {
      dropdowns.add(const SizedBox(width: 8));
      dropdowns.add(Tooltip(
        message: spacePath.sublist(0, startDepth).join(' / '),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: colors.backgroundCard,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '...',
            style: TextStyle(color: colors.textDimmed, fontSize: 12),
          ),
        ),
      ));
    }
    
    for (int i = 0; i < pathToShow.length; i++) {
      dropdowns.add(const SizedBox(width: 12));
      final actualDepth = startDepth + i + 1;
      dropdowns.add(_SpaceDropdownAtDepth(
        key: ValueKey('depth_${actualDepth}_${spacePath.sublist(0, actualDepth).join('_')}'),
        depth: actualDepth,
      ));
    }
    
    // Return a simple Row since parent handles scrolling
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: dropdowns,
    );
  }
}

/// Dropdown for spaces at a specific depth
class _SpaceDropdownAtDepth extends ConsumerWidget {
  final int depth;
  
  const _SpaceDropdownAtDepth({super.key, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(childSpacesAtDepthProvider(depth));
    final spacePath = ref.watch(selectedSpacePathProvider);
    
    // Get the selected value at this depth (if any)
    final selectedValue = spacePath.length > depth ? spacePath[depth] : null;
    
    return spacesAsync.when(
      data: (spaces) {
        if (spaces.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final spaceNames = spaces.map((s) => s.name).toList();
        
        return _HeaderDropdown(
          value: selectedValue,
          items: spaceNames,
          onChanged: (name) {
            if (name == null) return;
            
            // Update the path: keep everything up to this depth, then add new selection
            final newPath = <String>[];
            
            // Keep path segments before this depth
            for (int i = 0; i < depth && i < spacePath.length; i++) {
              newPath.add(spacePath[i]);
            }
            
            // Add the new selection at this depth
            newPath.add(name);
            
            // Update state
            ref.read(selectedSpacePathProvider.notifier).state = newPath;
          },
          hint: depth == 0 ? 'Select space' : 'Sub-folder',
        );
      },
      loading: () => _HeaderDropdown(
        value: null,
        items: const [],
        onChanged: (_) {},
        hint: 'Loading...',
        isLoading: true,
      ),
      error: (e, _) {
        debugPrint('Error loading spaces at depth $depth: $e');
        return const SizedBox.shrink();
      },
    );
  }
}

// ==================== HELPER FUNCTIONS ==================== //

/// Check if URL is a valid HTTP/HTTPS image URL
bool _isValidImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  try {
    final uri = Uri.parse(url);
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  } catch (_) {
    return false;
  }
}

/// Get the first character for user avatar, handling empty strings
String _getUserInitial(String? displayName, String? email) {
  // Try displayName first, then email, then fallback to 'U'
  final name = (displayName?.isNotEmpty == true) 
      ? displayName 
      : (email?.isNotEmpty == true) 
          ? email 
          : 'U';
  return name![0].toUpperCase();
}

// ==================== USER ACCOUNT BUTTON ==================== //

class _UserAccountButton extends ConsumerWidget {
  const _UserAccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final authNotifier = ref.read(authNotifierProvider.notifier);

    return authState.when(
      data: (user) {
        if (user != null) {
          // User is logged in - show avatar with popup menu
          return PopupMenuButton<String>(
            offset: const Offset(0, 40),
            tooltip: user.email ?? 'Account',
            onSelected: (value) async {
              if (value == 'profile') {
                final url = Uri.parse('https://kumiho.io/app/profile');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
                return;
              }
              if (value == 'logout') {
                await authNotifier.signOut();
              }
            },
            itemBuilder: (context) {
              final colors = KumihoTheme.of(context);
              return [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'User',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (user.email != null)
                        Text(
                          user.email!,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 18, color: colors.textMuted),
                      const SizedBox(width: 8),
                      Text('Open Profile', style: TextStyle(color: colors.textPrimary)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18, color: colors.textMuted),
                      const SizedBox(width: 8),
                      Text('Sign Out', style: TextStyle(color: colors.textPrimary)),
                    ],
                  ),
                ),
              ];
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KumihoTheme.primary,
              ),
              child: SafeNetworkImage(
                url: user.photoURL,
                width: 32,
                height: 32,
                borderRadius: BorderRadius.circular(16),
                fallback: Center(
                  child: Text(
                    _getUserInitial(user.displayName, user.email),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          // User is not logged in - show login button
          final colors = KumihoTheme.of(context);
          return IconButton(
            icon: Icon(Icons.account_circle_outlined, size: 22, color: colors.textMuted),
            onPressed: () => _showLoginDialog(context, ref),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36),
            tooltip: 'Sign In',
          );
        }
      },
      loading: () => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: KumihoTheme.textMuted),
      ),
      error: (_, __) {
        final colors = KumihoTheme.of(context);
        return IconButton(
          icon: Icon(Icons.account_circle_outlined, size: 22, color: colors.textMuted),
          onPressed: () => _showLoginDialog(context, ref),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36),
          tooltip: 'Sign In',
        );
      },
    );
  }

  void _showLoginDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _EmailLoginDialog(),
    );
  }
}

class _EmailLoginDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EmailLoginDialog> createState() => _EmailLoginDialogState();
}

class _EmailLoginDialogState extends ConsumerState<_EmailLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authNotifier = ref.read(authNotifierProvider.notifier);
      await authNotifier.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final isDark = KumihoTheme.isDarkMode(context);
    
    return AlertDialog(
      backgroundColor: colors.backgroundCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              isDark
                  ? 'assets/images/kumiho_logo_white.png'
                  : 'assets/images/kumiho_logo_black.png',
              width: 40,
              height: 40,
              errorBuilder: (_, __, ___) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [KumihoTheme.primary, KumihoTheme.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pets, size: 20, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Sign in to Kumiho',
            style: TextStyle(color: colors.textPrimary, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Email field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: colors.textMuted),
                prefixIcon: Icon(Icons.email_outlined, color: colors.textMuted, size: 20),
                filled: true,
                fillColor: colors.backgroundMain,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: KumihoTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(color: colors.textPrimary),
              onSubmitted: (_) => _signIn(),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: colors.textMuted),
                prefixIcon: Icon(Icons.lock_outlined, color: colors.textMuted, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: colors.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true,
                fillColor: colors.backgroundMain,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: KumihoTheme.primary),
                ),
              ),
            ),
            // Forgot password link
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final url = Uri.parse('https://kumiho.io/login/forgot-password');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: KumihoTheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            // Sign in button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KumihoTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            // Sign up link
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                TextButton(
                  onPressed: () async {
                    final url = Uri.parse('https://kumiho.io/login');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sign Up',
                    style: TextStyle(
                      color: KumihoTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== LOGO ==================== //

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        KumihoTheme.isDarkMode(context)
            ? 'assets/images/kumiho_logo_white.png'
            : 'assets/images/kumiho_logo_black.png',
        width: KumihoTheme.logoSize,
        height: KumihoTheme.logoSize,
        errorBuilder: (_, __, ___) => Container(
          width: KumihoTheme.logoSize,
          height: KumihoTheme.logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [KumihoTheme.primary, KumihoTheme.primaryLight],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.pets, size: KumihoTheme.logoSize * 0.5, color: Colors.white),
        ),
      ),
    );
  }
}

// ==================== HEADER DROPDOWN ==================== //

class _HeaderDropdown extends StatefulWidget {
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String? hint;
  final bool isLoading;

  const _HeaderDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.isLoading = false,
  });

  @override
  State<_HeaderDropdown> createState() => _HeaderDropdownState();
}

class _HeaderDropdownState extends State<_HeaderDropdown> {
  List<String> _lastItems = const [];
  List<DropdownMenuItem<String>> _cachedMenuItems = const [];

  bool _sameItems(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _rebuildMenuItemsIfNeeded() {
    if (_sameItems(_lastItems, widget.items)) return;
    _lastItems = List<String>.from(widget.items);
    _cachedMenuItems = _lastItems
        .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis),
            ))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _rebuildMenuItemsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeaderDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildMenuItemsIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 180),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderLight),
      ),
      child: widget.isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.hint ?? 'Loading...',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          : ExcludeFocus(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: widget.items.contains(widget.value) ? widget.value : null,
                  hint: widget.hint != null
                      ? Text(
                          widget.hint!,
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  icon: Icon(Icons.keyboard_arrow_down, size: 18, color: colors.textMuted),
                  dropdownColor: colors.backgroundCard,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  isDense: true,
                  isExpanded: true,
                  items: _cachedMenuItems,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
    );
  }
}

// ==================== REFRESH BUTTON ==================== //

class _RefreshButton extends ConsumerWidget {
  const _RefreshButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(pagedItemsProvider.select((s) => s.isLoading || s.pendingDetails > 0));
    final isHardLoading = ref.watch(pagedItemsProvider.select((s) => s.isLoading));
    final colors = KumihoTheme.of(context);
    
    return IconButton(
      icon: isBusy 
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted),
              ),
            )
          : Icon(Icons.refresh, size: 20, color: colors.textMuted),
      onPressed: isHardLoading ? null : () {
        // Increment refresh trigger to force reload
        ref.read(kumihoRefreshTriggerProvider.notifier).state++;
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36),
      tooltip: isBusy ? 'Loading…' : 'Refresh',
    );
  }
}

// ==================== VIEW TOGGLE ==================== //

class _ViewToggle extends StatelessWidget {
  final bool isGridView;
  final ValueChanged<bool> onToggle;

  const _ViewToggle({
    required this.isGridView,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderLight, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(context, Icons.grid_view_rounded, true),
          _buildButton(context, Icons.view_list_rounded, false),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, IconData icon, bool isGrid) {
    final colors = KumihoTheme.of(context);
    final isActive = isGridView == isGrid;
    return InkWell(
      onTap: () => onToggle(isGrid),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? KumihoTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isGrid ? const Radius.circular(5) : Radius.zero,
            right: !isGrid ? const Radius.circular(5) : Radius.zero,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? Colors.white : colors.textMuted,
        ),
      ),
    );
  }
}

// ==================== ZOOM SLIDER ==================== //

class _ZoomSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ZoomSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_size_select_small, size: 14, color: colors.textDimmed),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: KumihoTheme.primary,
              inactiveTrackColor: colors.borderLight,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              min: 0.0,
              max: 1.0,
              divisions: 20,
            ),
          ),
        ),
        Icon(Icons.photo_size_select_large, size: 14, color: colors.textDimmed),
      ],
    );
  }
}
