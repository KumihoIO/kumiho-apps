// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/oauth_service.dart';
import '../services/update_service.dart';
import '../services/video_thumbnail_service.dart';
import '../theme/kumiho_theme.dart';
import 'safe_network_image.dart';

/// Format bytes to human-readable string
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Get human-readable label for UI font scale
String _getFontSizeLabel(double fontScale) {
  if (fontScale <= 0.85) return 'Small';
  if (fontScale <= 0.95) return 'Compact';
  if (fontScale <= 1.05) return 'Normal';
  if (fontScale <= 1.15) return 'Large';
  return 'Extra Large';
}

/// Shows the settings dialog
void showSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const SettingsDialog(),
  );
}

/// Main settings dialog with tabbed navigation
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  int _selectedSection = 0;

  final _sections = const [
    _SectionItem(icon: Icons.person_outline, label: 'Account'),
    _SectionItem(icon: Icons.tune, label: 'Preferences'),
    _SectionItem(icon: Icons.share_outlined, label: 'Sharing'),
    _SectionItem(icon: Icons.keyboard, label: 'Shortcuts'),
    _SectionItem(icon: Icons.storage_outlined, label: 'Storage'),
    _SectionItem(icon: Icons.info_outline, label: 'About'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    // Calculate 80% of screen size for the dialog
    final dialogWidth = (screenSize.width * 0.6).clamp(600.0, 900.0);
    final dialogHeight = screenSize.height * 0.8;
    
    return Dialog(
      backgroundColor: colors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KumihoTheme.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.1,
        vertical: screenSize.height * 0.1,
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          children: [
            // Left navigation rail
            Container(
              width: 180,
              decoration: BoxDecoration(
                color: colors.backgroundSidebar,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(KumihoTheme.radiusLg),
                  bottomLeft: Radius.circular(KumihoTheme.radiusLg),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 20, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.border, height: 1),
                  // Navigation items
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _sections.length,
                      itemBuilder: (context, index) {
                        final section = _sections[index];
                        final isSelected = index == _selectedSection;
                        return _NavigationItem(
                          icon: section.icon,
                          label: section.label,
                          isSelected: isSelected,
                          onTap: () => setState(() => _selectedSection = index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Content area
            Expanded(
              child: Column(
                children: [
                  // Title bar with close
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _sections[_selectedSection].label,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                          splashRadius: 16,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                  // Section content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildSectionContent(),
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

  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case 0:
        return const _AccountSection();
      case 1:
        return const _PreferencesSection();
      case 2:
        return const _SharingSection();
      case 3:
        return const _ShortcutsSection();
      case 4:
        return const _StorageSection();
      case 5:
        return const _AboutSection();
      default:
        return const SizedBox();
    }
  }
}

// ==================== SECTION CLASSES ==================== //

class _SectionItem {
  final IconData icon;
  final String label;
  const _SectionItem({required this.icon, required this.label});
}

class _NavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected ? KumihoTheme.primary.withAlpha(38) : Colors.transparent,
        borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
          hoverColor: KumihoTheme.primary.withAlpha(26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? KumihoTheme.primary : colors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    color: isSelected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== ACCOUNT SECTION ==================== //

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  late TextEditingController _tenantIdController;
  late TextEditingController _localHostController;
  late TextEditingController _localPortController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _tenantIdController = TextEditingController(text: settings.anonymousTenantId ?? '');
    _localHostController = TextEditingController(text: settings.localServerHost);
    _localPortController = TextEditingController(text: '${settings.localServerPort}');
  }

  @override
  void dispose() {
    _tenantIdController.dispose();
    _localHostController.dispose();
    _localPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final user = ref.watch(currentUserProvider);
    final sessionAsync = ref.watch(kumihoSessionProvider);
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final settings = ref.watch(settingsProvider);

    // Safe way to get the first character for avatar
    String getAvatarInitial() {
      final name = user?.displayName ?? user?.email ?? 'U';
      return name.isNotEmpty ? name[0].toUpperCase() : 'U';
    }

    InputDecoration connDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: colors.textDimmed, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: const BorderSide(color: KumihoTheme.primary),
          ),
          filled: true,
          fillColor: colors.backgroundCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Local / self-hosted (CE) server connection
        _SettingsCard(
          title: 'Local / Self-hosted Server',
          subtitle: 'Connect directly to a self-hosted Kumiho server (Community '
              'Edition). No sign-in required.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingRow(
                title: 'Use local server',
                subtitle: 'Bypass cloud sign-in and tenant discovery',
                trailing: Switch(
                  value: settings.localServerEnabled,
                  onChanged: ref.read(settingsProvider.notifier).setLocalServerEnabled,
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
              if (settings.localServerEnabled) ...[
                Divider(color: colors.border, height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Host',
                              style: TextStyle(fontSize: 11, color: colors.textMuted)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _localHostController,
                            decoration: connDecoration('127.0.0.1'),
                            style: TextStyle(fontSize: 13, color: colors.textPrimary),
                            onChanged: ref.read(settingsProvider.notifier).setLocalServerHost,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Port',
                              style: TextStyle(fontSize: 11, color: colors.textMuted)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _localPortController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: connDecoration('9190'),
                            style: TextStyle(fontSize: 13, color: colors.textPrimary),
                            onChanged: (v) {
                              final p = int.tryParse(v.trim());
                              if (p != null) {
                                ref.read(settingsProvider.notifier).setLocalServerPort(p);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _SettingRow(
                  title: 'Use TLS',
                  subtitle: 'Leave off for local CE (plaintext gRPC)',
                  trailing: Switch(
                    value: settings.localServerSecure,
                    onChanged: ref.read(settingsProvider.notifier).setLocalServerSecure,
                    activeThumbColor: KumihoTheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KumihoTheme.info.withAlpha(26),
                    borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_outlined, size: 16, color: KumihoTheme.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Community Edition listens on 127.0.0.1:9190 by default and '
                          'does not require authentication.',
                          style: TextStyle(fontSize: 11, color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // User profile card
        _SettingsCard(
          title: 'User Profile',
          child: isAuthenticated && user != null
              ? Row(
                  children: [
                    // Avatar
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KumihoTheme.primary.withAlpha(51),
                      ),
                      child: SafeNetworkImage(
                        url: user.photoURL,
                        width: 64,
                        height: 64,
                        borderRadius: BorderRadius.circular(32),
                        fallback: Center(
                          child: Text(
                            getAvatarInitial(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: KumihoTheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName ?? 'User',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                          if (user.emailVerified) ...[
                            const SizedBox(height: 4),
                            const Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: KumihoTheme.success,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Email verified',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: KumihoTheme.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : const _NotSignedInMessage(),
        ),
        const SizedBox(height: 16),
        
        // Tenant information - show for authenticated users with session
        sessionAsync.when(
          data: (session) {
            if (session == null) return const SizedBox.shrink();
            return Column(
              children: [
                _SettingsCard(
                  title: 'Organization',
                  child: Column(
                    children: [
                      _InfoRow(
                        label: 'Tenant ID',
                        value: session.tenantId ?? 'Default',
                        copyable: true,
                      ),
                      Divider(color: colors.border, height: 16),
                      _InfoRow(
                        label: 'Server',
                        value: session.discoveryRecord?.serverUrl ?? 'Unknown',
                      ),
                      Divider(color: colors.border, height: 16),
                      _InfoRow(
                        label: 'Region',
                        value: session.discoveryRecord?.region.regionCode ?? 'Unknown',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        
        // Anonymous tenant browsing - show for non-authenticated users
        if (!isAuthenticated) ...[
          _SettingsCard(
            title: 'Browse Public Projects',
            subtitle: 'Enter a Tenant ID to browse public projects without signing in',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tenantIdController,
                        decoration: InputDecoration(
                          hintText: 'Enter Tenant ID (e.g., my-studio)',
                          hintStyle: TextStyle(color: colors.textDimmed, fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                            borderSide: const BorderSide(color: KumihoTheme.primary),
                          ),
                          filled: true,
                          fillColor: colors.backgroundCard,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).setAnonymousTenantId(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (settings.anonymousTenantId != null && settings.anonymousTenantId!.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _tenantIdController.clear();
                          ref.read(settingsProvider.notifier).setAnonymousTenantId(null);
                        },
                        tooltip: 'Clear',
                        splashRadius: 16,
                        color: colors.textMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KumihoTheme.info.withAlpha(26),
                    borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.public, size: 16, color: KumihoTheme.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only projects with public access enabled will be visible.',
                          style: TextStyle(fontSize: 11, color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Sign out button
        if (isAuthenticated)
          _SettingsCard(
            title: 'Session',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sign out of your account',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KumihoTheme.error.withAlpha(38),
                    foregroundColor: KumihoTheme.error,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NotSignedInMessage extends StatelessWidget {
  const _NotSignedInMessage();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KumihoTheme.warning.withAlpha(26),
        borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
        border: Border.all(color: KumihoTheme.warning.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: KumihoTheme.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sign in to access your account settings and connected services.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== PREFERENCES SECTION ==================== //

class _PreferencesSection extends ConsumerWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // View preferences
        _SettingsCard(
          title: 'View',
          child: Column(
            children: [
              _SettingRow(
                title: 'Default to List View',
                subtitle: 'Open browser in list view instead of gallery',
                trailing: Switch(
                  value: settings.defaultToListView,
                  onChanged: notifier.setDefaultToListView,
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
              Divider(color: colors.border, height: 20),
              _SettingRow(
                title: 'Default Zoom Level',
                subtitle: 'Thumbnail size when opening browser',
                trailing: SizedBox(
                  width: 120,
                  child: Slider(
                    value: settings.defaultGridZoom,
                    onChanged: notifier.setDefaultGridZoom,
                    activeColor: KumihoTheme.primary,
                    inactiveColor: colors.border,
                  ),
                ),
              ),
              Divider(color: colors.border, height: 20),
              _SettingRow(
                title: 'Include Deprecated',
                subtitle: 'Show deprecated items and revisions (rendered transparently)',
                trailing: Switch(
                  value: settings.includeDeprecated,
                  onChanged: notifier.setIncludeDeprecated,
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Auto-refresh
        _SettingsCard(
          title: 'Auto-Refresh',
          child: Column(
            children: [
              _SettingRow(
                title: 'Enable Auto-Refresh',
                subtitle: 'Use real-time events (with periodic fallback) to keep this view fresh',
                trailing: Switch(
                  value: settings.autoRefreshEnabled,
                  onChanged: (v) => notifier.setAutoRefresh(v),
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
              if (settings.autoRefreshEnabled) ...[
                Divider(color: colors.border, height: 20),
                _SettingRow(
                  title: 'Refresh Interval',
                  subtitle: 'How often to refresh (in seconds)',
                  trailing: SizedBox(
                    width: 90,
                    child: DropdownButtonFormField<int>(
                      initialValue: settings.autoRefreshIntervalSeconds,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                      dropdownColor: colors.backgroundCard,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Real-time')),
                        DropdownMenuItem(value: 60, child: Text('60s')),
                        DropdownMenuItem(value: 120, child: Text('120s')),
                        DropdownMenuItem(value: 300, child: Text('5m')),
                        DropdownMenuItem(value: 600, child: Text('10m')),
                      ],
                      onChanged: (v) => notifier.setAutoRefresh(true, intervalSeconds: v),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Theme (placeholder - could be expanded)
        _SettingsCard(
          title: 'Appearance',
          child: Column(
            children: [
              _SettingRow(
                title: 'Dark Theme',
                subtitle: 'Use dark color scheme',
                trailing: Switch(
                  value: settings.useDarkTheme,
                  onChanged: notifier.setDarkTheme,
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
              Divider(color: colors.border, height: 20),
              _SettingRow(
                title: 'UI Font Size',
                subtitle: 'Text size across the browser (${_getFontSizeLabel(settings.uiFontScale)})',
                trailing: SizedBox(
                  width: 140,
                  child: Row(
                    children: [
                      Text(
                        'S',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.uiFontScale,
                          min: 0.8,
                          max: 1.2,
                          divisions: 4,
                          onChanged: notifier.setUIFontScale,
                          activeColor: KumihoTheme.primary,
                          inactiveColor: colors.border,
                        ),
                      ),
                      Text(
                        'L',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // TODO: Re-enable when external drag-drop via super_drag_and_drop is fixed
        // Currently disabled due to gesture conflicts with Flutter's internal Draggable
        // const SizedBox(height: 16),
        // 
        // // External drag-drop format
        // _SettingsCard(
        //   title: 'Drag & Drop',
        //   child: Column(
        //     children: [
        //       _SettingRow(
        //         title: 'External Drag Format',
        //         subtitle: 'Data format when dragging to external apps',
        //         trailing: SizedBox(
        //           width: 140,
        //           child: DropdownButtonFormField<DragDropFormat>(
        //             value: settings.dragDropFormat,
        //             decoration: InputDecoration(
        //               border: OutlineInputBorder(
        //                 borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
        //                 borderSide: BorderSide(color: colors.border),
        //               ),
        //               contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        //               isDense: true,
        //             ),
        //             dropdownColor: colors.backgroundCard,
        //             isExpanded: true,
        //             items: DragDropFormat.values.map((format) {
        //               return DropdownMenuItem(
        //                 value: format,
        //                 child: Text(
        //                   format.displayName,
        //                   style: TextStyle(fontSize: 13, color: colors.textPrimary),
        //                 ),
        //               );
        //             }).toList(),
        //             onChanged: (v) {
        //               if (v != null) notifier.setDragDropFormat(v);
        //             },
        //           ),
        //         ),
        //       ),
        //     ],
        //   ),
        // ),
      ],
    );
  }
}

// ==================== SHARING SECTION ==================== //

class _SharingSection extends ConsumerStatefulWidget {
  const _SharingSection();

  @override
  ConsumerState<_SharingSection> createState() => _SharingSectionState();
}

class _SharingSectionState extends ConsumerState<_SharingSection> {
  final _oauthService = OAuthService();
  String? _connectingPlatform;

  final _twitterKeyController = TextEditingController();
  final _twitterSecretController = TextEditingController();
  bool _showTwitterSecret = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    await _oauthService.loadCredentials();
    if (!mounted) return;
    setState(() {
      _twitterKeyController.text = _oauthService.twitterConsumerKey;
      _twitterSecretController.text = _oauthService.twitterConsumerSecret;
    });
  }

  @override
  void dispose() {
    _twitterKeyController.dispose();
    _twitterSecretController.dispose();
    super.dispose();
  }

  Future<void> _saveTwitterCredentials() async {
    await _oauthService.saveTwitterCredentials(
      consumerKey: _twitterKeyController.text,
      consumerSecret: _twitterSecretController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved X/Twitter API credentials'),
        backgroundColor: KumihoTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    InputDecoration credDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: colors.textDimmed, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            borderSide: const BorderSide(color: KumihoTheme.primary),
          ),
          filled: true,
          fillColor: colors.backgroundCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        );

    // Parse connected accounts for display
    SocialAccount? twitterAccount;
    SocialAccount? linkedInAccount;
    SocialAccount? redditAccount;
    if (settings.twitterAccountJson != null) {
      try {
        twitterAccount = SocialAccount.fromJson(
          json.decode(settings.twitterAccountJson!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (settings.linkedInAccountJson != null) {
      try {
        linkedInAccount = SocialAccount.fromJson(
          json.decode(settings.linkedInAccountJson!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (settings.redditAccountJson != null) {
      try {
        redditAccount = SocialAccount.fromJson(
          json.decode(settings.redditAccountJson!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Anonymous user message
        if (!isAuthenticated)
          _SettingsCard(
            title: 'Sharing',
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.backgroundCard,
                borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                border: Border.all(color: colors.borderLight),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.textMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sign in to enable social media sharing.',
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // Sharing toggle - only for authenticated users
          _SettingsCard(
            title: 'External Sharing',
            child: _SettingRow(
              title: 'Enable Sharing',
              subtitle: 'Allow sharing assets to social media',
              trailing: Switch(
                value: settings.enableExternalSharing,
                onChanged: notifier.setExternalSharing,
                activeThumbColor: KumihoTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Social app credentials (bring your own) - only for authenticated users
        if (isAuthenticated) ...[
          _SettingsCard(
            title: 'Social App Credentials',
            subtitle: 'Bring your own developer keys. No API keys are bundled. '
                'Register an app in the X Developer Portal with callback URL '
                'http://localhost:8642/callback, then paste your API key & '
                'secret below. Stored locally on this device only.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('X (Twitter) API Key',
                    style: TextStyle(fontSize: 11, color: colors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: _twitterKeyController,
                  decoration: credDecoration('API Key'),
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                ),
                const SizedBox(height: 10),
                Text('X (Twitter) API Secret',
                    style: TextStyle(fontSize: 11, color: colors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: _twitterSecretController,
                  obscureText: !_showTwitterSecret,
                  decoration: credDecoration('API Secret').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showTwitterSecret
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setState(
                          () => _showTwitterSecret = !_showTwitterSecret),
                      color: colors.textMuted,
                    ),
                  ),
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _saveTwitterCredentials,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Credentials'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KumihoTheme.primary.withAlpha(38),
                      foregroundColor: KumihoTheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Connected accounts - only shown for authenticated users
        if (isAuthenticated) ...[
          _SettingsCard(
            title: 'Connected Accounts',
            subtitle: 'Connect accounts to share assets directly via API',
            child: Column(
              children: [
                _SocialAccountRow(
                  platform: 'Twitter / X',
                  icon: Icons.circle,
                  iconColor: const Color(0xFF000000),
                  isConnected: settings.hasTwitterConnected,
                  connectedAccount: twitterAccount,
                  isConnecting: _connectingPlatform == 'Twitter',
                  onConnect: () => _connectAccount('Twitter'),
                  onDisconnect: () => _disconnectAccount('Twitter', notifier),
                ),
                Divider(color: colors.border, height: 16),
                _SocialAccountRow(
                  platform: 'LinkedIn',
                  icon: Icons.circle,
                  iconColor: const Color(0xFF0A66C2),
                  isConnected: settings.hasLinkedInConnected,
                  connectedAccount: linkedInAccount,
                  isConnecting: _connectingPlatform == 'LinkedIn',
                  onConnect: () => _connectAccount('LinkedIn'),
                  onDisconnect: () => _disconnectAccount('LinkedIn', notifier),
                ),
                Divider(color: colors.border, height: 16),
                _SocialAccountRow(
                  platform: 'Reddit',
                  icon: Icons.forum,
                  iconColor: const Color(0xFFFF4500),
                  isConnected: settings.hasRedditConnected,
                  connectedAccount: redditAccount,
                  isConnecting: _connectingPlatform == 'Reddit',
                  comingSoon: true,
                  onConnect: () => _connectAccount('Reddit'),
                  onDisconnect: () => _disconnectAccount('Reddit', notifier),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Default message - only for authenticated users
          _SettingsCard(
            title: 'Share Message',
            child: TextField(
              controller: TextEditingController(text: settings.defaultShareMessage),
              onChanged: notifier.setDefaultShareMessage,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Default message when sharing...',
                hintStyle: TextStyle(color: colors.textDimmed),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                  borderSide: const BorderSide(color: KumihoTheme.primary),
                ),
                filled: true,
                fillColor: colors.backgroundCard,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _connectAccount(String platform) async {
    if (platform == 'Reddit') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reddit integration is coming soon. API keys are pending.'),
          backgroundColor: KumihoTheme.info,
        ),
      );
      return;
    }

    setState(() => _connectingPlatform = platform);
    
    try {
      SocialAccount? account;
      
      switch (platform) {
        case 'Twitter':
          account = await _oauthService.authenticateTwitter();
          break;
        case 'LinkedIn':
          account = await _oauthService.authenticateLinkedIn();
          break;
      }

      if (!mounted) return;

      if (account != null) {
        final notifier = ref.read(settingsProvider.notifier);
        final accountJson = json.encode(account.toJson());
        
        switch (platform) {
          case 'Twitter':
            notifier.connectTwitterAccount(accountJson);
            break;
          case 'LinkedIn':
            notifier.connectLinkedInAccount(accountJson);
            break;
          case 'Reddit':
            notifier.connectRedditAccount(accountJson);
            break;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to $platform as ${account.displayName}'),
              backgroundColor: KumihoTheme.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to connect to $platform. Please try again.'),
              backgroundColor: KumihoTheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting to $platform: $e'),
            backgroundColor: KumihoTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _connectingPlatform = null);
      }
    }
  }

  void _disconnectAccount(String platform, SettingsNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KumihoTheme.of(context).backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KumihoTheme.radiusMd),
          side: BorderSide(color: KumihoTheme.of(context).border),
        ),
        title: Text(
          'Disconnect $platform?',
          style: TextStyle(color: KumihoTheme.of(context).textPrimary),
        ),
        content: Text(
          'You will no longer be able to share directly to $platform until you reconnect.',
          style: TextStyle(color: KumihoTheme.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              switch (platform) {
                case 'Twitter':
                  notifier.disconnectTwitterAccount();
                  break;
                case 'LinkedIn':
                  notifier.disconnectLinkedInAccount();
                  break;
                case 'Reddit':
                  notifier.disconnectRedditAccount();
                  break;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Disconnected from $platform'),
                  backgroundColor: KumihoTheme.info,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: KumihoTheme.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

class _SocialAccountRow extends StatelessWidget {
  final String platform;
  final IconData icon;
  final Color iconColor;
  final bool isConnected;
  final SocialAccount? connectedAccount;
  final bool isConnecting;
  final bool comingSoon;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _SocialAccountRow({
    required this.platform,
    required this.icon,
    required this.iconColor,
    required this.isConnected,
    this.connectedAccount,
    this.isConnecting = false,
    this.comingSoon = false,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    // Determine subtitle text
    String subtitle;
    if (comingSoon) {
      subtitle = 'Coming soon';
    } else if (isConnecting) {
      subtitle = 'Connecting...';
    } else if (isConnected && connectedAccount != null) {
      subtitle = connectedAccount!.username;
    } else if (isConnected) {
      subtitle = 'Connected';
    } else {
      subtitle = 'Not connected';
    }
    
    return Row(
      children: [
        // Avatar or icon
        if (isConnected && connectedAccount?.avatarUrl != null)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            ),
            child: SafeNetworkImage(
              url: connectedAccount!.avatarUrl,
              width: 32,
              height: 32,
              borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
              fallback: Container(
                color: colors.surfaceLighter,
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
          )
        else
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(38),
              borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    platform,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (isConnected && connectedAccount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      connectedAccount!.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  if (isConnecting)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: KumihoTheme.primary,
                        ),
                      ),
                    ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isConnecting
                          ? KumihoTheme.primary
                          : isConnected
                              ? KumihoTheme.success
                              : colors.textDimmed,
                    ),
                  ),
                  // Show token expiry warning if token is expired or expiring soon
                  if (isConnected && connectedAccount?.expiresAt != null) ...[
                    const SizedBox(width: 8),
                    if (connectedAccount!.isExpired)
                      const Tooltip(
                        message: 'Token expired - reconnect to continue sharing',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: KumihoTheme.error,
                        ),
                      )
                    else if (connectedAccount!.expiresAt!
                        .isBefore(DateTime.now().add(const Duration(days: 7))))
                      const Tooltip(
                        message: 'Token expires soon',
                        child: Icon(
                          Icons.schedule,
                          size: 14,
                          color: KumihoTheme.warning,
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (isConnecting)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 20,
              height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (comingSoon)
          TextButton.icon(
            onPressed: null,
            icon: const Icon(Icons.schedule, size: 14),
            label: const Text('Coming Soon', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: colors.textDimmed,
              disabledForegroundColor: colors.textDimmed,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          )
        else if (isConnected)
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              foregroundColor: KumihoTheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
          )
        else
          TextButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link, size: 14),
            label: const Text('Connect', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: KumihoTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
      ],
    );
  }
}

// ==================== SHORTCUTS SECTION ==================== //

class _ShortcutsSection extends ConsumerWidget {
  const _ShortcutsSection();

  static const _shortcuts = [
    ('Toggle View Mode', 'Ctrl + G'),
    ('Zoom In', 'Ctrl + +'),
    ('Zoom Out', 'Ctrl + -'),
    ('Search', 'Ctrl + F'),
    ('Select All', 'Ctrl + A'),
    ('Refresh', 'F5'),
    ('Delete from Playlist', 'Delete'),
    ('Open Settings', 'Ctrl + ,'),
    ('Toggle Playlists Sidebar', 'Ctrl + B'),
    ('Toggle Playlist Area', 'Ctrl + Shift + B'),
    ('Navigate Items', '↑ ↓ ← →'),
    ('Open Item', 'Space'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          title: 'Keyboard Shortcuts',
          child: Column(
            children: [
              _SettingRow(
                title: 'Enable Keyboard Shortcuts',
                subtitle: 'Use keyboard to navigate and control the browser',
                trailing: Switch(
                  value: settings.keyboardShortcutsEnabled,
                  onChanged: notifier.setKeyboardShortcutsEnabled,
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Available Shortcuts',
          child: Column(
            children: _shortcuts.asMap().entries.map((entry) {
              final index = entry.key;
              final (action, shortcut) = entry.value;
              return Column(
                children: [
                  if (index > 0)
                    Divider(color: colors.border, height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.backgroundCard,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            shortcut,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ==================== STORAGE SECTION ==================== //

/// Provider for current cache size
final _cacheSizeProvider = FutureProvider<int>((ref) async {
  return videoThumbnailService.getCacheSize();
});

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cacheSizeAsync = ref.watch(_cacheSizeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          title: 'Cache Settings',
          child: Column(
            children: [
              _SettingRow(
                title: 'Maximum Cache Size',
                subtitle: 'Limit disk space for cached thumbnails',
                trailing: SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                      initialValue: settings.maxCacheSizeMb,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    dropdownColor: colors.backgroundCard,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 100, child: Text('100 MB')),
                      DropdownMenuItem(value: 250, child: Text('250 MB')),
                      DropdownMenuItem(value: 500, child: Text('500 MB')),
                      DropdownMenuItem(value: 1000, child: Text('1 GB')),
                      DropdownMenuItem(value: 2000, child: Text('2 GB')),
                    ],
                    onChanged: (v) => notifier.setCacheSettings(maxSizeMb: v),
                  ),
                ),
              ),
              Divider(color: colors.border, height: 20),
              _SettingRow(
                title: 'Auto-Clear Cache',
                subtitle: 'Clear old cache when limit reached',
                trailing: Switch(
                  value: settings.autoClearCache,
                  onChanged: (v) => notifier.setCacheSettings(autoClear: v),
                  activeThumbColor: KumihoTheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Clear Data',
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clear All Cache',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    cacheSizeAsync.when(
                      data: (size) => Text(
                        'Currently using ${_formatBytes(size)}',
                        style: TextStyle(fontSize: 11, color: colors.textDimmed),
                      ),
                      loading: () => Text(
                        'Calculating size...',
                        style: TextStyle(fontSize: 11, color: colors.textDimmed),
                      ),
                      error: (_, __) => Text(
                        'Remove all cached thumbnails and data',
                        style: TextStyle(fontSize: 11, color: colors.textDimmed),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await videoThumbnailService.clearCache();
                  ref.invalidate(_cacheSizeProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cache cleared successfully'),
                        backgroundColor: KumihoTheme.success,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: KumihoTheme.warning.withAlpha(38),
                  foregroundColor: KumihoTheme.warning,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Clear Cache'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Reset',
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reset All Settings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Restore all settings to default values',
                      style: TextStyle(fontSize: 11, color: colors.textDimmed),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: colors.backgroundSecondary,
                      title: const Text('Reset Settings?'),
                      content: const Text(
                        'This will reset all settings to their default values. This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: TextButton.styleFrom(foregroundColor: KumihoTheme.error),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await notifier.resetToDefaults();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Settings reset to defaults'),
                          backgroundColor: KumihoTheme.success,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: KumihoTheme.error.withAlpha(38),
                  foregroundColor: KumihoTheme.error,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Reset All'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== ABOUT SECTION ==================== //

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  final UpdateService _updateService = UpdateService();

  PackageInfo? _packageInfo;
  bool _checking = false;
  bool _installing = false;
  double? _downloadProgress;
  String? _updateError;
  AppUpdateCheckResult? _update;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _packageInfo = info);
    } catch (_) {
      // Non-fatal; the UI will show unknown version.
    }
  }

  String _platformLabel() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  Future<void> _runUpdateCheck() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateError = null;
    });

    final current = _packageInfo?.version ?? '0.0.0';
    try {
      final result = await _updateService.checkForUpdates(currentVersion: current);
      if (!mounted) return;
      setState(() => _update = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openUrl(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadAndInstallWindows() async {
    final installer = _update?.windowsInstaller;
    if (installer == null) return;

    setState(() {
      _installing = true;
      _downloadProgress = 0;
      _updateError = null;
    });

    try {
      final file = await _updateService.downloadToTemp(
        url: installer.downloadUrl,
        fileName: installer.name,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total == null || total == 0) {
            setState(() => _downloadProgress = null);
            return;
          }
          setState(() => _downloadProgress = received / total);
        },
      );

      await _updateService.launchWindowsInstallerAndExit(installer: file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _downloadProgress = null;
        _updateError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);

    final version = _packageInfo?.version ?? 'Unknown';
    final buildNumber = _packageInfo?.buildNumber;
    final buildLabel = (buildNumber == null || buildNumber.isEmpty) ? 'Unknown' : buildNumber;
    final platform = _platformLabel();

    final updateStatus = _update == null
        ? 'Not checked'
        : (_update!.updateAvailable
            ? 'Update available: ${_update!.latestVersion}'
            : 'Up to date');
    final canInstallWindows = Platform.isWindows && (_update?.windowsInstaller != null) && (_update?.updateAvailable == true);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          title: 'Kumiho Browser',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Version', value: version),
              Divider(color: colors.border, height: 16),
              _InfoRow(label: 'Build', value: buildLabel),
              Divider(color: colors.border, height: 16),
              _InfoRow(label: 'Platform', value: platform),
              Divider(color: colors.border, height: 16),
              const _InfoRow(label: 'License', value: 'Proprietary'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Updates',
          subtitle: updateStatus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingRow(
                title: 'Check for updates',
                subtitle: _updateError ?? 'Checks the latest GitHub release',
                trailing: ElevatedButton(
                  onPressed: _checking ? null : _runUpdateCheck,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KumihoTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text(_checking ? 'Checking…' : 'Check'),
                ),
              ),
              if (_update != null) ...[
                Divider(color: colors.border, height: 16),
                _SettingRow(
                  title: 'Latest release',
                  subtitle: _update!.latestVersion,
                  trailing: OutlinedButton(
                    onPressed: () => _openUrl(_update!.releasePageUrl),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ],
              if (_update?.updateAvailable == true) ...[
                Divider(color: colors.border, height: 16),
                if (Platform.isWindows)
                  _SettingRow(
                    title: 'Install update',
                    subtitle: (_installing && _downloadProgress != null)
                        ? 'Downloading… ${(100 * _downloadProgress!).toStringAsFixed(0)}%'
                        : (canInstallWindows
                            ? 'Downloads the installer and updates this app'
                            : 'Installer not available for this release'),
                    trailing: ElevatedButton(
                      onPressed: (!canInstallWindows || _installing) ? null : _downloadAndInstallWindows,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KumihoTheme.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: Text(_installing ? 'Installing…' : 'Download & Install'),
                    ),
                  )
                else if (Platform.isLinux)
                  ((_update?.linuxDeb == null) && (_update?.linuxRpm == null))
                      ? _SettingRow(
                          title: 'Download update',
                          subtitle: 'Open downloads and update via your package manager',
                          trailing: ElevatedButton(
                            onPressed: () => _openUrl(_update!.releasePageUrl),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KumihoTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Open downloads'),
                          ),
                        )
                      : Row(
                          children: [
                            if (_update?.linuxDeb != null)
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _openUrl(_update!.linuxDeb!.downloadUrl),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: KumihoTheme.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                  child: const Text('Download .deb'),
                                ),
                              ),
                            if (_update?.linuxDeb != null && _update?.linuxRpm != null)
                              const SizedBox(width: 12),
                            if (_update?.linuxRpm != null)
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _openUrl(_update!.linuxRpm!.downloadUrl),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: KumihoTheme.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                  child: const Text('Download .rpm'),
                                ),
                              ),
                          ],
                        )
                else
                  _SettingRow(
                    title: 'Download update',
                    subtitle: 'Download and replace the app manually',
                    trailing: ElevatedButton(
                      onPressed: () => _openUrl(_update!.releasePageUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KumihoTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Download'),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Links',
          child: Column(
            children: [
              const _LinkRow(
                icon: Icons.language,
                label: 'Website',
                url: 'https://kumiho.io',
              ),
              Divider(color: colors.border, height: 12),
              const _LinkRow(
                icon: Icons.description_outlined,
                label: 'Documentation',
                url: 'https://docs.kumiho.io/browser',
              ),
              Divider(color: colors.border, height: 12),
              const _LinkRow(
                icon: Icons.code,
                label: 'GitHub',
                url: 'https://github.com/kumihoclouds',
              ),
              Divider(color: colors.border, height: 12),
              const _LinkRow(
                icon: Icons.chat_outlined,
                label: 'Report Issue',
                url: 'https://discord.gg/Utp2P8G69P',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '© 2025 Kumiho Clouds. All rights reserved.',
            style: TextStyle(fontSize: 11, color: colors.textDimmed),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
  });

  Future<void> _launchUrl() async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return InkWell(
      onTap: _launchUrl,
      borderRadius: BorderRadius.circular(KumihoTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
            Text(
              url,
              style: const TextStyle(fontSize: 11, color: KumihoTheme.primary),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 12, color: KumihoTheme.primary),
          ],
        ),
      ),
    );
  }
}

// ==================== SHARED COMPONENTS ==================== //

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(KumihoTheme.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: colors.textDimmed),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: colors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, color: colors.textDimmed),
                ),
              ],
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
        if (copyable)
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: KumihoTheme.success,
                ),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 12, color: colors.textMuted),
                ],
              ),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
          ),
      ],
    );
  }
}
