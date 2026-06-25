// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';
import 'package:kumiho/kumiho.dart' hide DiscoveryRecord;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';
import 'settings_provider.dart';
import 'browser_provider.dart';
import '../services/control_plane_service.dart';
import '../core/constants/firebase_config.dart';
import '../core/perf/perf_logger.dart';
import '../models/media_item.dart';
import '../models/list_view_models.dart';

/// Isolate entry point for projects fetch.
///
/// This runs entirely in a background isolate so TLS handshakes and gRPC I/O
/// never block the Flutter UI thread.
Future<List<String>> _getProjectsJsonInIsolate(Map<String, Object?> args) async {
  final host = args['host'] as String;
  final port = args['port'] as int;
  final secure = args['secure'] as bool;
  final token = args['token'] as String;
  final timeoutMs = args['timeoutMs'] as int;
  final tenantId = args['tenantId'] as String?;

  // Create the gRPC client *inside* the isolate so all network I/O (including
  // the TLS handshake) happens off the main Flutter UI thread.
  final client = KumihoClient(
    host: host,
    port: port,
    secure: secure,
    token: token,
    tenantId: tenantId,
  );

  try {
    final response = await client.stub.getProjects(
      GetProjectsRequest(),
      options: client.mergeOptions(
        CallOptions(timeout: Duration(milliseconds: timeoutMs)),
      ),
    );
    return response.projects.map((p) => p.writeToJson()).toList(growable: false);
  } finally {
    // Best-effort shutdown; not awaited.
    client.shutdown();
  }
}

({String host, int port, bool secure}) _resolveGrpcEndpointFromDiscovery(
  DiscoveryRecord discovery,
) {
  // Prefer grpc_authority if provided. It may be:
  // - "host:port"
  // - "host"
  // - "https://host:port" (rare)
  final serverUri = Uri.tryParse(discovery.serverUrl);
  final serverSecure = serverUri?.scheme.toLowerCase() == 'https';
  final serverDefaultPort = serverSecure ? 443 : 80;

  final grpcAuthority = discovery.grpcAuthority;
  if (grpcAuthority != null && grpcAuthority.trim().isNotEmpty) {
    final raw = grpcAuthority.trim();
    final asUri = raw.contains('://') ? Uri.tryParse(raw) : null;
    if (asUri != null && asUri.host.isNotEmpty) {
      final secure = asUri.scheme.toLowerCase() == 'https' || serverSecure;
      final port = asUri.hasPort && asUri.port != 0
          ? asUri.port
          : (secure ? 443 : 80);
      return (host: asUri.host, port: port, secure: secure);
    }

    final parts = raw.split(':');
    final host = parts[0];
    final port = parts.length > 1
        ? (int.tryParse(parts[1]) ?? serverDefaultPort)
        : (serverUri?.hasPort == true && serverUri!.port != 0
            ? serverUri.port
            : serverDefaultPort);
    return (host: host, port: port, secure: serverSecure);
  }

  // Fall back to server_url.
  final uri = Uri.parse(discovery.serverUrl);
  final secure = uri.scheme.toLowerCase() == 'https';
  final port = uri.hasPort && uri.port != 0 ? uri.port : (secure ? 443 : 80);
  return (host: uri.host, port: port, secure: secure);
}

bool _isUnauthenticatedGrpcError(Object error) {
  return error is GrpcError && error.code == StatusCode.unauthenticated;
}

bool _isTransportGrpcError(Object error) {
  if (error is GrpcError) {
    if (error.code == StatusCode.unavailable ||
        error.code == StatusCode.deadlineExceeded) {
      return true;
    }
    final msg = error.message ?? '';
    if (msg.contains('HandshakeException') || msg.contains('Error connecting')) {
      return true;
    }
  }
  return false;
}

Future<void> _forceRefreshAuthToken(Ref ref) async {
  final authService = ref.read(authServiceProvider);
  final token = await authService.getIdToken(forceRefresh: true);
  if (token == null || token.isEmpty) return;

  ref.read(authTokenRefreshTriggerProvider.notifier).state++;
}

List<T> _asList<T>(Object? value) {
  if (value == null) return <T>[];
  if (value is List<T>) return value;
  if (value is Iterable) return List<T>.from(value);
  throw Exception('Unexpected result type: ${value.runtimeType}');
}

Future<List<ItemResponse>> _itemSearchCompat(
  KumihoClient client,
  String contextFilter,
  String nameFilter,
  String kindFilter, {
  required bool includeDeprecated,
}) async {
  try {
    final res = await Function.apply(
      client.itemSearch,
      [contextFilter, nameFilter, kindFilter],
      {#includeDeprecated: includeDeprecated},
    );
    return _asList<ItemResponse>(res);
  } catch (_) {
    final res = await Function.apply(
      client.itemSearch,
      [contextFilter, nameFilter, kindFilter],
    );
    return _asList<ItemResponse>(res);
  }
}

Future<List<Item>> _getProjectItemsCompat(Project project, {required bool includeDeprecated}) async {
  try {
    final res = await Function.apply(
      project.getItems,
      const [],
      {#includeDeprecated: includeDeprecated},
    );
    return _asList<Item>(res);
  } catch (_) {
    final res = await Function.apply(project.getItems, const []);
    return _asList<Item>(res);
  }
}

Future<List<Revision>> _getRevisionsCompat(Item item, {required bool includeDeprecated}) async {
  try {
    final res = await Function.apply(
      item.getRevisions,
      const [],
      {#includeDeprecated: includeDeprecated},
    );
    return _asList<Revision>(res);
  } catch (_) {
    final res = await Function.apply(item.getRevisions, const []);
    return _asList<Revision>(res);
  }
}

final _kumihoClientInstanceProvider = StateProvider<KumihoClient?>((ref) => null);
final _kumihoClientSignatureProvider = StateProvider<String?>((ref) => null);
final _kumihoAnonDiscoveryLastAttemptMsProvider = StateProvider<int?>((ref) => null);

/// On Windows, defer creating KumihoClient until after first isolate projects fetch.
/// This avoids blocking the UI thread on TLS handshake during startup.
final _kumihoClientDeferredProvider = StateProvider<bool>((ref) {
  // Start deferred on Windows; becomes false after startup settles or first successful fetch.
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
});

/// Provider that settles after the Windows startup grace period.
/// On non-Windows, this completes immediately.
final _windowsStartupSettledProvider = FutureProvider<void>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  // Wait for any native initialization stalls to complete.
  // This is a workaround for ~20 second stalls observed on Windows startup
  // that occur in native code (Firebase SDK, gRPC TLS, Flutter engine).
  await Future<void>.delayed(const Duration(seconds: 25));
  PerfLogger.mark('Windows startup grace period complete');
});

const int _kumihoAnonDiscoveryRetryBackoffMs = 60 * 1000;
const int _kumihoAnonDiscoveryStartupGraceMs = 3000;

final _kumihoAnonStartupGraceProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(
    const Duration(milliseconds: _kumihoAnonDiscoveryStartupGraceMs),
  );
});

final _projectsCacheProvider = StateProvider<List<Project>>((ref) => const []);
final _projectsCacheAtMsProvider = StateProvider<int?>((ref) => null);

const int _projectsCacheTtlMs = 2 * 60 * 1000;

/// Stable cache for the local / self-hosted (CE) client, kept outside the
/// provider graph so it can be set during build without tripping Riverpod's
/// "modify a provider during build" / "didChangeDependency" assertions.
KumihoClient? _localServerClient;
String? _localServerSig;

/// Provider for the Kumiho gRPC client
///
/// The client is created after successful authentication and discovery.
/// Also supports anonymous browsing with tenant ID from settings.
/// Returns null if user is not authenticated and no anonymous tenant configured.
final kumihoClientProvider = FutureProvider<KumihoClient?>((ref) async {
  // Local / self-hosted (CE) mode: connect directly to a self-hosted Kumiho
  // server, bypassing Firebase sign-in and control-plane discovery. Resolve it
  // FIRST — before watching the auth stream — so that in CE mode this provider
  // depends only on settings and does NOT rebuild on every auth-stream emission
  // at startup. Each such rebuild re-emits this client future and invalidates
  // the in-flight projects fetch ("didChangeDependency"), which loops the UI.
  // CE serves plaintext gRPC on loopback and ignores auth tokens, so there is
  // no TLS handshake to defer and nothing to discover.
  final settings = ref.watch(settingsProvider);
  if (settings.localServerEnabled) {
    final host = settings.localServerHost;
    final port = settings.localServerPort;
    final secure = settings.localServerSecure;
    final sig = 'local|$host:$port|$secure';
    // Reuse one stable client. Cache in a module-level variable, NOT the
    // StateProviders: modifying a provider during this provider's build throws,
    // and doing it after an await races with the auth stream re-emitting at
    // startup (which churns the client and loops the projects fetch). A plain
    // cache sidesteps both.
    if (_localServerSig == sig && _localServerClient != null) {
      return _localServerClient;
    }
    if (PerfLogger.enabled) {
      PerfLogger.log('kumihoClientProvider: local/CE mode -> $host:$port secure=$secure');
    }
    final client = KumihoClient(
      host: host,
      port: port,
      secure: secure,
      token: '', // CE ignores auth; empty token avoids env/file auto-load.
    );
    _localServerClient = client;
    _localServerSig = sig;
    return client;
  }

  // --- Cloud (Firebase auth + control-plane discovery) path below ---
  // If auth is still resolving at startup, don't start anonymous public
  // discovery yet. Wait until we definitively know whether the user is
  // signed in or signed out.
  final authState = ref.watch(authStateProvider);
  final authSettled = authState.hasValue || authState.hasError;

  // IMPORTANT (Windows): avoid synchronous FirebaseAuth.currentUser access.
  // On desktop we've observed it can block the UI thread for many seconds
  // while the SDK restores the persisted user.
  final user = authState.valueOrNull;
  final hasSyncUser = user != null;

  final cached = ref.read(_kumihoClientInstanceProvider);
  final cachedSig = ref.read(_kumihoClientSignatureProvider);

  // CRITICAL (Windows): do not touch session discovery or Firebase token APIs
  // during the deferred startup window. Even seemingly-async calls like
  // user.getIdToken() have been observed to block the UI isolate for ~20-30s
  // on Windows startup.
  final deferredStartup = ref.read(_kumihoClientDeferredProvider);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && deferredStartup) {
    if (PerfLogger.enabled) {
      PerfLogger.log('kumihoClientProvider: early-return (deferred Windows startup)');
    }
    // If we previously had an authenticated client instance, keep using it
    // while deferred. Otherwise return null and let isolate-based fetch paths
    // handle startup.
    return cached;
  }

  if (!authSettled && !hasSyncUser) {
    // If we previously had an authenticated client instance, keep using it
    // while auth settles; otherwise, return null (no client yet).
    if (cachedSig != null && cachedSig.startsWith('auth|')) {
      return cached;
    }
    return null;
  }

  final session = await ref.watch(kumihoSessionProvider.future);

  // Rebuild the client when we force-refresh the token.
  ref.watch(authTokenRefreshTriggerProvider);
  String? idToken;
  if (user != null) {
    try {
      idToken = await user.getIdToken(false);
    } catch (_) {
      idToken = null;
    }
  }

  if (PerfLogger.enabled) {
    PerfLogger.log(
      'kumihoClientProvider(+${PerfLogger.sinceStartMs()}ms): authSettled=$authSettled hasSyncUser=$hasSyncUser '
      'session=${session != null} idToken=${idToken != null} '
      'anonTenant=${settings.anonymousTenantId?.isNotEmpty == true}',
    );
  }

  // If authenticated with session, use that
  if (session != null && idToken != null) {
    final hasEndpoint =
        KumihoConfig.dataPlaneUrlOverride != null || session.discoveryRecord != null;
    if (!hasEndpoint) {
      if (PerfLogger.enabled) {
        PerfLogger.log(
          'kumihoClientProvider: waiting for tenant discovery (set DATA_PLANE_URL to bypass)',
        );
      }
      return null;
    }

    // On Windows, defer creating the KumihoClient to avoid blocking the UI
    // thread on TLS handshake during startup. The projects fetch will use an
    // isolate that creates its own client. After the first successful fetch,
    // we create the main-thread client for other operations.
    final deferred = ref.read(_kumihoClientDeferredProvider);
    if (deferred) {
      if (PerfLogger.enabled) {
        PerfLogger.log(
          'kumihoClientProvider: deferring client creation (Windows startup)',
        );
      }
      // Return cached if available; otherwise null (projects fetch uses isolate).
      return cached;
    }

    final sig = 'auth|${session.discoveryRecord?.grpcAuthority ?? session.discoveryRecord?.serverUrl ?? 'fallback'}';
    final shouldRecreate = cached == null || cachedSig != sig;

    final client = shouldRecreate ? _createClientFromSession(session, idToken) : cached;
    // Keep the same client instance and update token in-place so existing
    // model objects (Project/Space/etc.) keep working after refresh.
    client!.token = idToken;

    if (shouldRecreate) {
      ref.read(_kumihoClientInstanceProvider.notifier).state = client;
      ref.read(_kumihoClientSignatureProvider.notifier).state = sig;
    }

    return client;
  }
  
  // If not authenticated, check for anonymous tenant browsing
  final anonymousTenantId = settings.anonymousTenantId;
  if (!hasSyncUser && anonymousTenantId != null && anonymousTenantId.isNotEmpty) {
    // On Windows, defer creating the KumihoClient to avoid blocking the UI
    // thread during startup (same as authenticated path).
    final deferred = ref.read(_kumihoClientDeferredProvider);
    if (deferred) {
      if (PerfLogger.enabled) {
        PerfLogger.log(
          'kumihoClientProvider: deferring anonymous client creation (Windows startup)',
        );
      }
      return cached;
    }

    // On desktop startup, Firebase may surface a persisted user a moment after
    // the auth stream initially reports null. Avoid firing anonymous public
    // discovery during that window.
    final firebaseEnabled = ref.watch(firebaseEnabledProvider);
    if (firebaseEnabled) {
      final grace = ref.watch(_kumihoAnonStartupGraceProvider);
      if (!grace.hasValue) {
        if (PerfLogger.enabled) {
          PerfLogger.log(
            'kumihoClientProvider: skipping anonymous discovery during startup grace',
          );
        }
        return null;
      }
    }

    final sig = 'anon|$anonymousTenantId';

    // If public discovery failed recently, avoid retrying on every rebuild.
    // Without this, a null cached client causes an immediate retry loop.
    final lastAttemptMs = ref.read(_kumihoAnonDiscoveryLastAttemptMsProvider);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (cachedSig == sig && cached == null && lastAttemptMs != null) {
      final elapsedMs = nowMs - lastAttemptMs;
      if (elapsedMs >= 0 && elapsedMs < _kumihoAnonDiscoveryRetryBackoffMs) {
        return null;
      }
    }

    // Reuse previously created anonymous client if it's for the same tenant.
    if (cachedSig == sig && cached != null) {
      return cached;
    }

    ref.read(_kumihoAnonDiscoveryLastAttemptMsProvider.notifier).state = nowMs;
    if (PerfLogger.enabled) {
      PerfLogger.log('kumihoClientProvider: attempting anonymous discovery (tenant=$anonymousTenantId)');
    }
    final client = await _createAnonymousClient(anonymousTenantId);
    // Cache the signature even when client is null so we can apply backoff.
    ref.read(_kumihoClientInstanceProvider.notifier).state = client;
    ref.read(_kumihoClientSignatureProvider.notifier).state = sig;
    return client;
  }

  // Signed out / no anonymous mode: clear cached client.
  if (cached != null) {
    ref.read(_kumihoClientInstanceProvider.notifier).state = null;
    ref.read(_kumihoClientSignatureProvider.notifier).state = null;
  }
  
  return null;
});

/// Create client from authenticated session
KumihoClient _createClientFromSession(KumihoSession session, String idToken) {
  PerfLogger.mark('_createClientFromSession: start');
  String host;
  int port;
  bool secure;

  Uri parseUrl(String raw) {
    final normalized = raw.contains('://') ? raw : 'http://$raw';
    return Uri.parse(normalized);
  }

  final dataPlaneOverride = KumihoConfig.dataPlaneUrlOverride;
  if (dataPlaneOverride != null) {
    final uri = parseUrl(dataPlaneOverride);
    host = uri.host;
    port = uri.hasPort && uri.port != 0
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    secure = uri.scheme == 'https';

    return KumihoClient(
      host: host,
      port: port,
      token: idToken,
      secure: secure,
    );
  }

  if (session.discoveryRecord != null) {
    final discovery = session.discoveryRecord!;

    final resolved = _resolveGrpcEndpointFromDiscovery(discovery);
    host = resolved.host;
    port = resolved.port;
    secure = resolved.secure;

    if (PerfLogger.enabled) {
      PerfLogger.log(
        'createClientFromSession: resolved grpc endpoint '
        '$host:$port secure=$secure '
        '(serverUrl=${discovery.serverUrl}, grpcAuthority=${discovery.grpcAuthority})',
      );
    }
  } else {
    // Dev-only fallback. In production/staging we require control-plane discovery
    // (or an explicit DATA_PLANE_URL override) to determine the correct region.
    host = 'localhost';
    port = 50051;
    secure = false;
  }

  PerfLogger.mark('_createClientFromSession: creating KumihoClient');
  final client = KumihoClient(
    host: host,
    port: port,
    token: idToken,
    secure: secure,
  );
  PerfLogger.mark('_createClientFromSession: KumihoClient created');
  return client;
}

/// Top-level function for running anonymous discovery in a background isolate.
/// Must be top-level (not a closure) to be passed to compute().
/// 
/// Parameters: [controlPlaneUrl, tenantId]
/// Returns: JSON map of DiscoveryRecord or null on failure.
Future<Map<String, dynamic>?> _discoverPublicTenantInIsolate(
    List<String> params) async {
  final controlPlaneUrl = params[0];
  final tenantId = params[1];

  final controlPlane = ControlPlaneService(controlPlaneUrl: controlPlaneUrl);
  try {
    final discovery = await controlPlane.discoverPublicTenant(tenantId);
    return discovery.toJson();
  } catch (e) {
    // Return null on any error - caller will handle
    return null;
  }
}

/// Create anonymous client for public tenant browsing
/// The tenant ID is passed as x-tenant-id header for the server to filter results.
/// Uses control-plane discovery to get the correct data plane endpoint.
/// 
/// On Windows, the HTTP discovery call is run in a background isolate to avoid
/// blocking the main thread during native DNS/TLS operations.
Future<KumihoClient?> _createAnonymousClient(String tenantId) async {
  Uri parseUrl(String raw) {
    final normalized = raw.contains('://') ? raw : 'http://$raw';
    return Uri.parse(normalized);
  }

  final dataPlaneOverride = KumihoConfig.dataPlaneUrlOverride;
  if (dataPlaneOverride != null) {
    final uri = parseUrl(dataPlaneOverride);
    final host = uri.host;
    final port = uri.hasPort && uri.port != 0
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final secure = uri.scheme == 'https';

    return KumihoClient(
      host: host,
      port: port,
      secure: secure,
      token: '', // Empty token to prevent auto-loading from env/cache
      tenantId: tenantId, // Required for server-side public access routing
    );
  }

  try {
    DiscoveryRecord discovery;

    // On Windows, run discovery in background isolate to avoid main thread
    // blocking on native DNS/TLS operations in the HTTP client.
    if (defaultTargetPlatform == TargetPlatform.windows) {
      PerfLogger.mark('createAnonymousClient: starting compute() for discovery');

      // Use compute() with a tight timeout - if native layer is blocking,
      // we don't want to wait forever.
      final discoveryJson = await compute(
        _discoverPublicTenantInIsolate,
        [KumihoConfig.controlPlaneUrl, tenantId],
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Anonymous discovery timed out (5s outer timeout)');
          return null;
        },
      );

      PerfLogger.mark('createAnonymousClient: compute() returned');

      if (discoveryJson == null) {
        debugPrint('Anonymous discovery failed or timed out');
        return null;
      }

      discovery = DiscoveryRecord.fromJson(discoveryJson);
    } else {
      // On other platforms, run directly on main thread
      final controlPlane = ControlPlaneService();
      discovery = await controlPlane.discoverPublicTenant(tenantId);
    }

    final resolved = _resolveGrpcEndpointFromDiscovery(discovery);
    final host = resolved.host;
    final port = resolved.port;
    final secure = resolved.secure;

    if (PerfLogger.enabled) {
      PerfLogger.log(
        'createAnonymousClient: resolved grpc endpoint '
        '$host:$port secure=$secure '
        '(serverUrl=${discovery.serverUrl}, grpcAuthority=${discovery.grpcAuthority})',
      );
    }

    return KumihoClient(
      host: host,
      port: port,
      secure: secure,
      token: '', // Empty token to prevent auto-loading from env/cache
      tenantId: tenantId, // Required for server-side public access routing
    );
  } catch (e) {
    debugPrint('Failed to create anonymous client: $e');
    return null;
  }
}

/// Provider for list of projects from the tenant
final projectsProvider = AsyncNotifierProvider<ProjectsNotifier, List<Project>>(
  ProjectsNotifier.new,
);

class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    PerfLogger.mark('projectsProvider.build() START');
    // Re-fetch projects when user triggers a manual refresh (e.g., toolbar refresh)
    final refreshTick = ref.watch(kumihoRefreshTriggerProvider);
    // If the user has explicitly selected a project, we must ensure projects
    // are fetched with a real client (so Project.getSpaces() can work).
    final selectedProjectName = ref.watch(selectedProjectNameProvider);

    // Local / self-hosted (CE) mode connects over plaintext loopback gRPC,
    // which has no TLS-handshake stall and no discovery record. Skip the
    // Windows startup deferral and the discovery-based isolate fetch path.
    final localMode = ref.watch(settingsProvider).localServerEnabled;

    final cached = ref.watch(_projectsCacheProvider);
    final cachedAtMs = ref.watch(_projectsCacheAtMsProvider);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Capture the cache controllers up front (before any await) so the write
    // after the fetch completes does NOT call a ref function. Calling ref after
    // an await throws "didChangeDependency" if any watched provider notified
    // mid-fetch — which happens in CE mode, where the loopback fetch returns in
    // a few ms while startup providers are still settling, leaving the cache
    // perpetually unwritten and the fetch looping every frame.
    final projectsCacheCtrl = ref.read(_projectsCacheProvider.notifier);
    final projectsCacheAtCtrl = ref.read(_projectsCacheAtMsProvider.notifier);

    final isCacheFresh = cachedAtMs != null &&
        nowMs - cachedAtMs >= 0 &&
        nowMs - cachedAtMs < _projectsCacheTtlMs;

    // If we have cached data and it’s still fresh, avoid hitting the network.
    // This dramatically reduces perceived latency and prevents repeated fetches
    // on rebuilds.
    // If there’s no explicit refresh happening and cache is fresh, use it.
    // Note: when the refresh trigger increments, build reruns and we fetch.
    final cachedHasClient = cached.isNotEmpty && cached.every((p) => p.client != null);
    if (cachedHasClient && isCacheFresh) {
      return cached;
    }

    // CRITICAL WINDOWS WORKAROUND: On Windows, native operations (gRPC TLS,
    // http DNS resolution, compute() isolate spawning) can block the main thread
    // for 20+ seconds during startup. To avoid this, we defer ALL network
    // operations during the startup grace period and rely on cached project names.
    // After the grace period, a rebuild will trigger the actual fetch.
    final deferred = ref.watch(_kumihoClientDeferredProvider);
    if (deferred && !localMode) {
      final userInitiated = refreshTick > 0 || selectedProjectName != null;
      // Only defer if we have something meaningful to show. If the cache is
      // empty, deferring would break project selection and space loading.
      if (!userInitiated && cachedHasClient) {
        PerfLogger.mark('projectsProvider: DEFERRED (Windows startup grace)');
        // Schedule a rebuild after the grace period to fetch fresh data.
        unawaited(Future.delayed(const Duration(seconds: 26), () {
          if (ref.read(_kumihoClientDeferredProvider)) {
            ref.read(_kumihoClientDeferredProvider.notifier).state = false;
          }
          ref.invalidateSelf();
        }));
        return cached;
      }

      // User action (or missing cache): end deferral immediately so we can
      // fetch real Project objects and allow getSpaces() to work.
      ref.read(_kumihoClientDeferredProvider.notifier).state = false;
    }

    // If we have cached data but it’s stale, or the user triggered a refresh,
    // we still keep showing cached data while loading (Riverpod preserves the
    // previous value during refresh), but we do fetch fresh data.
    PerfLogger.mark('projectsProvider: awaiting kumihoClientProvider');
    final client = await ref.watch(kumihoClientProvider.future);
    PerfLogger.mark('projectsProvider: got client');
    if (client == null) {
      // Keep whatever cached data we had, but never return client-less Projects
      // since calling Project.getSpaces()/getItems() would crash.
      return cachedHasClient ? cached : const <Project>[];
    }

    /// Fetch projects, preferring a background isolate on Windows to avoid
    /// blocking the Flutter UI thread during TLS handshakes and gRPC I/O.
    ///
    /// [c] can be null on Windows startup when client creation is deferred.
    Future<List<Project>> fetchProjects(
      KumihoClient? c,
      String label, {
      Duration timeout = const Duration(seconds: 12),
    }) async {
      final useIsolate =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !localMode;

      final projects = await PerfLogger.timeAsync(
        label,
        () async {
          // On Windows, the grpc/TLS handshake can sometimes block the UI
          // isolate for seconds. Run the RPC in a background isolate and return
          // protobufs via JSON to keep frames responsive.
          if (useIsolate) {
            final session = await ref.read(kumihoSessionProvider.future);
            final discovery = session?.discoveryRecord;
            if (discovery == null || session == null) {
              return const <Project>[];
            }
            final resolved = _resolveGrpcEndpointFromDiscovery(discovery);

            // Get token from session if client is null (deferred startup).
            final token = c?.token ?? await session.user.getIdToken(false) ?? '';
            final tenantId = c?.tenantId ?? discovery.tenantId;

            // Ensure returned Projects always have a non-null client attached.
            // (Project/Space/Item methods call client.getChildSpaces/itemSearch.)
            final effectiveClient = c ??
                KumihoClient(
                  host: resolved.host,
                  port: resolved.port,
                  secure: resolved.secure,
                  token: token,
                  tenantId: tenantId,
                );

            // Use compute() to ensure the isolate callback is a top-level
            // function. This avoids unsendable captured context errors.
            final args = <String, Object?>{
              'host': resolved.host,
              'port': resolved.port,
              'secure': resolved.secure,
              'token': token,
              'tenantId': tenantId,
              'timeoutMs': timeout.inMilliseconds,
            };

            // Wrap compute() in an outer timeout so the UI thread never waits
            // longer than the requested deadline even if the isolate or TLS
            // handshake hangs indefinitely.
            PerfLogger.mark('projectsProvider: starting compute() for isolate fetch');
            final jsonList = await compute(_getProjectsJsonInIsolate, args)
                .timeout(timeout + const Duration(seconds: 2));
            PerfLogger.mark('projectsProvider: compute() returned ${jsonList.length} projects');

            // NOTE: Do NOT set _kumihoClientDeferredProvider to false here!
            // Since projectsProvider watches _kumihoClientDeferredProvider,
            // changing it here would trigger an immediate rebuild, causing an
            // infinite loop. The deferred state is managed by the scheduled
            // timer in build() or by the gracePeriod completing naturally.

            // Return projects immediately using the existing client (may be null).
            // The Project model needs a client for operations but since we're
            // just listing projects, null is acceptable for now. When user
            // interacts with a project, the client will be ready.
            return jsonList
              .map((json) => Project(ProjectResponse.fromJson(json), effectiveClient))
                .toList(growable: false);
          }

          // Non-Windows: do a direct unary call with a real gRPC deadline.
          final response = await c!.stub.getProjects(
            GetProjectsRequest(),
            options: c.mergeOptions(CallOptions(timeout: timeout)),
          );
          return response.projects
              .map((p) => Project(p, c))
              .toList(growable: false);
        },
        fields: {
          'timeoutMs': timeout.inMilliseconds,
          if (useIsolate) 'mode': 'isolate',
        },
      );
      // IMPORTANT: Only update the cache when we have actual projects.
      // Since projectsProvider watches _projectsCacheProvider, updating it
      // with an empty list would trigger an infinite rebuild loop.
      if (projects.isNotEmpty) {
        projectsCacheCtrl.state = projects;
        projectsCacheAtCtrl.state = DateTime.now().millisecondsSinceEpoch;
      }
      return projects;
    }

    /// Retry projects fetch using only session/discovery info so we do NOT
    /// create a new KumihoClient on the main isolate (which would block on TLS).
    Future<List<Project>?> retryWithNewChannel(String reason) async {
      if (PerfLogger.enabled) {
        PerfLogger.log('projectsProvider: retrying with new channel ($reason)');
      }

      // On Windows, avoid creating a KumihoClient on the main isolate at all.
      // The TLS handshake can block. Instead, pass session/discovery info to
      // fetchProjects which will create the client inside a background isolate.
      final useIsolate =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !localMode;

      if (useIsolate) {
        // On Windows, the isolate does all gRPC work. We can pass null client;
        // fetchProjects will get session/discovery/token directly.
        try {
          return await fetchProjects(
            null, // Client created in isolate or after fetch completes.
            'projectsProvider.projects(retry_new_channel)',
            timeout: const Duration(seconds: 12),
          );
        } catch (e) {
          if (PerfLogger.enabled) {
            PerfLogger.log('projectsProvider: retry failed: $e');
          }
          return null;
        }
      }

      // Force the gRPC client/channel to be recreated (non-Windows path, or
      // when there's no existing client).
      ref.read(_kumihoClientInstanceProvider.notifier).state = null;
      ref.read(_kumihoClientSignatureProvider.notifier).state = null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final newClient = await ref.read(kumihoClientProvider.future);
      if (newClient == null) return null;
      try {
        return await fetchProjects(
          newClient,
          'projectsProvider.projects(retry_new_channel)',
          timeout: const Duration(seconds: 12),
        );
      } catch (e) {
        if (PerfLogger.enabled) {
          PerfLogger.log('projectsProvider: retry failed: $e');
        }
        return null;
      }
    }

    // On Windows we've observed the *first* authenticated gRPC call after
    // startup occasionally stalling for ~20s before failing, while a fresh
    // channel succeeds quickly. To keep the UI responsive and get projects
    // loaded fast, prefer a fresh channel on the initial fetch.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && cached.isEmpty && !localMode) {
      final warmed = await retryWithNewChannel('initial_windows_warm_channel');
      if (warmed != null && warmed.isNotEmpty) return warmed;
      // If retry failed or returned empty, and cache is also empty, don't
      // fall through to another fetch that will likely also fail.
      // Return cached (empty) to avoid hammering the server or causing
      // infinite rebuild loops.
      if (PerfLogger.enabled) {
        PerfLogger.log('projectsProvider: Windows warm channel failed/empty, using cached');
      }
      return cached;
    }

    try {
      return await fetchProjects(client, 'projectsProvider.client.projects');
    } catch (e) {
      if (_isUnauthenticatedGrpcError(e)) {
        await _forceRefreshAuthToken(ref);
        final refreshedClient = await ref.read(kumihoClientProvider.future);
        if (refreshedClient == null) return cached;
        try {
          return await fetchProjects(
            refreshedClient,
            'projectsProvider.projects(after_refresh)',
          );
        } catch (e2) {
          debugPrint('Failed to fetch projects after token refresh: $e2');
          return cached;
        }
      }

      // Common on Windows when the first TLS connection is flaky. Recreate the
      // channel once and retry quickly rather than stalling for 20s+.
      if (_isTransportGrpcError(e) || e is TimeoutException) {
        final retry = await retryWithNewChannel(e.toString());
        if (retry != null) return retry;
      }

      debugPrint('Failed to fetch projects: $e');
      return cached;
    }
  }
}

/// Provider for project names (for dropdown)
final projectNamesMemoryCacheProvider = StateProvider<List<String>>(
  (ref) => const <String>[],
);

final projectNamesProvider = FutureProvider<List<String>>((ref) async {
  const cacheKey = 'kumiho.projectNames.v1';

  // Load cached names quickly so the dropdown can render without waiting for
  // auth/session/projects network calls.
  final swPrefs = Stopwatch()..start();
  final prefs = await SharedPreferences.getInstance();
  if (PerfLogger.enabled) {
    PerfLogger.log('projectNamesProvider: prefs.getInstance ${swPrefs.elapsedMilliseconds}ms');
  }
  final cachedNames = prefs.getStringList(cacheKey) ?? const <String>[];

  // Seed an in-memory cache so widgets can show names even while this provider
  // is still in the "loading" state during startup.
  final memory = ref.read(projectNamesMemoryCacheProvider.notifier);
  if (memory.state.isEmpty && cachedNames.isNotEmpty) {
    memory.state = cachedNames;
  }

  final projectsAsync = ref.watch(projectsProvider);
  final projects = projectsAsync.valueOrNull;
  // If projects aren't ready yet, or if the projects provider emitted an empty
  // list during startup (e.g. because the gRPC client is still null), keep
  // showing the cached names. This prevents the UI from briefly clearing the
  // dropdown and overwriting the on-disk cache with an empty list.
  if (projects == null) {
    if (PerfLogger.enabled) {
      PerfLogger.log(
        'projectNamesProvider: cached=${cachedNames.length} (projects not ready)',
      );
    }
    if (cachedNames.isNotEmpty) {
      memory.state = cachedNames;
    }
    return cachedNames;
  }

  if (projects.isEmpty && cachedNames.isNotEmpty) {
    if (PerfLogger.enabled) {
      PerfLogger.log(
        'projectNamesProvider: using cached=${cachedNames.length} (projects empty during startup)',
      );
    }
    memory.state = cachedNames;
    return cachedNames;
  }

  final names = projects.map((p) => p.name).toList(growable: false);
  memory.state = names;
  // Avoid clobbering the cache with an empty list unless we truly have no
  // cached value.
  if (names.isNotEmpty || cachedNames.isEmpty) {
    await prefs.setStringList(cacheKey, names);
  }

  if (PerfLogger.enabled) {
    PerfLogger.log('projectNamesProvider: ${names.length} projects');
  }
  return names;
});

/// State for currently selected project
final selectedProjectNameProvider = StateProvider<String?>((ref) => null);

/// Provider for the currently selected Project object
final selectedProjectProvider = FutureProvider<Project?>((ref) async {
  final projectName = ref.watch(selectedProjectNameProvider);
  if (projectName == null) return null;

  final projects = await ref.watch(projectsProvider.future);
  try {
    final project = projects.firstWhere((p) => p.name == projectName);
    if (project.client != null) return project;

    // Defensive: if a client-less Project slipped through (e.g. old cache),
    // refetch just this Project using the active client.
    final client = await ref.watch(kumihoClientProvider.future);
    if (client == null) return null;
    return await client.project(projectName);
  } catch (_) {
    return null;
  }
});

/// Provider for spaces within the selected project
final spacesProvider = FutureProvider<List<Space>>((ref) async {
  final project = await ref.watch(selectedProjectProvider.future);
  if (project == null) {
    return [];
  }

  try {
    return await PerfLogger.timeAsync(
      'spacesProvider.project.getSpaces',
      () => project.getSpaces(),
      fields: {'project': project.name},
    );
  } catch (e) {
    debugPrint('Failed to fetch spaces: $e');
    return [];
  }
});

/// Provider for space names (for dropdown)
final spaceNamesProvider = FutureProvider<List<String>>((ref) async {
  final spaces = await ref.watch(spacesProvider.future);
  return spaces.map((s) => s.name).toList();
});

/// State for currently selected space
final selectedSpaceNameProvider = StateProvider<String?>((ref) => null);

/// Provider for the currently selected Space object
final selectedSpaceProvider = FutureProvider<Space?>((ref) async {
  final spaceName = ref.watch(selectedSpaceNameProvider);
  if (spaceName == null) return null;

  final spaces = await ref.watch(spacesProvider.future);
  try {
    return spaces.firstWhere((s) => s.name == spaceName);
  } catch (_) {
    return null;
  }
});

/// Provider for child spaces (sub-folders)
final childSpacesProvider = FutureProvider<List<Space>>((ref) async {
  final space = await ref.watch(selectedSpaceProvider.future);
  if (space == null) return [];

  try {
    return await space.getChildSpaces();
  } catch (e) {
    debugPrint('Failed to fetch child spaces: $e');
    return [];
  }
});

/// Provider for child space names
final childSpaceNamesProvider = FutureProvider<List<String>>((ref) async {
  final spaces = await ref.watch(childSpacesProvider.future);
  return spaces.map((s) => s.name).toList();
});

// ==================== CASCADING SPACE NAVIGATION ==================== //

/// Tracks the full space path as a list of selected space names
/// e.g., ['characters', 'hero', 'v1']
final selectedSpacePathProvider = StateProvider<List<String>>((ref) => []);

/// Provider for child spaces at a specific depth in the path
/// Takes the current space path and returns children of the last space
final childSpacesAtDepthProvider = FutureProvider.family<List<Space>, int>((ref, depth) async {
  final project = await ref.watch(selectedProjectProvider.future);
  if (project == null) return [];

  final spacePath = ref.watch(selectedSpacePathProvider);
  final filters = ref.watch(mediaFiltersProvider);
  final queries = ref.watch(searchChipsProvider).map((q) => q.toLowerCase()).toList();
  
  // If depth is 0, return root spaces from project
  if (depth == 0) {
    try {
      final spaces = await PerfLogger.timeAsync(
        'childSpacesAtDepth(0).project.getSpaces',
        () => project.getSpaces(),
        fields: {'project': project.name},
      );
      // Filter to only root-level spaces (no '/' in name after project)
      return spaces.where((s) {
        final pathParts = s.path.split('/').where((p) => p.isNotEmpty).toList();
        return pathParts.length == 2; // /project/space
      }).toList();
    } catch (e) {
      if (_isUnauthenticatedGrpcError(e)) {
        await _forceRefreshAuthToken(ref);
        final refreshedClient = await ref.read(kumihoClientProvider.future);
        if (refreshedClient == null) return [];
        try {
          final refreshedProjects = await PerfLogger.timeAsync(
            'childSpacesAtDepth(0).projects(after_refresh)',
            () => refreshedClient.projects(),
          );
          final refreshedProject = refreshedProjects.firstWhere((p) => p.name == project.name);
          final spaces = await PerfLogger.timeAsync(
            'childSpacesAtDepth(0).getSpaces(after_refresh)',
            () => refreshedProject.getSpaces(),
            fields: {'project': refreshedProject.name},
          );
          return spaces.where((s) {
            final pathParts = s.path.split('/').where((p) => p.isNotEmpty).toList();
            return pathParts.length == 2;
          }).toList();
        } catch (e2) {
          debugPrint('Failed to fetch root spaces after token refresh: $e2');
          return [];
        }
      }

      debugPrint('Failed to fetch root spaces: $e');
      return [];
    }
  }

  // If we don't have enough path segments for this depth, return empty
  if (spacePath.length < depth) return [];

  // Build path to parent space
  final parentPath = '/${project.name}/${spacePath.sublist(0, depth).join('/')}';
  
  try {
    final client = await ref.read(kumihoClientProvider.future);
    if (client == null) return [];
    
    final parentSpace = await PerfLogger.timeAsync(
      'childSpacesAtDepth($depth).client.space',
      () => client.space(parentPath),
      fields: {'path': parentPath},
    );
    return await PerfLogger.timeAsync(
      'childSpacesAtDepth($depth).parent.getChildSpaces',
      () => parentSpace.getChildSpaces(),
      fields: {'path': parentPath},
    );
  } catch (e) {
    if (_isUnauthenticatedGrpcError(e)) {
      await _forceRefreshAuthToken(ref);
      final refreshedClient = await ref.read(kumihoClientProvider.future);
      if (refreshedClient == null) return [];
      try {
        final parentSpace = await PerfLogger.timeAsync(
          'childSpacesAtDepth($depth).space(after_refresh)',
          () => refreshedClient.space(parentPath),
          fields: {'path': parentPath},
        );
        return await PerfLogger.timeAsync(
          'childSpacesAtDepth($depth).getChildSpaces(after_refresh)',
          () => parentSpace.getChildSpaces(),
          fields: {'path': parentPath},
        );
      } catch (e2) {
        debugPrint('Failed to fetch child spaces after token refresh: $e2');
        return [];
      }
    }

    debugPrint('Failed to fetch child spaces at depth $depth: $e');
    return [];
  }
});

/// Checks if a space at given depth has children
final hasChildrenAtDepthProvider = FutureProvider.family<bool, int>((ref, depth) async {
  final children = await ref.watch(childSpacesAtDepthProvider(depth + 1).future);
  return children.isNotEmpty;
});

/// Gets the currently selected space object (deepest in path)
final currentSpaceProvider = FutureProvider<Space?>((ref) async {
  final project = await ref.watch(selectedProjectProvider.future);
  if (project == null) {
    return null;
  }

  final spacePath = ref.watch(selectedSpacePathProvider);
  if (spacePath.isEmpty) {
    return null;
  }

  final fullPath = '/${project.name}/${spacePath.join('/')}';
  
  try {
    final client = await ref.watch(kumihoClientProvider.future);
    return await client?.space(fullPath);
  } catch (e) {
    debugPrint('Failed to get space: $e');
    return null;
  }
});

// ==================== ITEMS IN CURRENT SPACE ==================== //

/// Represents a single artifact to display in the browser
/// Each artifact becomes one ClipContainer
class KumihoArtifactData {
  final Item item;
  final Revision? revision;
  final Artifact? artifact;
  final bool isLoadMorePlaceholder;
  final int? nextRevisionIndex;

  KumihoArtifactData({
    required this.item,
    this.revision,
    this.artifact,
    this.isLoadMorePlaceholder = false,
    this.nextRevisionIndex,
  });

  /// Unique ID for this artifact
  String get id {
    if (isLoadMorePlaceholder) return '${item.kref.uri}?more=${nextRevisionIndex ?? 0}';
    if (artifact != null) return artifact!.kref.uri;
    if (revision != null) return '${item.kref.uri}?r=${revision!.number}';
    return item.kref.uri;
  }

  /// Display name (artifact name or item name if only one)
  String get displayName => isLoadMorePlaceholder ? 'Loading more…' : (artifact?.name ?? item.itemName);

  /// Item name
  String get itemName => isLoadMorePlaceholder ? 'Loading more…' : item.itemName;

  /// File location for thumbnail
  String get location => artifact?.location ?? '';

  /// Get file type from artifact location
  String get fileType {
    if (location.isEmpty) return 'item';
    final ext = location.split('.').last.toLowerCase();
    return ext;
  }

  /// Revision number
  int get revisionNumber => revision?.number ?? 0;

  /// Revision tags
  List<String> get tags => revision?.tags ?? [];

  /// Revision metadata
  Map<String, String> get metadata => isLoadMorePlaceholder ? const {} : (revision?.metadata ?? item.metadata);
}

MediaItem _mediaItemFromArtifactData(KumihoArtifactData data) {
  if (data.isLoadMorePlaceholder) {
    final colorHash = data.id.hashCode;
    final hue = (colorHash % 360).abs().toDouble();
    final thumbColor = HSVColor.fromAHSV(1.0, hue, 0.2, 0.35).toColor();

    return MediaItem(
      id: data.id,
      name: data.itemName,
      artifactName: data.displayName,
      type: 'item',
      kind: data.item.kind,
      revision: '',
      tags: const [],
      author: '',
      date: DateTime(1970),
      thumbColor: thumbColor,
      thumbnailPath: null,
      kref: data.item.kref.uri,
      revisionKref: null,
      deprecated: false,
      location: null,
      metadata: const ItemMetadata(prompt: '__kumiho_load_more__'),
    );
  }

  final metadata = data.metadata;

  // Parse metadata for display
  final prompt = metadata['prompt'] ?? metadata['positive_prompt'];
  final negativePrompt = metadata['negative_prompt'];
  final model = metadata['model'] ?? metadata['checkpoint'];
  final lorasStr = metadata['loras'] ?? metadata['lora'];
  final loras = lorasStr?.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final seed = int.tryParse(metadata['seed'] ?? '');
  final steps = int.tryParse(metadata['steps'] ?? '');
  final cfg = double.tryParse(metadata['cfg'] ?? metadata['cfg_scale'] ?? '');
  final sampler = metadata['sampler'] ?? metadata['sampler_name'];
  final width = metadata['width'];
  final height = metadata['height'];
  final resolution = (width != null && height != null) ? '${width}x$height' : null;

  // Generate a color from artifact kref for placeholder thumbnail
  final colorHash = data.id.hashCode;
  final hue = (colorHash % 360).abs().toDouble();
  final thumbColor = HSVColor.fromAHSV(1.0, hue, 0.6, 0.7).toColor();

  // Prefer revision.createdAt for date (more accurate for sorting by version time)
  final dateStr = data.revision?.createdAt ?? data.item.createdAt ?? '';
  final date = DateTime.tryParse(dateStr) ?? DateTime.now();

  final thumbnailPath = data.location.isNotEmpty ? data.location : null;

  return MediaItem(
    id: data.id,
    name: data.itemName,
    artifactName: data.displayName,
    type: data.fileType,
    kind: data.item.kind,
    revision: data.revision != null ? 'v${data.revisionNumber}' : '',
    tags: data.tags,
    author: data.item.username,
    date: date,
    thumbColor: thumbColor,
    thumbnailPath: thumbnailPath,
    kref: data.artifact?.kref.uri ?? data.item.kref.uri,
    revisionKref: data.revision?.kref.uri,
    deprecated: (data.artifact?.deprecated ?? false) || (data.revision?.deprecated ?? false) || data.item.deprecated,
    isPublished: data.revision?.published ?? false,
    location: data.location,
    // Keep metadata non-null so search/filter logic doesn't thrash on null checks.
    metadata: ItemMetadata(
      prompt: prompt,
      negativePrompt: negativePrompt,
      model: model,
      loras: loras,
      seed: seed,
      steps: steps,
      cfg: cfg,
      sampler: sampler,
      resolution: resolution,
    ),
  );
}

/// Trigger for manual refresh
final kumihoRefreshTriggerProvider = StateProvider<int>((ref) => 0);

class PagedItemsState {
  final List<KumihoArtifactData> items;
  final List<MediaItem> mediaItems;
  final String? nextCursor;
  final bool isLoading;
  final int pendingDetails;
  final bool hasMore;

  const PagedItemsState({
    this.items = const [],
    this.mediaItems = const [],
    this.nextCursor,
    this.isLoading = false,
    this.pendingDetails = 0,
    this.hasMore = true,
  });

  PagedItemsState copyWith({
    List<KumihoArtifactData>? items,
    List<MediaItem>? mediaItems,
    String? nextCursor,
    bool? isLoading,
    int? pendingDetails,
    bool? hasMore,
  }) {
    return PagedItemsState(
      items: items ?? this.items,
      mediaItems: mediaItems ?? this.mediaItems,
      nextCursor: nextCursor ?? this.nextCursor,
      isLoading: isLoading ?? this.isLoading,
      pendingDetails: pendingDetails ?? this.pendingDetails,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class PagedItemsNotifier extends StateNotifier<PagedItemsState> {
  final Ref ref;
  final Set<String> _expandingItems = {};
  // Prevent rebuild-driven re-entrancy for the same tile (base item tile or
  // load-more placeholder tile).
  final Set<String> _detailsFetchedForTileIds = {};
  // Queue detail expansion work to avoid saturating the UI isolate when many
  // base tiles become visible at once.
  Future<void> _detailsQueue = Future.value();
  int _pendingDetails = 0;
  bool _pendingDetailsNotifyScheduled = false;

  // Keep background detail work bounded. A large backlog (e.g. pending=49)
  // makes the app feel perpetually busy and can amplify jank.
  static const int _maxPendingDetails = 12;
  final Map<String, List<Revision>> _revisionsCache = {};
  int _generation = 0;

  PagedItemsNotifier(this.ref) : super(const PagedItemsState()) {
    // Refresh manual trigger (and real-time events) reload the root item list
    ref.listen<int>(kumihoRefreshTriggerProvider, (_, __) {
      Future.microtask(loadFirstPage);
    });

    // Visibility settings should reload the root item list
    ref.listen<bool>(includeDeprecatedProvider, (_, __) {
      Future.microtask(loadFirstPage);
    });

    // Project selection changes should reset paging state.
    // (Listening to selectedProjectProvider causes load loops because _loadPage
    // awaits selectedProjectProvider.future, which churns its AsyncValue.)
    ref.listen<String?>(selectedProjectNameProvider, (prev, next) {
      if (next == null || next.isEmpty) {
        Future.microtask(() {
          if (!mounted) return;
          state = const PagedItemsState();
        });
        return;
      }

      if (prev != next) {
        Future.microtask(loadFirstPage);
      }
    });

    // Space navigation changes should reload items (we now use this notifier
    // for both root browsing and space browsing).
    ref.listen<List<String>>(selectedSpacePathProvider, (prev, next) {
      if (prev == next) return;
      Future.microtask(loadFirstPage);
    });
  }

  Future<List<KumihoArtifactData>> _expandItemData(KumihoArtifactData data) async {
    final includeDeprecated = ref.read(includeDeprecatedProvider);
    final revisions = await _getRevisionsCompat(data.item, includeDeprecated: includeDeprecated);
    if (revisions.isEmpty) {
      return [data];
    }

    // Deduplicate revisions by number
    final uniqueRevisions = <int, Revision>{};
    for (final r in revisions) {
      if (!includeDeprecated && r.deprecated) continue;
      uniqueRevisions[r.number] = r;
    }

    // Sort revisions by number descending (newest first)
    final sortedRevisions = uniqueRevisions.values.toList()
      ..sort((a, b) => b.number.compareTo(a.number));

    final expandedItems = <KumihoArtifactData>[];
    for (final revision in sortedRevisions) {
      try {
        final artifacts = await revision.getArtifacts();

        // Deduplicate artifacts by KRef URI
        final uniqueArtifacts = <String, Artifact>{};
        for (final a in artifacts) {
          if (!includeDeprecated && a.deprecated) continue;
          uniqueArtifacts[a.kref.uri] = a;
        }

        if (uniqueArtifacts.isEmpty) {
          expandedItems.add(KumihoArtifactData(
            item: data.item,
            revision: revision,
            artifact: null,
          ));
        } else {
          for (final artifact in uniqueArtifacts.values) {
            expandedItems.add(KumihoArtifactData(
              item: data.item,
              revision: revision,
              artifact: artifact,
            ));
          }
        }
      } catch (e) {
        debugPrint('Failed to get artifacts for revision ${revision.number}: $e');
        expandedItems.add(KumihoArtifactData(
          item: data.item,
          revision: revision,
          artifact: null,
        ));
      }
    }

    return expandedItems.isEmpty ? [data] : expandedItems;
  }

  Future<void> loadFirstPage() async {
    // Cancel any in-flight load/expansion work and restart from scratch.
    // This keeps project/space navigation responsive even if the user changes
    // selection while a previous load is still running.
    _generation++;
    _expandingItems.clear();
    _detailsFetchedForTileIds.clear();
    _detailsQueue = Future.value();
    _pendingDetails = 0;
    _pendingDetailsNotifyScheduled = false;
    _revisionsCache.clear();
    state = state.copyWith(isLoading: true, pendingDetails: 0, items: [], mediaItems: [], nextCursor: null, hasMore: true);
    await PerfLogger.timeAsync(
      'PagedItems.loadFirstPage',
      () => _loadPage(),
      fields: {
        'project': ref.read(selectedProjectNameProvider),
        'spaceDepth': ref.read(selectedSpacePathProvider).length,
      },
    );
  }

  void _schedulePendingDetailsNotify() {
    if (_pendingDetailsNotifyScheduled) return;
    _pendingDetailsNotifyScheduled = true;
    scheduleMicrotask(() {
      _pendingDetailsNotifyScheduled = false;
      if (!mounted) return;
      if (state.pendingDetails == _pendingDetails) return;
      state = state.copyWith(pendingDetails: _pendingDetails);
    });
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    await PerfLogger.timeAsync('PagedItems.loadNextPage', () => _loadPage());
  }

  Future<void> _loadPage() async {
    final generation = _generation;
    final projectName = ref.read(selectedProjectNameProvider);
    if (projectName == null || projectName.isEmpty) {
      state = state.copyWith(isLoading: false, items: [], hasMore: false);
      return;
    }

    final projects = await ref.read(projectsProvider.future);
    Project? project;
    try {
      project = projects.firstWhere((p) => p.name == projectName);
    } catch (_) {
      project = null;
    }

    if (project == null) {
      state = state.copyWith(isLoading: false, items: [], hasMore: false);
      return;
    }

    final resolvedProject = project;

    final includeDeprecated = ref.read(includeDeprecatedProvider);
    final spacePath = ref.read(selectedSpacePathProvider);

    try {
      // Fetch the base Item list only. Revisions/artifacts are expanded lazily
      // as ClipContainers become visible (see DraggableClipContainer).
      final List<Item> baseItems;
      if (spacePath.isEmpty) {
        baseItems = await PerfLogger.timeAsync(
          'PagedItems._getProjectItemsCompat',
          () => _getProjectItemsCompat(resolvedProject, includeDeprecated: includeDeprecated),
          fields: {'project': resolvedProject.name, 'includeDeprecated': includeDeprecated},
        );
      } else {
        final client = await ref.read(kumihoClientProvider.future);
        if (client == null) {
          state = state.copyWith(isLoading: false, items: [], hasMore: false);
          return;
        }
        final contextFilter = '${resolvedProject.name}/${spacePath.join('/')}';
        final itemResponses = await PerfLogger.timeAsync(
          'PagedItems._itemSearchCompat',
          () => _itemSearchCompat(
            client,
            '$contextFilter/',
            '',
            '',
            includeDeprecated: includeDeprecated,
          ),
          fields: {'context': contextFilter, 'includeDeprecated': includeDeprecated},
        );
        baseItems = itemResponses.map((r) => Item(r, client)).toList();
      }

      if (generation != _generation) return;

      final scopedItems = baseItems.where((item) => item.projectName == resolvedProject.name);
      final filteredItems = includeDeprecated ? scopedItems : scopedItems.where((item) => !item.deprecated);

      // Sorting very large lists on the UI isolate can make the whole app feel
      // sluggish (project dropdowns, scrolling, etc). For huge item lists we
      // rely on the server's ordering and prioritize responsiveness.
      const sortThreshold = 2500;
      final filteredList = filteredItems.toList();

      PerfLogger.log(
        'PagedItems._loadPage: base=${baseItems.length} filtered=${filteredList.length} sort=${filteredList.length <= sortThreshold}',
      );

      Iterable<Item> sortedBaseItems;
      if (filteredList.length <= sortThreshold) {
        final itemsWithSortKey = filteredList
            .map((item) {
              final created = item.createdAt;
              final millis = created == null ? 0 : (DateTime.tryParse(created)?.millisecondsSinceEpoch ?? 0);
              return (millis, item);
            })
            .toList();
        itemsWithSortKey.sort((a, b) => b.$1.compareTo(a.$1));
        sortedBaseItems = itemsWithSortKey.map((e) => e.$2);
      } else {
        sortedBaseItems = filteredList;
      }

      // All items are fetched in one API call, but we stream them into state
      // to keep the UI responsive.
      const batchSize = 200;

      final currentItemUris = <String>{};
      // State is reset at loadFirstPage, but be defensive if future changes
      // ever call _loadPage incrementally.
      currentItemUris.addAll(state.items.map((i) => i.item.kref.uri));

      final updatedItems = <KumihoArtifactData>[];
      final updatedMediaItems = <MediaItem>[];

      var batched = 0;
      for (final item in sortedBaseItems) {
        if (generation != _generation) return;

        // Bundles have no artifacts/images to display in the media grid/list and
        // can cause unnecessary work and stutter while scrolling.
        if (item.kind.toLowerCase() == 'bundle') {
          continue;
        }

        final uri = item.kref.uri;
        if (currentItemUris.contains(uri)) {
          continue;
        }
        currentItemUris.add(uri);

        final data = KumihoArtifactData(item: item);
        updatedItems.add(data);
        updatedMediaItems.add(_mediaItemFromArtifactData(data));
        batched++;

        if (batched >= batchSize) {
          if (mounted && generation == _generation) {
            state = state.copyWith(
              items: [...state.items, ...updatedItems],
              mediaItems: [...state.mediaItems, ...updatedMediaItems],
              nextCursor: null,
              hasMore: false,
              isLoading: true,
            );
          }
          updatedItems.clear();
          updatedMediaItems.clear();
          batched = 0;

          // Yield so UI can process input (e.g., project/space dropdown).
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (mounted && generation == _generation) {
        state = state.copyWith(
          items: [...state.items, ...updatedItems],
          mediaItems: [...state.mediaItems, ...updatedMediaItems],
          nextCursor: null,
          hasMore: false,
          isLoading: false,
        );
      }

      PerfLogger.log('PagedItems._loadPage done: items=${state.items.length} mediaItems=${state.mediaItems.length}');
    } catch (e) {
      debugPrint('Failed to load items: $e');
      state = state.copyWith(isLoading: false, hasMore: false);
    }
  }
  
  Future<void> fetchDetails(String itemId) {
    final requestGeneration = _generation;

    // Fast no-op checks to avoid flooding the queue and rebuilding the UI.
    if (requestGeneration != _generation) return Future.value();
    if (_expandingItems.contains(itemId) || _detailsFetchedForTileIds.contains(itemId)) {
      return Future.value();
    }

    final index = state.items.indexWhere((i) => i.id == itemId);
    if (index == -1) return Future.value();
    final data = state.items[index];
    if (data.revision != null) return Future.value();
    if (data.item.kind.toLowerCase() == 'bundle') {
      // Never expand bundles; also mark so rebuilds don't keep trying.
      _detailsFetchedForTileIds.add(itemId);
      return Future.value();
    }

    // Cap how much detail work we let build up; keeps project/space navigation responsive.
    if (_pendingDetails >= _maxPendingDetails) {
      return Future.value();
    }

    _pendingDetails++;
    _schedulePendingDetailsNotify();

    _detailsQueue = _detailsQueue.then((_) async {
      try {
        if (requestGeneration != _generation) return;

        // If the user is in playback mode (fullscreen viewer), defer expensive
        // detail expansion so Space/arrow navigation stays responsive.
        while (ref.read(playbackModeActiveProvider) && requestGeneration == _generation) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        await PerfLogger.timeAsync(
          'PagedItems.fetchDetails',
          () => _fetchDetailsInternal(itemId, requestGeneration),
          fields: {'pending': _pendingDetails, 'itemId': itemId},
        );
      } finally {
        _pendingDetails = (_pendingDetails - 1).clamp(0, 1 << 30);
        _schedulePendingDetailsNotify();
      }
    });

    return _detailsQueue;
  }

  Future<void> _fetchDetailsInternal(String itemId, int generation) async {
    // If the user is in playback mode (fullscreen viewer), defer expensive
    // detail expansion so Space/arrow navigation stays responsive.
    while (ref.read(playbackModeActiveProvider) && generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // Prevent concurrent expansion of the same item
    if (_expandingItems.contains(itemId)) return;

    // Prevent repeated expansion attempts for the same tile on rebuild.
    if (_detailsFetchedForTileIds.contains(itemId)) return;
    
    final index = state.items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    
    final data = state.items[index];
    if (data.revision != null) return;

    // Bundles don't have artifacts/images to expand into clip tiles.
    // Expanding them is wasted work and can cause stutter when scrolling.
    if (data.item.kind.toLowerCase() == 'bundle') {
      _detailsFetchedForTileIds.add(itemId);
      return;
    }
    
    _expandingItems.add(itemId);
    
    try {
      final includeDeprecated = ref.read(includeDeprecatedProvider);
      final itemKrefUri = data.item.kref.uri;

      final hadCachedRevisions = _revisionsCache.containsKey(itemKrefUri);

      // If the user enters playback mode while we are about to do heavy work,
      // pause here rather than letting revisions/artifacts processing block
      // the main isolate.
      while (ref.read(playbackModeActiveProvider) && generation == _generation) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // Fetch and cache the revision list once per item (per generation).
      final sortedRevisions = _revisionsCache[itemKrefUri] ?? await () async {
        final revisions = await PerfLogger.timeAsync(
          'PagedItems._getRevisionsCompat',
          () => _getRevisionsCompat(data.item, includeDeprecated: includeDeprecated),
          fields: {'includeDeprecated': includeDeprecated},
        );

        // Deduplicate revisions by number
        final uniqueRevisions = <int, Revision>{};
        for (final r in revisions) {
          if (!includeDeprecated && r.deprecated) continue;
          uniqueRevisions[r.number] = r;
        }

        final sorted = uniqueRevisions.values.toList()..sort((a, b) => b.number.compareTo(a.number));
        _revisionsCache[itemKrefUri] = sorted;
        return sorted;
      }();

      PerfLogger.log(
        'PagedItems._fetchDetailsInternal: revisions=${sortedRevisions.length} cached=$hadCachedRevisions start=${data.nextRevisionIndex ?? 0}',
      );

      if (sortedRevisions.isEmpty) {
        return;
      }

      // Page the expansion: only add up to ~30 clips at a time.
      // On Windows, large gRPC/protobuf responses can cause noticeable main
      // isolate hitches. Use smaller batches & lower concurrency to keep
      // interactions (like Space-to-preview) responsive.
      final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
      final clipPageSize = isWindows ? 12 : 30;
      final revisionBatchSize = isWindows ? 2 : 8;
      final artifactsConcurrency = isWindows ? 1 : 4;

      final startRevisionIndex = data.isLoadMorePlaceholder ? (data.nextRevisionIndex ?? 0) : 0;
      var revisionIndex = startRevisionIndex;
      var clipsAdded = 0;
      final pageExpanded = <KumihoArtifactData>[];

      while (revisionIndex < sortedRevisions.length && clipsAdded < clipPageSize) {
        if (generation != _generation) return;

        // Pause expansion while fullscreen viewer is open.
        while (ref.read(playbackModeActiveProvider) && generation == _generation) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        final batch = sortedRevisions.skip(revisionIndex).take(revisionBatchSize).toList();
        revisionIndex += batch.length;

        for (var i = 0; i < batch.length; i += artifactsConcurrency) {
          final remaining = clipPageSize - clipsAdded;
          if (remaining <= 0) break;

          // Pause before starting any getArtifacts calls.
          while (ref.read(playbackModeActiveProvider) && generation == _generation) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }

          final chunk = batch.skip(i).take(artifactsConcurrency).toList();
          final futures = chunk.map((revision) async {
            try {
              final artifacts = await revision.getArtifacts();

              // IMPORTANT: don't build huge intermediate maps/lists here.
              // For items with many artifacts, allocating/deduping everything can
              // block the main isolate long enough to cause UI stalls.
              final selected = <KumihoArtifactData>[];
              final seen = <String>{};
              for (final a in artifacts) {
                if (!includeDeprecated && a.deprecated) continue;
                final uri = a.kref.uri;
                if (!seen.add(uri)) continue;
                selected.add(KumihoArtifactData(item: data.item, revision: revision, artifact: a));
                if (selected.length >= remaining) break;
              }

              if (selected.isEmpty) {
                return <KumihoArtifactData>[KumihoArtifactData(item: data.item, revision: revision, artifact: null)];
              }

              return selected;
            } catch (e) {
              debugPrint('Failed to get artifacts for revision ${revision.number}: $e');
              return <KumihoArtifactData>[
                KumihoArtifactData(item: data.item, revision: revision, artifact: null),
              ];
            }
          }).toList();

          final results = await Future.wait(futures);
          for (final list in results) {
            for (final d in list) {
              if (clipsAdded >= clipPageSize) break;
              pageExpanded.add(d);
              clipsAdded++;
            }
            if (clipsAdded >= clipPageSize) break;
          }

          // Yield between chunks so the UI can process input.
          await Future<void>.delayed(Duration.zero);
        }

        // Yield between revision batches as well.
        await Future<void>.delayed(Duration.zero);
      }

      if (pageExpanded.isEmpty) {
        // Mark as fetched so this tile doesn't keep triggering on rebuild.
        _detailsFetchedForTileIds.add(itemId);
        return;
      }

      // Deduplicate newly produced clips.
      final pageExpandedById = <String, KumihoArtifactData>{};
      for (final d in pageExpanded) {
        pageExpandedById[d.id] = d;
      }
      final uniquePageExpanded = pageExpandedById.values.toList();

      // Determine if there is more history to load for this item.
      final hasMoreRevisions = revisionIndex < sortedRevisions.length;

      PerfLogger.log(
        'PagedItems._fetchDetailsInternal expanded: clips=$clipsAdded nextRevisionIndex=$revisionIndex hasMore=$hasMoreRevisions',
      );
      final placeholder = hasMoreRevisions
          ? KumihoArtifactData(
              item: data.item,
              isLoadMorePlaceholder: true,
              nextRevisionIndex: revisionIndex,
            )
          : null;

      // Update the list by replacing the current placeholder entry (either the
      // base item tile, or the load-more tile).
      final updated = List<KumihoArtifactData>.from(state.items);
      final updatedMedia = List<MediaItem>.from(state.mediaItems);

      // Only dedupe against this item's existing block (ignoring load-more tiles).
      final existingIds = updated
          .where((e) => e.item.kref.uri == itemKrefUri && !e.isLoadMorePlaceholder)
          .map((e) => e.id)
          .toSet();
      final filtered = uniquePageExpanded.where((e) => !existingIds.contains(e.id)).toList();

      final replacement = <KumihoArtifactData>[...filtered, if (placeholder != null) placeholder];
      final replacementMedia = replacement.map(_mediaItemFromArtifactData).toList();

      updated.replaceRange(index, index + 1, replacement);
      updatedMedia.replaceRange(index, index + 1, replacementMedia);

      if (mounted && generation == _generation) {
        state = state.copyWith(items: updated, mediaItems: updatedMedia);
      }

      // This tile (base item tile or load-more tile) has been processed.
      _detailsFetchedForTileIds.add(itemId);
    } catch (e) {
      debugPrint('Failed to fetch details for $itemId: $e');
    } finally {
      _expandingItems.remove(itemId);
    }
  }

  /// Fetch just enough data to preview a base item in the viewer.
  ///
  /// This intentionally avoids expanding the grid into many revision/artifact
  /// tiles (which can be extremely expensive for items with 100+ revisions).
  ///
  /// Returns a [MediaItem] that has a displayable [thumbnailPath]/[location]
  /// when possible, or null if no artifacts are available.
  Future<MediaItem?> fetchPreviewForItem(MediaItem baseItem) async {
    // If the item already has a usable thumbnail/location, nothing to do.
    if (baseItem.hasLocalThumbnail || baseItem.hasHttpThumbnail || baseItem.isVideo) {
      return baseItem;
    }

    final requestGeneration = _generation;
    if (requestGeneration != _generation) return null;

    // Resolve the backing Item model from the current state.
    final itemKrefUri = baseItem.kref;
    if (itemKrefUri == null || itemKrefUri.isEmpty) return null;
    final dataIndex = state.items.indexWhere((d) => d.item.kref.uri == itemKrefUri);
    if (dataIndex == -1) return null;
    final data = state.items[dataIndex];

    // Never attempt to preview bundles via artifacts.
    if (data.item.kind.toLowerCase() == 'bundle') return null;

    final includeDeprecated = ref.read(includeDeprecatedProvider);

    return await PerfLogger.timeAsync(
      'PagedItems.fetchPreviewForItem',
      () async {
        // Fetch (or reuse) revisions list, but only use the latest revision.
        final sortedRevisions = _revisionsCache[itemKrefUri] ?? await () async {
          final revisions = await PerfLogger.timeAsync(
            'PagedItems._getRevisionsCompat',
            () => _getRevisionsCompat(data.item, includeDeprecated: includeDeprecated),
            fields: {'includeDeprecated': includeDeprecated},
          );

          final uniqueRevisions = <int, Revision>{};
          for (final r in revisions) {
            if (!includeDeprecated && r.deprecated) continue;
            uniqueRevisions[r.number] = r;
          }

          final sorted = uniqueRevisions.values.toList()..sort((a, b) => b.number.compareTo(a.number));
          _revisionsCache[itemKrefUri] = sorted;
          return sorted;
        }();

        if (requestGeneration != _generation) return null;
        if (sortedRevisions.isEmpty) return null;

        final latest = sortedRevisions.first;
        try {
          final artifacts = await PerfLogger.timeAsync(
            'PagedItems.fetchPreviewForItem.getArtifacts',
            () => latest.getArtifacts(),
            fields: {'revision': latest.number},
          );

          final uniqueArtifacts = <String, Artifact>{};
          for (final a in artifacts) {
            if (!includeDeprecated && a.deprecated) continue;
            uniqueArtifacts[a.kref.uri] = a;
          }

          if (uniqueArtifacts.isEmpty) return null;

          // Pick the preview artifact, preferring an explicit 'thumbnail'
          // artifact, then the revision's default artifact, then any artifact
          // with a location. This makes a user-added thumbnail the preview.
          final withLocation =
              uniqueArtifacts.values.where((a) => (a.location).isNotEmpty).toList();
          if (withLocation.isEmpty) return null;

          Artifact pickPreviewArtifact() {
            for (final a in withLocation) {
              if (a.name == 'thumbnail') return a;
            }
            final def = latest.defaultArtifact;
            if (def != null && def.isNotEmpty) {
              for (final a in withLocation) {
                if (a.name == def) return a;
              }
            }
            return withLocation.first;
          }

          final artifactWithLocation = pickPreviewArtifact();

          final previewData = KumihoArtifactData(item: data.item, revision: latest, artifact: artifactWithLocation);
          return _mediaItemFromArtifactData(previewData);
        } catch (e) {
          debugPrint('fetchPreviewForItem: getArtifacts failed for ${latest.kref.uri}: $e');
          return null;
        }
      },
      fields: {'itemId': baseItem.id, 'kref': baseItem.kref},
    );
  }
}

final pagedItemsProvider = StateNotifierProvider<PagedItemsNotifier, PagedItemsState>((ref) {
  return PagedItemsNotifier(ref);
});

/// Provider for artifacts in the current view.
///
/// This is synchronous by design: the underlying list is maintained by
/// [pagedItemsProvider] and updated incrementally (including lazy expansion
/// of revisions/artifacts). Using a FutureProvider here caused UI to bounce
/// through AsyncLoading on every incremental update, which reset scroll
/// position and created visible “jumps”.
final kumihoArtifactsProvider = Provider<List<KumihoArtifactData>>((ref) {
  final pagedState = ref.watch(pagedItemsProvider);
  return pagedState.items;
});

// ==================== FILTERING & SEARCH STATE ==================== //

/// Filter type for media items (can be combined)
enum MediaFilterType { images, videos, today, week }

/// Current filter selection (multi-select as a Set)
final mediaFiltersProvider = StateProvider<Set<MediaFilterType>>((ref) => {});

/// Search query input text
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Persistent search chips (added via Enter)
final searchChipsProvider = StateProvider<List<String>>((ref) => []);

/// Convert KumihoArtifactData to MediaItem for display.
///
/// Synchronous for the same reason as [kumihoArtifactsProvider].
final kumihoMediaItemsProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(pagedItemsProvider.select((s) => s.mediaItems));
  final filters = ref.watch(mediaFiltersProvider);
  final queries = ref.watch(searchChipsProvider).map((q) => q.toLowerCase()).toList();

  // Hot path: when no filters/search are active, returning the existing list
  // avoids an O(n) scan + copy on every incremental update (which can become
  // a major source of UI stalls once the grid contains many artifacts).
  if (filters.isEmpty && queries.isEmpty) {
    return items;
  }

  bool isLoadMoreTile(MediaItem item) => item.metadata?.prompt == '__kumiho_load_more__';

  // Bundles have no artifacts/images to display in the media grid/list and
  // can cause unnecessary work and stutter while scrolling.
  var filteredItems = items
      .where((item) => isLoadMoreTile(item) || item.kind.toLowerCase() != 'bundle')
      .toList(growable: false);

  // Apply filters (multi-select - all selected filters must match)
  if (filters.isNotEmpty) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));
    
    filteredItems = filteredItems.where((item) {
      if (isLoadMoreTile(item)) return true;
      // Check type filters (images/videos) - if either selected, must match one
      final hasTypeFilter = filters.contains(MediaFilterType.images) || filters.contains(MediaFilterType.videos);
      if (hasTypeFilter) {
        final matchesImages = filters.contains(MediaFilterType.images) && item.isImage;
        final matchesVideos = filters.contains(MediaFilterType.videos) && item.isVideo;
        if (!matchesImages && !matchesVideos) return false;
      }
      
      // Check date filters - if either selected, must match one
      final hasDateFilter = filters.contains(MediaFilterType.today) || filters.contains(MediaFilterType.week);
      if (hasDateFilter) {
        final matchesToday = filters.contains(MediaFilterType.today) && item.date.isAfter(todayStart);
        final matchesWeek = filters.contains(MediaFilterType.week) && item.date.isAfter(weekStart);
        if (!matchesToday && !matchesWeek) return false;
      }
      
      return true;
    }).toList();
  }

  // Apply search queries (all must match)
  if (queries.isNotEmpty) {
    filteredItems = filteredItems.where((item) {
      if (isLoadMoreTile(item)) return true;
      final meta = item.metadata;
      if (meta == null) return false;
      
      // Search in prompt, model, loras, sampler
      final searchableFields = [
        meta.prompt,
        meta.negativePrompt,
        meta.model,
        meta.sampler,
        meta.seed?.toString(),
        meta.steps?.toString(),
        meta.cfg?.toString(),
        meta.resolution,
        item.name,
        item.artifactName,
        ...item.tags,
        ...?meta.loras,
        ...item.metadata?.toSearchMap().values ?? [],
      ].whereType<String>().join(' ').toLowerCase();
      
      return queries.every(searchableFields.contains);
    }).toList();
  }

  return filteredItems;
});

/// Breadcrumb path for navigation display
final breadcrumbPathProvider = Provider<List<String>>((ref) {
  final project = ref.watch(selectedProjectNameProvider);
  final spacePath = ref.watch(selectedSpacePathProvider);
  
  if (project == null) return [];
  return [project, ...spacePath];
});

/// Total items count in current view
final itemCountProvider = Provider<int>((ref) {
  return ref.watch(kumihoMediaItemsProvider).length;
});

// ==================== LINEAGE/GRAPH PROVIDERS ==================== //

/// Provider for fetching edges from a revision
final revisionEdgesProvider = FutureProvider.family<List<Edge>, String>((ref, krefUri) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) return [];

  try {
    final edges = await client.getEdges(
      krefUri,
      direction: EdgeDirection.BOTH,
    );
    return edges.edges.map((e) => Edge(e, client)).toList();
  } catch (e) {
    debugPrint('Failed to fetch edges for $krefUri: $e');
    return [];
  }
});

/// Provider for fetching dependencies of a revision (what it depends on)
final revisionDependenciesProvider = FutureProvider.family<List<String>, String>((ref, krefUri) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) return [];

  try {
    final response = await client.traverseEdges(
      krefUri,
      EdgeDirection.OUTGOING,
      edgeTypeFilter: ['DEPENDS_ON', 'DERIVED_FROM'],
      maxDepth: 5,
    );
    return response.revisionKrefs.map((k) => k.uri).toList();
  } catch (e) {
    debugPrint('Failed to fetch dependencies for $krefUri: $e');
    return [];
  }
});

/// Provider for fetching dependents of a revision (what depends on it)
final revisionDependentsProvider = FutureProvider.family<List<String>, String>((ref, krefUri) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) return [];

  try {
    final response = await client.traverseEdges(
      krefUri,
      EdgeDirection.INCOMING,
      edgeTypeFilter: ['DEPENDS_ON', 'DERIVED_FROM'],
      maxDepth: 5,
    );
    return response.revisionKrefs.map((k) => k.uri).toList();
  } catch (e) {
    debugPrint('Failed to fetch dependents for $krefUri: $e');
    return [];
  }
});

/// Parameters for building a lineage graph
class LineageGraphParams {
  final String revisionKref;
  final String itemKref;
  final String itemName;
  final String itemKind;
  final String projectName;
  final String spacePath;
  final int revisionNumber;
  final List<String> tags;

  const LineageGraphParams({
    required this.revisionKref,
    required this.itemKref,
    required this.itemName,
    required this.itemKind,
    required this.projectName,
    required this.spacePath,
    required this.revisionNumber,
    this.tags = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineageGraphParams &&
          runtimeType == other.runtimeType &&
          revisionKref == other.revisionKref;

  @override
  int get hashCode => revisionKref.hashCode;
}

/// Provider that builds a complete lineage graph for a revision
/// Includes parent hierarchy (project > space > item > revision) and all edges
final lineageGraphProvider = FutureProvider.family<LineageGraphResult, LineageGraphParams>((ref, params) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) {
    return LineageGraphResult.empty();
  }

  try {
    // Fetch all edges for this revision (both directions)
    final edgesResponse = await client.getEdges(
      params.revisionKref,
      direction: EdgeDirection.BOTH,
    );
    final edges = edgesResponse.edges.map((e) => Edge(e, client)).toList();

    // Build nodes map for deduplication
    final nodesMap = <String, LineageNodeInfo>{};
    final graphEdges = <LineageEdgeInfo>[];

    // 1. Add the parent hierarchy: Project > Space(s) > Item > Revision
    final projectId = 'project:${params.projectName}';
    nodesMap[projectId] = LineageNodeInfo(
      id: projectId,
      name: params.projectName,
      type: 'project',
      kref: 'kref://${params.projectName}',
      metadata: {
        'Project': params.projectName,
      },
    );

    // Add space hierarchy
    final spaceParts = params.spacePath.split('/');
    String currentPath = params.projectName;
    String? previousSpaceId = projectId;
    
    for (int i = 0; i < spaceParts.length; i++) {
      final spaceName = spaceParts[i];
      currentPath = '$currentPath/$spaceName';
      final spaceId = 'space:$currentPath';
      final isSubSpace = i > 0;
      
      nodesMap[spaceId] = LineageNodeInfo(
        id: spaceId,
        name: spaceName,
        type: isSubSpace ? 'subSpace' : 'space',
        kref: 'kref://$currentPath',
        metadata: {
          'Space': spaceName,
          'Path': currentPath,
        },
      );
      
      // Edge from previous level to this space
      if (previousSpaceId != null) {
        graphEdges.add(LineageEdgeInfo(
          sourceId: previousSpaceId,
          targetId: spaceId,
          type: 'BELONGS_TO',
        ));
      }
      previousSpaceId = spaceId;
    }

    // 2. Add the item node
    final itemId = 'item:${params.itemKref}';
    nodesMap[itemId] = LineageNodeInfo(
      id: itemId,
      name: params.itemName,
      type: 'item',
      kref: params.itemKref,
      metadata: {
        'Item': params.itemName,
        'Kind': params.itemKind,
      },
    );
    
    // Edge from last space to item
    if (previousSpaceId != null) {
      graphEdges.add(LineageEdgeInfo(
        sourceId: previousSpaceId,
        targetId: itemId,
        type: 'BELONGS_TO',
      ));
    }

    // 3. Add the revision node (the focus node)
    final revisionId = 'revision:${params.revisionKref}';
    final latestTag = params.tags.contains('latest') ? ' (Latest)' : '';
    nodesMap[revisionId] = LineageNodeInfo(
      id: revisionId,
      name: 'v${params.revisionNumber}$latestTag',
      type: 'revision',
      kref: params.revisionKref,
      isFocus: true,
      metadata: {
        'Revision': params.revisionNumber.toString(),
        'Item': params.itemName,
        'Kind': params.itemKind,
        if (params.tags.isNotEmpty) 'Tags': params.tags.join(', '),
      },
    );
    
    // Edge from item to revision
    graphEdges.add(LineageEdgeInfo(
      sourceId: itemId,
      targetId: revisionId,
      type: 'BELONGS_TO',
    ));

    // 3.5. Fetch and add artifacts for the focused revision
    try {
      final artifacts = await client.getArtifacts(params.revisionKref);
      for (final artifact in artifacts) {
        final artifactName = artifact.name;
        final artifactKref = artifact.kref.uri;
        final artifactId = 'artifact:$artifactKref';
        
        // Determine artifact type based on file extension or kind
        String artifactType = 'artifact';
        final location = artifact.location.toLowerCase();
        if (location.endsWith('.png') || location.endsWith('.jpg') || 
            location.endsWith('.jpeg') || location.endsWith('.webp') ||
            location.endsWith('.gif')) {
          artifactType = 'image';
        } else if (location.endsWith('.safetensors') || location.endsWith('.ckpt') ||
                   location.endsWith('.pt')) {
          artifactType = 'model';
        } else if (location.endsWith('.json')) {
          artifactType = 'workflow';
        }
        
        nodesMap[artifactId] = LineageNodeInfo(
          id: artifactId,
          name: artifactName,
          type: artifactType,
          kref: artifactKref,
          metadata: {
            'Artifact': artifactName,
            'Location': artifact.location,
            'Type': artifactType,
            if (artifact.author.isNotEmpty) 'Author': artifact.author,
            if (artifact.createdAt.isNotEmpty) 'Created': artifact.createdAt,
          },
        );
        
        // Edge from revision to artifact (revision contains artifact)
        graphEdges.add(LineageEdgeInfo(
          sourceId: revisionId,
          targetId: artifactId,
          type: 'CONTAINS',
        ));
      }
    } catch (e) {
      debugPrint('Failed to fetch artifacts for revision: $e');
      // Continue without artifacts - they're optional
    }

    // 4. Process all edges from the API
    for (final edge in edges) {
      final sourceKref = edge.sourceKref.uri;
      final targetKref = edge.targetKref.uri;
      final edgeType = edge.edgeType;

      // Add source node if not already present
      final sourceId = 'revision:$sourceKref';
      if (!nodesMap.containsKey(sourceId) && sourceKref != params.revisionKref) {
        final sourceKrefObj = edge.sourceKref;
        
        // Parse the kref to get info
        final sourceNodeInfo = await _parseKrefToNodeInfo(
          client: client,
          kref: sourceKref,
          id: sourceId,
        );
        nodesMap[sourceId] = sourceNodeInfo;
        
        // Also add parent hierarchy for this external node
        await _addParentHierarchy(
          client: client,
          kref: sourceKref,
          nodesMap: nodesMap,
          graphEdges: graphEdges,
          nodeId: sourceId,
        );
      }

      // Add target node if not already present
      final targetId = 'revision:$targetKref';
      if (!nodesMap.containsKey(targetId) && targetKref != params.revisionKref) {
        final targetNodeInfo = await _parseKrefToNodeInfo(
          client: client,
          kref: targetKref,
          id: targetId,
        );
        nodesMap[targetId] = targetNodeInfo;
        
        // Also add parent hierarchy for this external node
        await _addParentHierarchy(
          client: client,
          kref: targetKref,
          nodesMap: nodesMap,
          graphEdges: graphEdges,
          nodeId: targetId,
        );
      }

      // Add the relationship edge
      final actualSourceId = sourceKref == params.revisionKref ? revisionId : 'revision:$sourceKref';
      final actualTargetId = targetKref == params.revisionKref ? revisionId : 'revision:$targetKref';
      
      graphEdges.add(LineageEdgeInfo(
        sourceId: actualSourceId,
        targetId: actualTargetId,
        type: edgeType,
      ));
    }

    return LineageGraphResult(
      nodes: nodesMap.values.toList(),
      edges: graphEdges,
      focusNodeId: revisionId,
    );
  } catch (e) {
    debugPrint('Failed to build lineage graph: $e');
    return LineageGraphResult.empty();
  }
});

/// Parse a kref URI to create node info
Future<LineageNodeInfo> _parseKrefToNodeInfo({
  required KumihoClient client,
  required String kref,
  required String id,
}) async {
  try {
    final krefObj = Kref(kref);
    final itemName = krefObj.itemName;
    final kind = krefObj.kind;
    final revision = krefObj.revision;
    
    // Determine node type based on kind
    String type = 'revision';
    if (kind == 'model' || kind == 'checkpoint') {
      type = 'model';
    } else if (kind == 'lora') {
      type = 'lora';
    } else if (kind == 'image') {
      type = 'image';
    } else if (kind == 'workflow') {
      type = 'workflow';
    }
    
    return LineageNodeInfo(
      id: id,
      name: revision != null ? '$itemName v$revision' : itemName,
      type: type,
      kref: kref,
      metadata: {
        'Item': itemName,
        if (kind != null) 'Kind': kind,
        if (revision != null) 'Revision': revision.toString(),
        'Project': krefObj.project,
        if (krefObj.space.isNotEmpty) 'Space': krefObj.space,
      },
    );
  } catch (e) {
    // Fallback if parsing fails
    return LineageNodeInfo(
      id: id,
      name: kref.split('/').last,
      type: 'revision',
      kref: kref,
    );
  }
}

/// Add parent hierarchy (project/space/item) for an external node
Future<void> _addParentHierarchy({
  required KumihoClient client,
  required String kref,
  required Map<String, LineageNodeInfo> nodesMap,
  required List<LineageEdgeInfo> graphEdges,
  required String nodeId,
}) async {
  try {
    final krefObj = Kref(kref);
    final project = krefObj.project;
    final space = krefObj.space;
    final itemKref = krefObj.itemKref.uri;
    
    // Add project if not present
    final projectId = 'project:$project';
    if (!nodesMap.containsKey(projectId)) {
      nodesMap[projectId] = LineageNodeInfo(
        id: projectId,
        name: project,
        type: 'project',
        kref: 'kref://$project',
      );
    }
    
    // Add space hierarchy
    String? previousId = projectId;
    if (space.isNotEmpty) {
      final spaceParts = space.split('/');
      String currentPath = project;
      
      for (int i = 0; i < spaceParts.length; i++) {
        final spaceName = spaceParts[i];
        currentPath = '$currentPath/$spaceName';
        final spaceId = 'space:$currentPath';
        
        if (!nodesMap.containsKey(spaceId)) {
          nodesMap[spaceId] = LineageNodeInfo(
            id: spaceId,
            name: spaceName,
            type: i > 0 ? 'subSpace' : 'space',
            kref: 'kref://$currentPath',
          );
          
          // Only add edge if it doesn't already exist
          final edgeExists = graphEdges.any((e) => 
            e.sourceId == previousId && e.targetId == spaceId && e.type == 'BELONGS_TO');
          if (!edgeExists && previousId != null) {
            graphEdges.add(LineageEdgeInfo(
              sourceId: previousId,
              targetId: spaceId,
              type: 'BELONGS_TO',
            ));
          }
        }
        previousId = spaceId;
      }
    }
    
    // Add item node
    final itemId = 'item:$itemKref';
    if (!nodesMap.containsKey(itemId)) {
      nodesMap[itemId] = LineageNodeInfo(
        id: itemId,
        name: krefObj.itemName,
        type: 'item',
        kref: itemKref,
      );
      
      // Edge from space to item
      if (previousId != null) {
        final edgeExists = graphEdges.any((e) => 
          e.sourceId == previousId && e.targetId == itemId && e.type == 'BELONGS_TO');
        if (!edgeExists) {
          graphEdges.add(LineageEdgeInfo(
            sourceId: previousId,
            targetId: itemId,
            type: 'BELONGS_TO',
          ));
        }
      }
    }
    
    // Edge from item to revision node
    final edgeExists = graphEdges.any((e) => 
      e.sourceId == itemId && e.targetId == nodeId && e.type == 'BELONGS_TO');
    if (!edgeExists) {
      graphEdges.add(LineageEdgeInfo(
        sourceId: itemId,
        targetId: nodeId,
        type: 'BELONGS_TO',
      ));
    }
  } catch (e) {
    debugPrint('Failed to add parent hierarchy for $kref: $e');
  }
}

/// Result of lineage graph building
class LineageGraphResult {
  final List<LineageNodeInfo> nodes;
  final List<LineageEdgeInfo> edges;
  final String? focusNodeId;

  const LineageGraphResult({
    required this.nodes,
    required this.edges,
    this.focusNodeId,
  });

  factory LineageGraphResult.empty() => const LineageGraphResult(
    nodes: [],
    edges: [],
  );

  bool get isEmpty => nodes.isEmpty;
}

/// Node info for lineage graph
class LineageNodeInfo {
  final String id;
  final String name;
  final String type;
  final String? kref;
  final bool isFocus;
  final Map<String, dynamic> metadata;

  const LineageNodeInfo({
    required this.id,
    required this.name,
    required this.type,
    this.kref,
    this.isFocus = false,
    this.metadata = const {},
  });
}

/// Edge info for lineage graph
class LineageEdgeInfo {
  final String sourceId;
  final String targetId;
  final String type;

  const LineageEdgeInfo({
    required this.sourceId,
    required this.targetId,
    required this.type,
  });
}

// ==================== LIST VIEW PROVIDERS ==================== //

/// Provider for child spaces in the current location (for list view mode)
/// Returns spaces that can be navigated into
final childSpacesListProvider = FutureProvider<List<SpaceListEntry>>((ref) async {
  ref.watch(kumihoRefreshTriggerProvider);
  
  final project = await ref.watch(selectedProjectProvider.future);
  if (project == null) {
    return [];
  }

  final spacePath = ref.watch(selectedSpacePathProvider);
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) {
    return [];
  }

  final queries = ref.watch(searchChipsProvider).map((q) => q.toLowerCase()).toList();

  try {
    List<Space> childSpaces;
    
    if (spacePath.isEmpty) {
      // At project root - get root spaces
      final spaces = await project.getSpaces();
      childSpaces = spaces.where((s) {
        final pathParts = s.path.split('/').where((p) => p.isNotEmpty).toList();
        return pathParts.length == 2; // /project/space (root level)
      }).toList();
    } else {
      // In a space - get child spaces
      final parentPath = '/${project.name}/${spacePath.join('/')}';
      final parentSpace = await client.space(parentPath);
      childSpaces = await parentSpace.getChildSpaces();
    }

    var entries = childSpaces.map((space) {
      // Extract just the space name from the path
      final pathParts = space.path.split('/').where((p) => p.isNotEmpty).toList();
      final spaceName = pathParts.isNotEmpty ? pathParts.last : space.path;
      
      return SpaceListEntry(
        spacePath: space.path,
        name: spaceName,
        author: space.author,
        username: space.username,
        createdAt: space.createdAt != null ? DateTime.tryParse(space.createdAt!) : null,
        modifiedAt: space.createdAt != null ? DateTime.tryParse(space.createdAt!) : null,
        deprecated: false, // Space doesn't have deprecated field
      );
    }).toList();

    if (queries.isNotEmpty) {
      entries = entries.where((entry) {
        final searchable = [
          entry.name,
          entry.author,
          entry.username,
        ].join(' ').toLowerCase();
        return queries.every(searchable.contains);
      }).toList();
    }

    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  } catch (e) {
    debugPrint('Failed to fetch spaces: $e');
    return [];
  }
});

/// Combined provider for list view - returns spaces first, then items
final listViewEntriesProvider = FutureProvider<List<ListViewEntry>>((ref) async {
  final spaces = await ref.watch(childSpacesListProvider.future);
  final items = await ref.watch(itemsListProvider.future);
  
  return <ListViewEntry>[
    ...spaces.map((s) => SpaceEntry(s)),
    ...items.map((i) => ItemEntry(i)),
  ];
});

/// Provider for items in the current space (for list view mode)
/// Returns items (not artifacts) for the item-centric list view
final itemsListProvider = FutureProvider<List<ItemListEntry>>((ref) async {
  // Watch refresh trigger to enable manual refresh
  ref.watch(kumihoRefreshTriggerProvider);
  
  final project = await ref.watch(selectedProjectProvider.future);
  if (project == null) {
    return [];
  }

  final spacePath = ref.watch(selectedSpacePathProvider);
  final filters = ref.watch(mediaFiltersProvider);
  final queries = ref.watch(searchChipsProvider).map((q) => q.toLowerCase()).toList();
  
  // If no space selected, use paged items from project root
  if (spacePath.isEmpty) {
    final pagedState = ref.watch(pagedItemsProvider);
    final uniqueItems = <String, ItemListEntry>{};
    
    for (final data in pagedState.items) {
      final item = data.item;
      if (!uniqueItems.containsKey(item.kref.uri)) {
        // Try to get revision info from the artifact data if available
        final revision = data.revision;
        final tags = revision?.tags ?? [];
        final modified = revision?.createdAt != null 
            ? DateTime.tryParse(revision!.createdAt!) 
            : null;

        uniqueItems[item.kref.uri] = ItemListEntry(
          itemKref: item.kref.uri,
          name: item.itemName,
          kind: item.kind,
          author: item.author,
          username: item.username,
          createdAt: item.createdAt != null ? DateTime.tryParse(item.createdAt!) : null,
          modifiedAt: modified,
          revisionCount: revision != null ? 1 : 0, // Approximate
          latestTags: tags,
          deprecated: item.deprecated,
          metadata: item.metadata,
        );
      }
    }

    var itemEntries = uniqueItems.values.toList();

    // Sort by modified date (newest first), then by name
    itemEntries.sort((a, b) {
      final dateCompare = (b.modifiedAt ?? b.createdAt ?? DateTime(1970))
          .compareTo(a.modifiedAt ?? a.createdAt ?? DateTime(1970));
      if (dateCompare != 0) return dateCompare;
      return a.name.compareTo(b.name);
    });

    // Apply date filters (Today/Week)
    final hasDateFilter = filters.contains(MediaFilterType.today) || filters.contains(MediaFilterType.week);
    if (hasDateFilter) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(const Duration(days: 7));

      itemEntries = itemEntries.where((item) {
        final itemDate = item.modifiedAt ?? item.createdAt;
        if (itemDate == null) return false;

        final matchesToday = filters.contains(MediaFilterType.today) && itemDate.isAfter(todayStart);
        final matchesWeek = filters.contains(MediaFilterType.week) && itemDate.isAfter(weekStart);
        return matchesToday || matchesWeek;
      }).toList();
    }

    // Apply search query filter
    if (queries.isNotEmpty) {
      itemEntries = itemEntries.where((item) {
        final searchableText = [
          item.name,
          item.kind,
          item.author,
          item.username,
          ...item.latestTags,
          ...item.metadata.values.map((v) => v.toString()),
        ].join(' ').toLowerCase();
        return queries.every(searchableText.contains);
      }).toList();
    }

    return itemEntries;
  }

  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) {
    return [];
  }

  final includeDeprecated = ref.watch(includeDeprecatedProvider);

  // Build context filter for itemSearch
  final contextFilter = '${project.name}/${spacePath.join('/')}';
  
  try {
    final itemResponses = await _itemSearchCompat(
      client,
      '$contextFilter/', // enforce project/space prefix
      '',
      '',
      includeDeprecated: includeDeprecated,
    );
    
    final itemEntries = <ItemListEntry>[];
    
    for (final itemResponse in itemResponses) {
      final item = Item(itemResponse, client);
      if (item.projectName != project.name) continue;
      if (!includeDeprecated && item.deprecated) continue;

      // IMPORTANT: Avoid eager per-item revision fetches in list view.
      // Revisions are loaded lazily by the detail panel for the selected item.
      // We still populate modifiedAt from ItemResponse (cheap) so sorting works.
      final latestModified = itemResponse.modifiedAt.isNotEmpty
          ? DateTime.tryParse(itemResponse.modifiedAt)
          : null;
      
      itemEntries.add(ItemListEntry(
        itemKref: item.kref.uri,
        name: item.itemName,
        kind: item.kind,
        author: item.author,
        username: item.username,
        createdAt: item.createdAt != null ? DateTime.tryParse(item.createdAt!) : null,
        modifiedAt: latestModified,
        revisionCount: -1, // Unknown in list view until item is selected
        latestTags: const [],
        deprecated: item.deprecated,
        metadata: item.metadata,
      ));
    }
    
    // Sort by modified date (newest first), then by name
    itemEntries.sort((a, b) {
      final dateCompare = (b.modifiedAt ?? b.createdAt ?? DateTime(1970))
          .compareTo(a.modifiedAt ?? a.createdAt ?? DateTime(1970));
      if (dateCompare != 0) return dateCompare;
      return a.name.compareTo(b.name);
    });
    
    // Apply date filters (Today/Week)
    var filteredEntries = itemEntries;
    
    final hasDateFilter = filters.contains(MediaFilterType.today) || filters.contains(MediaFilterType.week);
    if (hasDateFilter) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(const Duration(days: 7));
      
      filteredEntries = itemEntries.where((item) {
        final itemDate = item.modifiedAt ?? item.createdAt;
        if (itemDate == null) return false;
        
        final matchesToday = filters.contains(MediaFilterType.today) && itemDate.isAfter(todayStart);
        final matchesWeek = filters.contains(MediaFilterType.week) && itemDate.isAfter(weekStart);
        return matchesToday || matchesWeek;
      }).toList();
    }
    
    // Apply search query filter
    if (queries.isNotEmpty) {
      filteredEntries = filteredEntries.where((item) {
        final searchableText = [
          item.name,
          item.kind,
          item.author,
          item.username,
          ...item.latestTags,
          ...item.metadata.values.map((v) => v.toString()),
        ].join(' ').toLowerCase();
        return queries.every(searchableText.contains);
      }).toList();
    }
    
    return filteredEntries;
  } catch (e) {
    debugPrint('Failed to search items: $e');
    return [];
  }
});

/// Provider for revisions of a specific item (for detail panel)
final itemRevisionsProvider = FutureProvider.family<List<RevisionListEntry>, String>((ref, itemKref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) {
    return [];
  }

  try {
    final revisions = await client.getRevisions(itemKref);
    
    final entries = revisions.map((rev) {
      final revision = Revision(rev, client);
      return RevisionListEntry(
        revisionKref: revision.kref.uri,
        number: revision.number,
        tags: revision.tags,
        author: revision.author,
        username: revision.username,
        createdAt: revision.createdAt != null ? DateTime.tryParse(revision.createdAt!) : null,
        modifiedAt: revision.createdAt != null ? DateTime.tryParse(revision.createdAt!) : null,
        isLatest: revision.latest,
        isPublished: revision.published,
        deprecated: revision.deprecated,
        metadata: revision.metadata,
        defaultArtifact: revision.defaultArtifact,
      );
    }).toList();
    
    // Sort by revision number (newest first)
    entries.sort((a, b) => b.number.compareTo(a.number));
    
    return entries;
  } catch (e) {
    debugPrint('Failed to fetch revisions: $e');
    return [];
  }
});

/// Provider for artifacts of a specific revision (for detail panel)
final revisionArtifactsProvider = FutureProvider.family<List<ArtifactListEntry>, String>((ref, revisionKref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) {
    return [];
  }

  try {
    final artifacts = await client.getArtifacts(revisionKref);
    
    final entries = artifacts.map((art) {
      return ArtifactListEntry(
        artifactKref: art.kref.uri,
        name: art.name,
        location: art.location,
        author: art.author,
        username: art.username,
        createdAt: art.createdAt.isNotEmpty ? DateTime.tryParse(art.createdAt) : null,
        modifiedAt: art.modifiedAt.isNotEmpty ? DateTime.tryParse(art.modifiedAt) : null,
        deprecated: art.deprecated,
        metadata: Map<String, String>.from(art.metadata),
      );
    }).toList();
    
    // Sort by name
    entries.sort((a, b) => a.name.compareTo(b.name));
    
    return entries;
  } catch (e) {
    debugPrint('Failed to fetch artifacts: $e');
    return [];
  }
});

/// Provider for full revision details (metadata for info panel)
final revisionDetailProvider = FutureProvider.family<RevisionListEntry?, String>((ref, revisionKref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  if (client == null) return null;

  try {
    final response = await client.getRevision(revisionKref);
    final revision = Revision(response, client);
    
    return RevisionListEntry(
      revisionKref: revision.kref.uri,
      number: revision.number,
      tags: revision.tags,
      author: revision.author,
      username: revision.username,
      createdAt: revision.createdAt != null ? DateTime.tryParse(revision.createdAt!) : null,
      modifiedAt: revision.createdAt != null ? DateTime.tryParse(revision.createdAt!) : null,
      isLatest: revision.latest,
      isPublished: revision.published,
      deprecated: revision.deprecated,
      metadata: revision.metadata,
      defaultArtifact: revision.defaultArtifact,
    );
  } catch (e) {
    debugPrint('Failed to fetch revision: $e');
    return null;
  }
});

/// State provider for list view selection
final listViewSelectionProvider = StateProvider<ListViewSelection>((ref) => const ListViewSelection());

/// Notifier for managing list view selection state
class ListViewSelectionNotifier extends StateNotifier<ListViewSelection> {
  ListViewSelectionNotifier() : super(const ListViewSelection());

  void selectItem(ItemListEntry? item) {
    state = ListViewSelection(
      selectedItem: item,
      selectedRevision: null,  // Clear revision when item changes
      selectedArtifact: null,  // Clear artifact when item changes
    );
  }

  void selectRevision(RevisionListEntry? revision) {
    state = state.copyWith(
      selectedRevision: revision,
      clearArtifact: true,  // Clear artifact when revision changes
    );
  }

  void selectArtifact(ArtifactListEntry? artifact) {
    state = state.copyWith(selectedArtifact: artifact);
  }

  void clearAll() {
    state = const ListViewSelection();
  }
}

/// StateNotifier provider for list view selection
final listViewSelectionNotifierProvider = StateNotifierProvider<ListViewSelectionNotifier, ListViewSelection>((ref) {
  return ListViewSelectionNotifier();
});
