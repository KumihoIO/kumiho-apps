// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/perf/perf_logger.dart';
import '../services/video_thumbnail_service.dart';

// ==================== DRAG DROP FORMAT ENUM ==================== //

/// Format for external drag-drop operations
enum DragDropFormat {
  location('File Location'),
  kref('Kref URI');

  final String displayName;
  const DragDropFormat(this.displayName);
}

// ==================== SETTINGS MODEL ==================== //

/// User preferences and application settings
class AppSettings {
  // View preferences
  final bool defaultToListView;
  final double defaultGridZoom;
  final bool autoRefreshEnabled;
  final int autoRefreshIntervalSeconds;

  // Content visibility
  final bool includeDeprecated;
  
  // Theme preferences
  final bool useDarkTheme;
  
  // Anonymous browsing - tenant ID for public projects
  final String? anonymousTenantId;

  // Local / self-hosted (CE) server connection.
  // When enabled, the app connects directly to a self-hosted Kumiho server
  // (Community Edition) and bypasses Firebase sign-in and control-plane
  // discovery entirely.
  final bool localServerEnabled;
  final String localServerHost;
  final int localServerPort;
  final bool localServerSecure;

  // Social sharing accounts (stored as JSON strings with OAuth tokens)
  final String? twitterAccountJson;
  final String? linkedInAccountJson;
  final String? redditAccountJson;
  final String? discordAccountJson;
  
  // Sharing preferences
  final bool enableExternalSharing;
  final String defaultShareMessage;
  
  // Keyboard shortcuts enabled
  final bool keyboardShortcutsEnabled;
  
  // Cache settings
  final int maxCacheSizeMb;
  final bool autoClearCache;
  
  // Drag-drop format for external apps
  final DragDropFormat dragDropFormat;
  
  // UI font scale settings (applies to entire browser)
  final double uiFontScale;  // 0.8 = small, 1.0 = medium, 1.2 = large
  
  const AppSettings({
    this.defaultToListView = false,
    this.defaultGridZoom = 0.5,
    this.autoRefreshEnabled = false,
    this.autoRefreshIntervalSeconds = 300,
    this.includeDeprecated = false,
    this.useDarkTheme = true,
    this.anonymousTenantId,
    this.localServerEnabled = false,
    this.localServerHost = '127.0.0.1',
    this.localServerPort = 9190,
    this.localServerSecure = false,
    this.twitterAccountJson,
    this.linkedInAccountJson,
    this.redditAccountJson,
    this.discordAccountJson,
    this.enableExternalSharing = true,
    this.defaultShareMessage = 'Check out this asset!',
    this.keyboardShortcutsEnabled = true,
    this.maxCacheSizeMb = 500,
    this.autoClearCache = false,
    this.dragDropFormat = DragDropFormat.location,
    this.uiFontScale = 1.0,
  });

  AppSettings copyWith({
    bool? defaultToListView,
    double? defaultGridZoom,
    bool? autoRefreshEnabled,
    int? autoRefreshIntervalSeconds,
    bool? includeDeprecated,
    bool? useDarkTheme,
    String? anonymousTenantId,
    bool? localServerEnabled,
    String? localServerHost,
    int? localServerPort,
    bool? localServerSecure,
    String? twitterAccountJson,
    String? linkedInAccountJson,
    String? redditAccountJson,
    String? discordAccountJson,
    bool? enableExternalSharing,
    String? defaultShareMessage,
    bool? keyboardShortcutsEnabled,
    int? maxCacheSizeMb,
    bool? autoClearCache,
    DragDropFormat? dragDropFormat,
    double? uiFontScale,
    bool clearAnonymousTenant = false,
    bool clearTwitter = false,
    bool clearLinkedIn = false,
    bool clearReddit = false,
    bool clearDiscord = false,
  }) {
    return AppSettings(
      defaultToListView: defaultToListView ?? this.defaultToListView,
      defaultGridZoom: defaultGridZoom ?? this.defaultGridZoom,
      autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
      autoRefreshIntervalSeconds: autoRefreshIntervalSeconds ?? this.autoRefreshIntervalSeconds,
      includeDeprecated: includeDeprecated ?? this.includeDeprecated,
      useDarkTheme: useDarkTheme ?? this.useDarkTheme,
      anonymousTenantId: clearAnonymousTenant ? null : (anonymousTenantId ?? this.anonymousTenantId),
      localServerEnabled: localServerEnabled ?? this.localServerEnabled,
      localServerHost: localServerHost ?? this.localServerHost,
      localServerPort: localServerPort ?? this.localServerPort,
      localServerSecure: localServerSecure ?? this.localServerSecure,
      twitterAccountJson: clearTwitter ? null : (twitterAccountJson ?? this.twitterAccountJson),
      linkedInAccountJson: clearLinkedIn ? null : (linkedInAccountJson ?? this.linkedInAccountJson),
      redditAccountJson: clearReddit ? null : (redditAccountJson ?? this.redditAccountJson),
      discordAccountJson: clearDiscord ? null : (discordAccountJson ?? this.discordAccountJson),
      enableExternalSharing: enableExternalSharing ?? this.enableExternalSharing,
      defaultShareMessage: defaultShareMessage ?? this.defaultShareMessage,
      keyboardShortcutsEnabled: keyboardShortcutsEnabled ?? this.keyboardShortcutsEnabled,
      maxCacheSizeMb: maxCacheSizeMb ?? this.maxCacheSizeMb,
      autoClearCache: autoClearCache ?? this.autoClearCache,
      dragDropFormat: dragDropFormat ?? this.dragDropFormat,
      uiFontScale: uiFontScale ?? this.uiFontScale,
    );
  }
  
  bool get hasTwitterConnected => twitterAccountJson != null;
  bool get hasLinkedInConnected => linkedInAccountJson != null;
  bool get hasRedditConnected => redditAccountJson != null;
  bool get hasDiscordConnected => discordAccountJson != null;
  int get connectedAccountsCount => 
    (hasTwitterConnected ? 1 : 0) + 
    (hasLinkedInConnected ? 1 : 0) + 
    (hasRedditConnected ? 1 : 0) + 
    (hasDiscordConnected ? 1 : 0);
}

// ==================== SOCIAL ACCOUNT MODEL ==================== //

/// Represents a connected social media account
class SocialAccount {
  final String platform;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String accessToken;
  final String? accessTokenSecret; // For OAuth 1.0a (Twitter media upload)
  final String? refreshToken;
  final DateTime? expiresAt;
  final DateTime connectedAt;

  const SocialAccount({
    required this.platform,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.accessToken,
    this.accessTokenSecret,
    this.refreshToken,
    this.expiresAt,
    required this.connectedAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'accessToken': accessToken,
    'accessTokenSecret': accessTokenSecret,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'connectedAt': connectedAt.toIso8601String(),
  };

  factory SocialAccount.fromJson(Map<String, dynamic> json) => SocialAccount(
    platform: json['platform'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    accessToken: json['accessToken'] as String,
    accessTokenSecret: json['accessTokenSecret'] as String?,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: json['expiresAt'] != null 
      ? DateTime.parse(json['expiresAt'] as String) 
      : null,
    connectedAt: DateTime.parse(json['connectedAt'] as String),
  );
}

// ==================== SETTINGS KEYS ==================== //

class _SettingsKeys {
  static const defaultToListView = 'settings_default_list_view';
  static const defaultGridZoom = 'settings_default_grid_zoom';
  static const autoRefreshEnabled = 'settings_auto_refresh_enabled';
  static const autoRefreshInterval = 'settings_auto_refresh_interval';
  static const includeDeprecated = 'settings_include_deprecated';
  static const useDarkTheme = 'settings_dark_theme';
  static const anonymousTenantId = 'settings_anonymous_tenant_id';
  static const twitterAccount = 'settings_twitter_account';
  static const linkedInAccount = 'settings_linkedin_account';
  static const redditAccount = 'settings_reddit_account';
  static const discordAccount = 'settings_discord_account';
  static const enableExternalSharing = 'settings_external_sharing';
  static const defaultShareMessage = 'settings_share_message';
  static const keyboardShortcuts = 'settings_keyboard_shortcuts';
  static const maxCacheSize = 'settings_max_cache_size';
  static const autoClearCache = 'settings_auto_clear_cache';
  static const dragDropFormat = 'settings_drag_drop_format';
  static const uiFontScale = 'settings_ui_font_scale';
  static const localServerEnabled = 'settings_local_server_enabled';
  static const localServerHost = 'settings_local_server_host';
  static const localServerPort = 'settings_local_server_port';
  static const localServerSecure = 'settings_local_server_secure';
}

// ==================== SETTINGS NOTIFIER ==================== //

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    // IMPORTANT (Windows): shared_preferences initialization has been observed
    // to intermittently stall the UI isolate for ~20-30s during early startup.
    // Defer loading persisted settings until after startup settles.
    if (isWindows) {
      if (PerfLogger.enabled) {
        PerfLogger.log('SettingsNotifier: deferring settings load on Windows');
      }
      _deferredLoadTimer = Timer(const Duration(seconds: 30), () {
        unawaited(_loadSettings());
      });
    } else {
      unawaited(_loadSettings());
    }
  }

  Timer? _deferredLoadTimer;

  @override
  void dispose() {
    _deferredLoadTimer?.cancel();
    _deferredLoadTimer = null;
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (PerfLogger.enabled) {
      PerfLogger.mark('SettingsNotifier._loadSettings START');
    }

    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    if (PerfLogger.enabled) {
      PerfLogger.mark('SettingsNotifier._loadSettings got SharedPreferences');
    }
    
    state = AppSettings(
      defaultToListView: prefs.getBool(_SettingsKeys.defaultToListView) ?? false,
      defaultGridZoom: prefs.getDouble(_SettingsKeys.defaultGridZoom) ?? 0.5,
      autoRefreshEnabled: prefs.getBool(_SettingsKeys.autoRefreshEnabled) ?? false,
      autoRefreshIntervalSeconds: prefs.getInt(_SettingsKeys.autoRefreshInterval) ?? 300,
      includeDeprecated: prefs.getBool(_SettingsKeys.includeDeprecated) ?? false,
      useDarkTheme: prefs.getBool(_SettingsKeys.useDarkTheme) ?? true,
      anonymousTenantId: prefs.getString(_SettingsKeys.anonymousTenantId),
      localServerEnabled: prefs.getBool(_SettingsKeys.localServerEnabled) ?? false,
      localServerHost: prefs.getString(_SettingsKeys.localServerHost) ?? '127.0.0.1',
      localServerPort: prefs.getInt(_SettingsKeys.localServerPort) ?? 9190,
      localServerSecure: prefs.getBool(_SettingsKeys.localServerSecure) ?? false,
      twitterAccountJson: prefs.getString(_SettingsKeys.twitterAccount),
      linkedInAccountJson: prefs.getString(_SettingsKeys.linkedInAccount),
      redditAccountJson: prefs.getString(_SettingsKeys.redditAccount),
      discordAccountJson: prefs.getString(_SettingsKeys.discordAccount),
      enableExternalSharing: prefs.getBool(_SettingsKeys.enableExternalSharing) ?? true,
      defaultShareMessage: prefs.getString(_SettingsKeys.defaultShareMessage) ?? 'Check out this asset!',
      keyboardShortcutsEnabled: prefs.getBool(_SettingsKeys.keyboardShortcuts) ?? true,
      maxCacheSizeMb: prefs.getInt(_SettingsKeys.maxCacheSize) ?? 500,
      autoClearCache: prefs.getBool(_SettingsKeys.autoClearCache) ?? false,
      dragDropFormat: DragDropFormat.values.firstWhere(
        (f) => f.name == prefs.getString(_SettingsKeys.dragDropFormat),
        orElse: () => DragDropFormat.location,
      ),
      uiFontScale: prefs.getDouble(_SettingsKeys.uiFontScale) ?? 1.0,
    );
    
    // Sync cache settings to VideoThumbnailService
    VideoThumbnailService().updateSettings(
      maxCacheSizeMb: state.maxCacheSizeMb,
      autoClearEnabled: state.autoClearCache,
    );

    if (PerfLogger.enabled) {
      PerfLogger.mark('SettingsNotifier._loadSettings DONE');
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool(_SettingsKeys.defaultToListView, state.defaultToListView);
    await prefs.setDouble(_SettingsKeys.defaultGridZoom, state.defaultGridZoom);
    await prefs.setBool(_SettingsKeys.autoRefreshEnabled, state.autoRefreshEnabled);
    await prefs.setInt(_SettingsKeys.autoRefreshInterval, state.autoRefreshIntervalSeconds);
    await prefs.setBool(_SettingsKeys.includeDeprecated, state.includeDeprecated);
    await prefs.setBool(_SettingsKeys.useDarkTheme, state.useDarkTheme);
    await prefs.setBool(_SettingsKeys.enableExternalSharing, state.enableExternalSharing);
    await prefs.setString(_SettingsKeys.defaultShareMessage, state.defaultShareMessage);
    await prefs.setBool(_SettingsKeys.keyboardShortcuts, state.keyboardShortcutsEnabled);
    await prefs.setInt(_SettingsKeys.maxCacheSize, state.maxCacheSizeMb);
    await prefs.setBool(_SettingsKeys.autoClearCache, state.autoClearCache);
    await prefs.setString(_SettingsKeys.dragDropFormat, state.dragDropFormat.name);
    await prefs.setDouble(_SettingsKeys.uiFontScale, state.uiFontScale);
    await prefs.setBool(_SettingsKeys.localServerEnabled, state.localServerEnabled);
    await prefs.setString(_SettingsKeys.localServerHost, state.localServerHost);
    await prefs.setInt(_SettingsKeys.localServerPort, state.localServerPort);
    await prefs.setBool(_SettingsKeys.localServerSecure, state.localServerSecure);

    // Save anonymous tenant ID
    if (state.anonymousTenantId != null) {
      await prefs.setString(_SettingsKeys.anonymousTenantId, state.anonymousTenantId!);
    } else {
      await prefs.remove(_SettingsKeys.anonymousTenantId);
    }
    
    // Save social accounts
    if (state.twitterAccountJson != null) {
      await prefs.setString(_SettingsKeys.twitterAccount, state.twitterAccountJson!);
    } else {
      await prefs.remove(_SettingsKeys.twitterAccount);
    }
    if (state.linkedInAccountJson != null) {
      await prefs.setString(_SettingsKeys.linkedInAccount, state.linkedInAccountJson!);
    } else {
      await prefs.remove(_SettingsKeys.linkedInAccount);
    }
    if (state.redditAccountJson != null) {
      await prefs.setString(_SettingsKeys.redditAccount, state.redditAccountJson!);
    } else {
      await prefs.remove(_SettingsKeys.redditAccount);
    }
    if (state.discordAccountJson != null) {
      await prefs.setString(_SettingsKeys.discordAccount, state.discordAccountJson!);
    } else {
      await prefs.remove(_SettingsKeys.discordAccount);
    }
  }

  // View preferences
  void setDefaultToListView(bool value) {
    state = state.copyWith(defaultToListView: value);
    _saveSettings();
  }

  void setDefaultGridZoom(double value) {
    state = state.copyWith(defaultGridZoom: value.clamp(0.0, 1.0));
    _saveSettings();
  }

  void setAutoRefresh(bool enabled, {int? intervalSeconds}) {
    state = state.copyWith(
      autoRefreshEnabled: enabled,
      autoRefreshIntervalSeconds: intervalSeconds,
    );
    _saveSettings();
  }

  void setIncludeDeprecated(bool value) {
    state = state.copyWith(includeDeprecated: value);
    _saveSettings();
  }

  // Theme preferences
  void setDarkTheme(bool value) {
    state = state.copyWith(useDarkTheme: value);
    _saveSettings();
  }

  // Drag-drop format for external apps
  void setDragDropFormat(DragDropFormat format) {
    state = state.copyWith(dragDropFormat: format);
    _saveSettings();
  }

  // UI font scale settings
  void setUIFontScale(double value) {
    state = state.copyWith(uiFontScale: value.clamp(0.8, 1.2));
    _saveSettings();
  }

  // Anonymous browsing
  void setAnonymousTenantId(String? tenantId) {
    if (tenantId == null || tenantId.trim().isEmpty) {
      state = state.copyWith(clearAnonymousTenant: true);
    } else {
      state = state.copyWith(anonymousTenantId: tenantId.trim());
    }
    _saveSettings();
  }

  // Local / self-hosted (CE) server connection
  void setLocalServerEnabled(bool value) {
    state = state.copyWith(localServerEnabled: value);
    _saveSettings();
  }

  void setLocalServerHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(localServerHost: trimmed);
    _saveSettings();
  }

  void setLocalServerPort(int port) {
    if (port <= 0 || port > 65535) return;
    state = state.copyWith(localServerPort: port);
    _saveSettings();
  }

  void setLocalServerSecure(bool value) {
    state = state.copyWith(localServerSecure: value);
    _saveSettings();
  }

  // Sharing preferences
  void setExternalSharing(bool enabled) {
    state = state.copyWith(enableExternalSharing: enabled);
    _saveSettings();
  }

  void setDefaultShareMessage(String message) {
    state = state.copyWith(defaultShareMessage: message);
    _saveSettings();
  }

  // Social accounts
  void connectTwitterAccount(String accountJson) {
    state = state.copyWith(twitterAccountJson: accountJson);
    _saveSettings();
  }

  void disconnectTwitterAccount() {
    state = state.copyWith(clearTwitter: true);
    _saveSettings();
  }

  void connectLinkedInAccount(String accountJson) {
    state = state.copyWith(linkedInAccountJson: accountJson);
    _saveSettings();
  }

  void disconnectLinkedInAccount() {
    state = state.copyWith(clearLinkedIn: true);
    _saveSettings();
  }

  void connectRedditAccount(String accountJson) {
    state = state.copyWith(redditAccountJson: accountJson);
    _saveSettings();
  }

  void disconnectRedditAccount() {
    state = state.copyWith(clearReddit: true);
    _saveSettings();
  }

  void connectDiscordAccount(String accountJson) {
    state = state.copyWith(discordAccountJson: accountJson);
    _saveSettings();
  }

  void disconnectDiscordAccount() {
    state = state.copyWith(clearDiscord: true);
    _saveSettings();
  }

  // Connection settings
  void setUseTls(bool value) {
    // TLS setting is stored locally but used in kumiho_provider
    _saveUseTls(value);
  }

  Future<void> _saveUseTls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings_use_tls', value);
  }

  // Asset directory
  void setAssetDirectory(String path) {
    _saveAssetDirectory(path);
  }

  Future<void> _saveAssetDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_asset_directory', path);
  }

  // Clear application cache
  Future<void> clearCache() async {
    // Clear video thumbnail cache
    await VideoThumbnailService().clearCache();
  }

  // Keyboard shortcuts
  void setKeyboardShortcutsEnabled(bool enabled) {
    state = state.copyWith(keyboardShortcutsEnabled: enabled);
    _saveSettings();
  }

  // Cache settings
  void setCacheSettings({int? maxSizeMb, bool? autoClear}) {
    state = state.copyWith(
      maxCacheSizeMb: maxSizeMb,
      autoClearCache: autoClear,
    );
    _saveSettings();
    
    // Sync to VideoThumbnailService
    VideoThumbnailService().updateSettings(
      maxCacheSizeMb: state.maxCacheSizeMb,
      autoClearEnabled: state.autoClearCache,
    );
  }

  // Reset all settings to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Remove all settings keys
    await prefs.remove(_SettingsKeys.defaultToListView);
    await prefs.remove(_SettingsKeys.defaultGridZoom);
    await prefs.remove(_SettingsKeys.autoRefreshEnabled);
    await prefs.remove(_SettingsKeys.autoRefreshInterval);
    await prefs.remove(_SettingsKeys.includeDeprecated);
    await prefs.remove(_SettingsKeys.useDarkTheme);
    await prefs.remove(_SettingsKeys.anonymousTenantId);
    await prefs.remove(_SettingsKeys.localServerEnabled);
    await prefs.remove(_SettingsKeys.localServerHost);
    await prefs.remove(_SettingsKeys.localServerPort);
    await prefs.remove(_SettingsKeys.localServerSecure);
    await prefs.remove(_SettingsKeys.twitterAccount);
    await prefs.remove(_SettingsKeys.linkedInAccount);
    await prefs.remove(_SettingsKeys.redditAccount);
    await prefs.remove(_SettingsKeys.discordAccount);
    await prefs.remove(_SettingsKeys.enableExternalSharing);
    await prefs.remove(_SettingsKeys.defaultShareMessage);
    await prefs.remove(_SettingsKeys.keyboardShortcuts);
    await prefs.remove(_SettingsKeys.maxCacheSize);
    await prefs.remove(_SettingsKeys.autoClearCache);
    
    state = const AppSettings();
  }
}

// ==================== PROVIDERS ==================== //

/// Main settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

/// Whether user prefers list view by default
final defaultToListViewProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).defaultToListView;
});

/// Whether external sharing is enabled
final externalSharingEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).enableExternalSharing;
});

/// Number of connected social accounts
final connectedSocialAccountsProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).connectedAccountsCount;
});

/// Anonymous tenant ID for browsing public projects
final anonymousTenantIdProvider = Provider<String?>((ref) {
  return ref.watch(settingsProvider).anonymousTenantId;
});

/// Whether dark theme is enabled
final useDarkThemeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).useDarkTheme;
});

/// Whether deprecated content is shown.
final includeDeprecatedProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).includeDeprecated;
});
