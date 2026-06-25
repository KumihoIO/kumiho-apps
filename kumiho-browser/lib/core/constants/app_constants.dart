// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

/// Application-wide constants.
abstract class AppConstants {
  /// Application name
  static const String appName = 'Kumiho Browser';

  /// Application version
  static const String appVersion = '1.0.0';

  /// Default Kumiho server host
  static const String defaultHost = 'api.kumiho.cloud';

  /// Default Kumiho server port
  static const int defaultPort = 443;

  /// Local storage keys
  static const String authTokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String serverHostKey = 'server_host';
  static const String serverPortKey = 'server_port';
  static const String themeModeKey = 'theme_mode';
  static const String recentProjectsKey = 'recent_projects';

  /// UI constants
  static const double sidebarWidth = 280.0;
  static const double sidebarCollapsedWidth = 48.0;
  static const double panelMinWidth = 200.0;
  static const double panelMaxWidth = 600.0;

  /// Asset types
  static const List<String> assetKinds = [
    'model',
    'texture',
    'material',
    'rig',
    'animation',
    'workflow',
    'scene',
    'reference',
    'audio',
    'video',
    'document',
    'other',
  ];

  /// File type icons mapping
  static const Map<String, String> fileTypeIcons = {
    'fbx': '🎨',
    'obj': '🎨',
    'gltf': '🎨',
    'glb': '🎨',
    'usd': '🎨',
    'usda': '🎨',
    'usdz': '🎨',
    'blend': '🎨',
    'ma': '🎨',
    'mb': '🎨',
    'max': '🎨',
    'c4d': '🎨',
    'png': '🖼️',
    'jpg': '🖼️',
    'jpeg': '🖼️',
    'tiff': '🖼️',
    'tga': '🖼️',
    'exr': '🖼️',
    'hdr': '🖼️',
    'psd': '🖼️',
    'json': '📄',
    'yaml': '📄',
    'yml': '📄',
    'xml': '📄',
  };
}
