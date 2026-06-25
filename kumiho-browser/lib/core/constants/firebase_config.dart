/// Firebase configuration for Kumiho Browser
///
/// These credentials are safe to embed in the client app.
/// Firebase Security Rules protect backend data.
library;

class FirebaseConfig {
  FirebaseConfig._();

  /// Firebase API Key
  static const String apiKey = 'AIzaSyBFAo7Nv48xAvbN18rL-3W41Dqheporh8E';

  /// Firebase Auth Domain
  static const String authDomain = 'kumiho-server.firebaseapp.com';

  /// Firebase Project ID
  static const String projectId = 'kumiho-server';

  /// Firebase App ID (Web)
  static const String appId = '1:1024102474822:web:7d06c46d0682c6c8175647';

  /// Messaging Sender ID (optional, for FCM)
  static const String messagingSenderId = '1024102474822';

  /// Storage Bucket (optional)
  static const String storageBucket = 'kumiho-server.appspot.com';
}

/// Environment configuration loaded from --dart-define flags
///
/// Build commands:
/// - Development: flutter run -d windows
/// - Production:  flutter build windows --dart-define=ENVIRONMENT=production
///
/// Or use the helper scripts in the project root.
class Environment {
  Environment._();

  /// Current environment (development, staging, production)
  static const String current = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Check if running in development mode
  static bool get isDevelopment => current == 'development';

  /// Check if running in staging mode
  static bool get isStaging => current == 'staging';

  /// Check if running in production mode
  static bool get isProduction => current == 'production';

  /// Check if running in any non-production mode (dev or staging)
  static bool get isDebugMode => !isProduction;
}

/// Kumiho Control Plane configuration
///
/// URLs are determined by environment or can be overridden via --dart-define:
/// - CONTROL_PLANE_URL: Override control plane URL
/// - DATA_PLANE_URL: Override default data plane URL
class KumihoConfig {
  KumihoConfig._();

  /// Control Plane URL for authentication and tenant routing
  ///
  /// Can be overridden via: --dart-define=CONTROL_PLANE_URL=https://custom.url
  ///
  /// Defaults:
  /// - Development: http://localhost:3000
  /// - Staging: https://control-staging.kumiho.cloud
  /// - Production: https://control.kumiho.cloud
  static String get controlPlaneUrl {
    const override = String.fromEnvironment('CONTROL_PLANE_URL');
    if (override.isNotEmpty) return override;
    return _defaultControlPlaneUrl;
  }

  /// Optional data plane URL override.
  ///
  /// Useful for hybrid setups like: production control-plane + local data-plane.
  ///
  /// Set via: --dart-define=DATA_PLANE_URL=http://localhost:50051
  static String? get dataPlaneUrlOverride {
    const override = String.fromEnvironment('DATA_PLANE_URL');
    if (override.isEmpty) return null;
    return override;
  }

  /// Default data plane URL (used only as a fallback).
  static String get defaultDataPlaneUrl =>
      dataPlaneUrlOverride ?? 'https://api.kumiho.cloud';

  /// Internal: Determine default control plane URL based on environment
  static String get _defaultControlPlaneUrl {
    if (Environment.isProduction) return 'https://control.kumiho.cloud';
    if (Environment.isStaging) return 'https://control-staging.kumiho.cloud';
    return 'http://localhost:3000';
  }
}
