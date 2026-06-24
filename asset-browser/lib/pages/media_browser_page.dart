// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/browser_provider.dart';
import '../theme/kumiho_theme.dart';
import '../widgets/widgets.dart';

/// Main media browser page composing all UI components
class MediaBrowserPage extends ConsumerWidget {
  const MediaBrowserPage({super.key});

  // Startup-bisection flags.
  // Accept both STARTUP_DISABLE_* and SKIP_DISABLE_* to avoid command-line mixups.
  static const bool _startupDisableHeader =
    String.fromEnvironment('STARTUP_DISABLE_HEADER', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_HEADER', defaultValue: '0') == '1';
  static const bool _startupDisablePlaylist =
    String.fromEnvironment('STARTUP_DISABLE_PLAYLIST', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_PLAYLIST', defaultValue: '0') == '1';
  static const bool _startupDisablePlaylistSidebar =
    String.fromEnvironment('STARTUP_DISABLE_PLAYLIST_SIDEBAR', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_PLAYLIST_SIDEBAR', defaultValue: '0') == '1';
  static const bool _startupDisablePlaylistArea =
    String.fromEnvironment('STARTUP_DISABLE_PLAYLIST_AREA', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_PLAYLIST_AREA', defaultValue: '0') == '1';
  static const bool _startupDisableMain =
    String.fromEnvironment('STARTUP_DISABLE_MAIN', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_MAIN', defaultValue: '0') == '1';
  static const bool _startupDisableDetail =
    String.fromEnvironment('STARTUP_DISABLE_DETAIL', defaultValue: '0') == '1' ||
    String.fromEnvironment('SKIP_DISABLE_DETAIL', defaultValue: '0') == '1';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);

    // Space key is handled at the grid/playlist level for proper context
    return Scaffold(
      backgroundColor: colors.backgroundMain,
      body: _buildContent(context, state, notifier, ref),
    );
  }

  Widget _buildContent(BuildContext context, BrowserState state, BrowserNotifier notifier, WidgetRef ref) {
    final allDisabled =
        _startupDisableHeader && _startupDisablePlaylist && _startupDisableMain && _startupDisableDetail;

    final disablePlaylistSidebar = _startupDisablePlaylist || _startupDisablePlaylistSidebar;
    final disablePlaylistArea = _startupDisablePlaylist || _startupDisablePlaylistArea;

    return Column(
      children: [
        // TOP HEADER: Logo, project/space, view toggle, zoom, settings, user
        if (!_startupDisableHeader) const HeaderBar(),
        // THREE COLUMNS
        Expanded(
          child: Row(
            children: [
              // Column 1: Playlist panel (collapsible) - hidden in list view
              if (!disablePlaylistSidebar && state.showPlaylistArea)
                const PlaylistSidebar(),
              // Column 2: Main browser (search, filters, breadcrumb, clips)
              // Wrapped with ZoomGestureHandler for Alt+scroll zoom
              if (_startupDisableMain)
                Expanded(
                  child: Center(
                    child: Text(
                      allDisabled ? 'STARTUP_ALL_UI_DISABLED' : 'STARTUP_MAIN_DISABLED',
                      style: TextStyle(color: KumihoTheme.of(context).textMuted),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ZoomGestureHandler(
                    onZoom: (delta) {
                      final newZoom = (state.gridZoom + delta).clamp(0.0, 1.0);
                      notifier.setGridZoom(newZoom);
                    },
                    child: _buildMainBrowserColumn(state, ref),
                  ),
                ),
              // Column 3: Details panel (or List Detail panel in list view)
              if (!_startupDisableDetail)
                state.isGridView
                    ? const DetailPanel()
                    : const ListDetailPanel(),
            ],
          ),
        ),
        // BOTTOM PLAYLIST AREA - also with zoom support, hidden in list view
        if (!disablePlaylistArea && state.showPlaylistArea)
          ZoomGestureHandler(
            onZoom: (delta) {
              final newZoom = (state.playlistZoom + delta).clamp(0.0, 1.0);
              notifier.setPlaylistZoom(newZoom);
            },
            child: const PlaylistArea(),
          )
        else if (state.isGridView)
          // Show a minimized bar to restore playlist
          _MinimizedPlaylistBar(onRestore: notifier.toggleShowPlaylistArea),
      ],
    );
  }

  Widget _buildMainBrowserColumn(BrowserState state, WidgetRef ref) {
    return Column(
      children: [
        const SearchFilterBar(),
        const BreadcrumbBar(),
        Expanded(
          child: state.isGridView ? const MediaGrid() : const MediaList(),
        ),
      ],
    );
  }
}

/// Minimized bar shown when playlist is collapsed
class _MinimizedPlaylistBar extends StatelessWidget {
  final VoidCallback onRestore;

  const _MinimizedPlaylistBar({required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return GestureDetector(
      onTap: onRestore,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            color: colors.backgroundHeader,
            border: Border(
              top: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_arrow_up, size: 16, color: colors.textMuted),
              const SizedBox(width: 4),
              Icon(Icons.playlist_play, size: 14, color: KumihoTheme.primary),
              const SizedBox(width: 4),
              Text(
                'Show Playlist',
                style: TextStyle(
                  color: colors.textDimmed,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
