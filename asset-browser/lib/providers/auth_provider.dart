import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/control_plane_service.dart';
import '../core/constants/firebase_config.dart';
import 'settings_provider.dart';
import '../core/perf/perf_logger.dart';

const String _kumihoDiscoveryCacheKey = 'kumiho.discoveryRecord.v1';
const String _sdkDiscoveryDefaultCacheKey = '__default__';

File? _tryGetSdkDiscoveryCacheFile() {
  try {
    final override = Platform.environment['KUMIHO_DISCOVERY_CACHE_FILE'];
    if (override != null && override.trim().isNotEmpty) {
      return File(override.trim());
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOMEPATH'];
    if (home == null || home.trim().isEmpty) return null;
    return File('${home.trim()}/.kumiho/discovery-cache.json');
  } catch (_) {
    return null;
  }
}

Future<DiscoveryRecord?> _tryLoadDiscoveryFromSdkCache() async {
  try {
    final file = _tryGetSdkDiscoveryCacheFile();
    if (file == null) return null;
    if (!await file.exists()) return null;

    final text = await file.readAsString();
    if (text.trim().isEmpty) return null;

    // Newer kumiho-cli versions encrypt discovery-cache.json.
    // Example: "enc:v1:....". The asset-browser does not currently have the
    // decryption keychain integration, so we must ignore it.
    if (text.startsWith('enc:v1:')) {
      if (PerfLogger.enabled) {
        PerfLogger.log(
          'discovery sdk_cache_file is encrypted; ignoring '
          '(path=${file.path})',
        );
      }
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;

    final entry = decoded[_sdkDiscoveryDefaultCacheKey];
    if (entry is! Map<String, dynamic>) return null;
    final record = DiscoveryRecord.fromJson(entry);

    if (PerfLogger.enabled) {
      PerfLogger.log(
        'discovery cache hit: sdk_cache_file '
        '(path=${file.path}, expired=${record.cacheControl.isExpired}, '
        'expiresAt=${record.cacheControl.expiresAt.toIso8601String()})',
      );
    }

    return record;
  } catch (_) {
    return null;
  }
}

/// Top-level function for compute() - must not capture any context.
Future<Map<String, dynamic>> _discoverTenantInBackground(Map<String, String> args) async {
  final baseUrl = args['baseUrl']!;
  final firebaseIdToken = args['firebaseIdToken']!;
  final tenantHint = args['tenantHint'];
  final timeoutMs = int.parse(args['timeoutMs']!);
  final timeout = Duration(milliseconds: timeoutMs);

  final url = Uri.parse('$baseUrl/api/discovery/tenant');
  final body = <String, dynamic>{};
  if (tenantHint != null && tenantHint.isNotEmpty) {
    body['tenant_hint'] = tenantHint;
  }

  final response = await http
      .post(
        url,
        headers: {
          'Authorization': 'Bearer $firebaseIdToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(timeout);

  if (response.statusCode != 200) {
    throw 'Discovery failed: HTTP ${response.statusCode}: ${response.body}';
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return data;
}

Future<Map<String, dynamic>> _discoverTenantJsonInIsolate({
  required String baseUrl,
  required String firebaseIdToken,
  String? tenantHint,
  required Duration timeout,
}) async {
  // Use compute() which reuses Flutter's isolate pool, rather than Isolate.run()
  // which spawns a fresh isolate on each call and can block on Windows.
  final totalTimeout = timeout + const Duration(seconds: 2);
  final args = <String, String>{
    'baseUrl': baseUrl,
    'firebaseIdToken': firebaseIdToken,
    if (tenantHint != null) 'tenantHint': tenantHint,
    'timeoutMs': timeout.inMilliseconds.toString(),
  };
  return await compute(_discoverTenantInBackground, args).timeout(totalTimeout);
}

Future<DiscoveryRecord?> _loadCachedDiscoveryRecord() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kumihoDiscoveryCacheKey);
    if (raw != null && raw.isNotEmpty) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final record = DiscoveryRecord.fromJson(json);

      if (PerfLogger.enabled) {
        PerfLogger.log(
          'discovery cache hit: shared_prefs '
          '(expired=${record.cacheControl.isExpired}, '
          'expiresAt=${record.cacheControl.expiresAt.toIso8601String()})',
        );
      }

      return record;
    }

    // Fallback: if the user already logged in via kumiho-cli / SDK tooling,
    // reuse the SDK discovery cache as a last-known-good seed.
  final sdkRecord = await _tryLoadDiscoveryFromSdkCache();
    if (sdkRecord != null) return sdkRecord;

    if (PerfLogger.enabled) {
      final file = _tryGetSdkDiscoveryCacheFile();
      PerfLogger.log(
        'discovery cache miss: shared_prefs and sdk_cache_file '
        '(sdkPath=${file?.path ?? 'null'})',
      );
    }

    return null;
  } catch (_) {
    return null;
  }
}

Future<void> _saveCachedDiscoveryRecord(DiscoveryRecord record) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kumihoDiscoveryCacheKey, jsonEncode(record.toJson()));
  } catch (_) {
    // Ignore cache write failures.
  }
}

/// Whether Firebase is enabled for this build/platform.
///
/// On desktop platforms, Firebase requires platform-specific configuration
/// (e.g., a `GoogleService-Info.plist` on macOS). If that configuration is
/// missing, we disable Firebase so the app can still start (e.g., anonymous
/// browsing via tenant ID).
final firebaseEnabledProvider = Provider<bool>((ref) => true);

/// Provider for Firebase Auth instance
final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  final enabled = ref.watch(firebaseEnabledProvider);
  if (!enabled) return null;
  return FirebaseAuth.instance;
});

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return AuthService(auth: auth);
});

/// Provider for ControlPlaneService
final controlPlaneServiceProvider = Provider<ControlPlaneService>((ref) {
  return ControlPlaneService();
});

/// Stream provider for authentication state changes
///
/// Use this to reactively update UI when user signs in/out.
final authStateProvider = StreamProvider<User?>((ref) {
  PerfLogger.mark('authStateProvider: creating stream');
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges.map((user) {
    PerfLogger.mark('authStateProvider: stream emitted user=${user?.uid != null}');
    return user;
  });
});

/// Provider for current user (nullable)
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Provider for checking if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// Provider for checking if we can browse (authenticated OR anonymous with tenant ID)
/// Use this to determine if we should show the browser or sign-in prompt
final canBrowseProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  if (isAuthenticated) return true;

  // Local / self-hosted (CE) mode connects directly and needs no sign-in.
  if (ref.watch(settingsProvider).localServerEnabled) return true;

  // Check for anonymous tenant ID
  final anonymousTenantId = ref.watch(settingsProvider).anonymousTenantId;
  return anonymousTenantId != null && anonymousTenantId.isNotEmpty;
});

/// Provider for checking if we're in anonymous browsing mode
final isAnonymousBrowsingProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final anonymousTenantId = ref.watch(settingsProvider).anonymousTenantId;
  return !isAuthenticated && anonymousTenantId != null && anonymousTenantId.isNotEmpty;
});

/// Provider for getting the current ID token
///
/// Returns null if user is not authenticated.
/// Use this when making gRPC calls to Kumiho server.
final idTokenProvider = FutureProvider<String?>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.getIdToken();
});

/// Trigger that increments when we refresh the Firebase ID token.
///
/// Providers can watch this to rebuild any clients that cached the old token string.
final authTokenRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Background auto-refresh for Firebase ID tokens.
///
/// Firebase tokens are short-lived (~1h). The app previously built a client with a token
/// string and kept using it until it expired. This provider schedules a refresh before expiry.
final authTokenAutoRefreshProvider = Provider<void>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return;
  Timer? periodicTimer;
  Timer? initialCheckTimer;

  bool tokenExpiringSoon(String token, {Duration threshold = const Duration(minutes: 5)}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = json['exp'];
      if (exp is! num) return true;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      final now = DateTime.now().toUtc();
      return expiry.difference(now) <= threshold;
    } catch (_) {
      // If we can't parse, err on the side of refreshing later.
      return true;
    }
  }

  Future<void> refreshNow(User user, {required bool force}) async {
    try {
      // Only refresh if needed. This avoids expensive startup work on desktop.
      if (PerfLogger.enabled) {
        PerfLogger.log('authTokenAutoRefresh: refreshNow(force=$force) START');
      }

      final cached = await user.getIdToken(false);
      if (!force && cached != null && cached.isNotEmpty && !tokenExpiringSoon(cached)) {
        if (PerfLogger.enabled) {
          PerfLogger.log('authTokenAutoRefresh: refreshNow skipped (token not expiring soon)');
        }
        return;
      }

      await user.getIdToken(force);
      ref.read(authTokenRefreshTriggerProvider.notifier).state++;

      if (PerfLogger.enabled) {
        PerfLogger.log('authTokenAutoRefresh: refreshNow DONE (trigger bumped)');
      }
    } catch (e) {
      debugPrint('Failed to force-refresh ID token: $e');
    }
  }

  void stopTimers() {
    periodicTimer?.cancel();
    periodicTimer = null;
    initialCheckTimer?.cancel();
    initialCheckTimer = null;
  }

  // IMPORTANT: avoid creating another FirebaseAuth.authStateChanges listener.
  // We already have authStateProvider streaming auth state; listen to that
  // instead to reduce native listener fan-out on Windows.
  ref.listen<User?>(currentUserProvider, (prev, next) {
    stopTimers();
    final user = next;
    if (user == null) return;

    // Do not refresh immediately on startup; it can stall on desktop.
    // On Windows, be extra conservative and wait longer.
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final initialDelay = isWindows
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);

    initialCheckTimer = Timer(initialDelay, () {
      unawaited(refreshNow(user, force: false));
    });

    periodicTimer = Timer.periodic(const Duration(minutes: 45), (_) {
      unawaited(refreshNow(user, force: true));
    });
  }, fireImmediately: true);

  ref.onDispose(stopTimers);
});

/// State class for Kumiho session (includes CP token and discovery)
class KumihoSession {
  const KumihoSession({
    required this.user,
    this.controlPlaneToken,
    this.discoveryRecord,
    this.error,
  });

  final User user;
  final ControlPlaneToken? controlPlaneToken;
  final DiscoveryRecord? discoveryRecord;
  final String? error;

  bool get hasControlPlaneToken => controlPlaneToken?.isValid ?? false;
  bool get hasDiscovery => discoveryRecord != null;
  bool get isFullyAuthenticated => hasControlPlaneToken && hasDiscovery;

  /// Get the data plane URL for SDK connections
  String? get dataPlaneUrl => discoveryRecord?.serverUrl;

  /// Get the tenant ID
  String? get tenantId => discoveryRecord?.tenantId ?? controlPlaneToken?.tenantId;

  KumihoSession copyWith({
    User? user,
    ControlPlaneToken? controlPlaneToken,
    DiscoveryRecord? discoveryRecord,
    String? error,
  }) {
    return KumihoSession(
      user: user ?? this.user,
      controlPlaneToken: controlPlaneToken ?? this.controlPlaneToken,
      discoveryRecord: discoveryRecord ?? this.discoveryRecord,
      error: error,
    );
  }
}

/// Provider for the full Kumiho session (Firebase + Control Plane)
final kumihoSessionProvider = FutureProvider<KumihoSession?>((ref) async {
  // Depend on the auth state stream for rebuilds.
  // IMPORTANT (Windows): do not read FirebaseAuth.currentUser synchronously;
  // it can block the UI thread while the desktop SDK restores a persisted user.
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;

  PerfLogger.mark('kumihoSessionProvider.start');

  final cpService = ref.watch(controlPlaneServiceProvider);
  final settings = ref.watch(settingsProvider);

  try {
    // Get Firebase ID token
    // IMPORTANT: do NOT force-refresh at startup.
    // On desktop this can block for a long time (10s+), which makes the whole
    // app feel stalled. Use the cached token first, and only force-refresh on
    // real auth failures.
    var idToken = await PerfLogger.timeAsync(
      'kumihoSessionProvider.getIdToken(cached)',
      () => user.getIdToken(false),
    );
    if (idToken == null) {
      // Fallback: try a force refresh, but don't let it stall forever.
      idToken = await PerfLogger.timeAsync(
        'kumihoSessionProvider.getIdToken(forceRefresh_fallback)',
        () => user.getIdToken(true).timeout(const Duration(seconds: 8)),
      );
    }
    if (idToken == null) {
      return KumihoSession(user: user, error: 'Failed to get Firebase ID token');
    }
    final token = idToken;
    PerfLogger.mark('kumihoSessionProvider.gotIdToken');

    // Tenant discovery determines region routing. We must NOT hardcode the data-plane.
    // Use cached discovery immediately when valid; otherwise fetch discovery.
    final cachedDiscovery = await _loadCachedDiscoveryRecord();

    // IMPORTANT: authenticated discovery should NOT use the anonymous tenant ID.
    // Passing a tenant_hint can force the wrong tenant and cause tenant_not_found.
    final anonymousTenantId = settings.anonymousTenantId;
    if (anonymousTenantId != null && anonymousTenantId.isNotEmpty) {
      PerfLogger.log(
        'kumihoSessionProvider: ignoring anonymousTenantId for authenticated discovery',
      );
    }
    const String? tenantHint = null;

    DiscoveryRecord? discovery;
    String? discoveryError;

    if (cachedDiscovery != null) {
      discovery = cachedDiscovery;
      final cacheExpired = cachedDiscovery.cacheControl.isExpired;
      PerfLogger.log(
        'kumihoSessionProvider: using cached discovery '
        '(expired=$cacheExpired, expiresAt=${cachedDiscovery.cacheControl.expiresAt.toIso8601String()})',
      );

      // Refresh in background if the cache-control says we should, or if it's expired.
      // TEMPORARILY DISABLED for Windows startup debugging
      final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
      if (!isWindows && (cacheExpired || cachedDiscovery.cacheControl.shouldRefresh)) {
        unawaited(() async {
          try {
            final json = await _discoverTenantJsonInIsolate(
              baseUrl: KumihoConfig.controlPlaneUrl,
              firebaseIdToken: token,
              tenantHint: tenantHint,
              timeout: const Duration(seconds: 5),
            );
            final fresh = DiscoveryRecord.fromJson(json);
            await _saveCachedDiscoveryRecord(fresh);
            PerfLogger.log('kumihoSessionProvider: discovery cache refreshed');
          } catch (e) {
            PerfLogger.log('kumihoSessionProvider: discovery refresh failed: $e');
          }
        }());
      }
    } else {
      // No usable cache: block until we have discovery.
      try {
        if (PerfLogger.enabled) {
          PerfLogger.log('discovery source: network (no cache available)');
        }
        final json = await PerfLogger.timeAsync(
          'kumihoSessionProvider.discoverTenant',
          () => _discoverTenantJsonInIsolate(
            baseUrl: KumihoConfig.controlPlaneUrl,
            firebaseIdToken: token,
            tenantHint: tenantHint,
            timeout: const Duration(seconds: 10),
          ),
        );
        discovery = DiscoveryRecord.fromJson(json);
        await _saveCachedDiscoveryRecord(discovery);

        if (PerfLogger.enabled) {
          PerfLogger.log(
            'discovery fetched: network '
            '(expired=${discovery.cacheControl.isExpired}, '
            'expiresAt=${discovery.cacheControl.expiresAt.toIso8601String()})',
          );
        }
      } catch (e) {
        discoveryError = e.toString();
        final isTenantNotFound = discoveryError.contains('tenant_not_found');
        debugPrint('╔════════════════════════════════════════════════════════════');
        debugPrint('║ Tenant discovery failed!');
        debugPrint('║ Error: $e');
        if (isTenantNotFound) {
          debugPrint('║ The control-plane could not map this account to a tenant.');
          debugPrint('║ If you recently used anonymous browsing, clear any tenant');
          debugPrint('║ overrides and try again. Otherwise, your account may not');
          debugPrint('║ be linked to a tenant in the production database.');
        } else {
          debugPrint('║ This usually means your Firebase account is not linked to');
          debugPrint('║ a tenant in the production Kumiho database.');
        }
        debugPrint('╚════════════════════════════════════════════════════════════');
      }
    }

    // NOTE: We intentionally do not exchange for a Control Plane JWT on startup.
    // The browser currently uses the Firebase ID token for discovery, and the
    // previous eager exchange was frequently timing out and not being stored or
    // used (cpToken stayed null), adding noise without improving UX.
    final ControlPlaneToken? cpToken = null;

    // If both control-plane calls failed, report an error
    final sessionError = (discovery == null && discoveryError != null)
      ? 'Tenant discovery failed: $discoveryError'
      : null;

    return KumihoSession(
      user: user,
      controlPlaneToken: cpToken,
      discoveryRecord: discovery,
      error: sessionError,
    );
  } catch (e) {
    return KumihoSession(user: user, error: e.toString());
  }
});

/// Notifier for handling auth actions
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthNotifier(this._authService, this._cpService) : super(const AsyncValue.loading()) {
    _init();
  }

  final AuthService _authService;
  final ControlPlaneService _cpService;

  void _init() {
    _authService.authStateChanges.listen((user) {
      state = AsyncValue.data(user);
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      debugPrint('[Auth] Starting Google sign-in...');
      final credential = await _authService.signInWithGoogle();
      debugPrint('[Auth] Google sign-in success: ${credential.user?.email}');
      state = AsyncValue.data(credential.user);
    } catch (e, st) {
      debugPrint('[Auth] Google sign-in failed: $e');
      state = AsyncValue.error(e, st);
      rethrow; // Let UI display the error
    }
  }

  Future<void> signInWithGitHub() async {
    state = const AsyncValue.loading();
    try {
      debugPrint('[Auth] Starting GitHub sign-in...');
      final credential = await _authService.signInWithGitHub();
      debugPrint('[Auth] GitHub sign-in success: ${credential.user?.email}');
      state = AsyncValue.data(credential.user);
    } catch (e, st) {
      debugPrint('[Auth] GitHub sign-in failed: $e');
      state = AsyncValue.error(e, st);
      rethrow; // Let UI display the error
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      debugPrint('[Auth] Starting email sign-in for: $email');
      final credential = await _authService.signInWithEmail(email, password);
      debugPrint('[Auth] Email sign-in success: ${credential.user?.email}');
      state = AsyncValue.data(credential.user);
    } catch (e, st) {
      debugPrint('[Auth] Email sign-in failed: $e');
      state = AsyncValue.error(e, st);
      rethrow; // Let UI display the error
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Provider for AuthNotifier
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
  final authService = ref.watch(authServiceProvider);
  final cpService = ref.watch(controlPlaneServiceProvider);
  return AuthNotifier(authService, cpService);
});
