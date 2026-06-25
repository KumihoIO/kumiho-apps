// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

/// Kumiho Browser - Main Entry Point
///
/// A desktop application for browsing and managing creative assets
/// using the Kumiho Cloud platform.
///
/// Run with:
/// - Development: flutter run -d windows
/// - Production:  flutter run -d windows --dart-define=ENVIRONMENT=production
///
/// Or use the helper scripts in scripts/

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants/firebase_config.dart';
import 'core/perf/perf_logger.dart';
import 'pages/pages.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'theme/kumiho_theme.dart';
import 'widgets/auto_refresh_controller.dart';
import 'widgets/keyboard_shortcuts_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional perf logging (slow frames + timed sections). Enable with:
  // `--dart-define=PERF_LOG=1`
  PerfLogger.installFrameTimingsIfEnabled();

  final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  // Log environment configuration
  debugPrint('╔════════════════════════════════════════════════════════════╗');
  debugPrint('║  Kumiho Browser                                            ║');
  debugPrint('║  Environment: ${Environment.current.padRight(43)}║');
  debugPrint('║  Control Plane: ${KumihoConfig.controlPlaneUrl.padRight(40)}║');
  debugPrint('╚════════════════════════════════════════════════════════════╝');

  // Debug/bisection mode: run the smallest possible Flutter app to determine
  // whether the Windows startup stall is caused by our app/plugin calls or by
  // the Flutter engine/driver environment.
  final minimalStartup =
      const String.fromEnvironment('MIN_STARTUP', defaultValue: '0') == '1';
  if (minimalStartup) {
    if (PerfLogger.enabled) {
      PerfLogger.log('MIN_STARTUP enabled: skipping Firebase/window_manager/providers');
    }

    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text('MIN_STARTUP'),
          ),
        ),
      ),
    );

    // Keep the same diagnostic timers so we can detect stalls in minimal mode.
    if (PerfLogger.enabled) {
      scheduleMicrotask(() {
        PerfLogger.mark('main: first microtask after runApp');
      });
      Future<void>.delayed(Duration.zero).then((_) {
        PerfLogger.mark('main: first Timer(Duration.zero) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 100)).then((_) {
        PerfLogger.mark('main: Timer(100ms) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        PerfLogger.mark('main: Timer(500ms) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 1000)).then((_) {
        PerfLogger.mark('main: Timer(1s) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 2000)).then((_) {
        PerfLogger.mark('main: Timer(2s) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 5000)).then((_) {
        PerfLogger.mark('main: Timer(5s) after runApp');
      });
      Future<void>.delayed(const Duration(milliseconds: 10000)).then((_) {
        PerfLogger.mark('main: Timer(10s) after runApp');
      });
    }

    return;
  }

  // Initialize MediaKit for video playback
  // NOTE (Windows): media_kit native initialization has been observed to
  // intermittently stall the UI thread for ~20-30s on some machines. Defer
  // initialization until the user actually needs video features.
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (!isWindows) {
    try {
      MediaKit.ensureInitialized();
    } catch (e, st) {
      // Do not crash the entire app if native media dependencies are missing.
      // The UI should still render, and media features can fail gracefully.
      debugPrint('MediaKit initialization failed: $e');
      debugPrintStack(stackTrace: st);
    }
  } else {
    if (PerfLogger.enabled) {
      PerfLogger.log('MediaKit.ensureInitialized deferred on Windows');
    }
    // Best-effort warmup shortly after startup.
    // NOTE: Must run on the main isolate; media_kit uses platform channels.
    unawaited(Future<void>.delayed(const Duration(seconds: 1), () {
      try {
        if (PerfLogger.enabled) {
          PerfLogger.log('MediaKit.ensureInitialized (delayed) START');
        }
        MediaKit.ensureInitialized();
        if (PerfLogger.enabled) {
          PerfLogger.log('MediaKit.ensureInitialized (delayed) DONE');
        }
      } catch (e, st) {
        debugPrint('MediaKit initialization failed (delayed): $e');
        debugPrintStack(stackTrace: st);
      }
    }));
  }

  // Initialize Firebase.
  //
  // On desktop, Firebase is enabled by default for production builds.
  // For development, pass --dart-define=ENABLE_FIREBASE_DESKTOP=true or use
  // the -firebase-desktop flag in run_dev.ps1.
  //
  // Set ENABLE_FIREBASE_DESKTOP=false to explicitly disable on desktop.
  final enableFirebaseDesktopOverride =
      const String.fromEnvironment('ENABLE_FIREBASE_DESKTOP');
  final enableFirebaseDesktop = enableFirebaseDesktopOverride.isEmpty
      ? Environment.isProduction  // Default: enabled for production
      : enableFirebaseDesktopOverride.toLowerCase() == 'true';
  // This starts as the *requested* Firebase state, but may be flipped to false
  // if initialization fails (e.g. missing native config on macOS).
  var firebaseEnabled = kIsWeb || enableFirebaseDesktop;

  debugPrint('[Firebase] Platform: ${kIsWeb ? "web" : "desktop"}, '
      'Environment: ${Environment.current}, '
      'Firebase enabled: $firebaseEnabled');

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        authDomain: FirebaseConfig.authDomain,
        projectId: FirebaseConfig.projectId,
        appId: FirebaseConfig.appId,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        storageBucket: FirebaseConfig.storageBucket,
      ),
    );
    debugPrint('[Firebase] Web initialization complete');
  } else if (enableFirebaseDesktop) {
    // Desktop (Windows/Linux/macOS):
    // - Windows/Linux: initialize from explicit options (no native config files).
    // - macOS: prefer *native* configuration (GoogleService-Info.plist) if present.
    //   Passing explicit options on macOS can crash if a default app was configured
    //   natively by another plugin at nearly the same time (SIGABRT in FIRApp).
    try {
      if (isMacOS) {
        await Firebase.initializeApp();
        debugPrint('[Firebase] macOS initialization complete (native config)');
      } else {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: FirebaseConfig.apiKey,
            authDomain: FirebaseConfig.authDomain,
            projectId: FirebaseConfig.projectId,
            appId: FirebaseConfig.appId,
            messagingSenderId: FirebaseConfig.messagingSenderId,
            storageBucket: FirebaseConfig.storageBucket,
          ),
        );
        debugPrint('[Firebase] Desktop initialization complete');
      }
    } catch (e, st) {
      // If Firebase fails to initialize on desktop, don't crash the whole app.
      // Disable Firebase-dependent features for this run.
      firebaseEnabled = false;
      debugPrint('[Firebase] Desktop initialization FAILED (Firebase disabled): $e');
      debugPrintStack(stackTrace: st);
    }
  } else {
    debugPrint('[Firebase] Skipped (desktop Firebase disabled)');
  }

  // Initialize window manager for desktop
  if (PerfLogger.enabled) {
    PerfLogger.mark('windowManager.ensureInitialized START');
  }
  await windowManager.ensureInitialized();
  if (PerfLogger.enabled) {
    PerfLogger.mark('windowManager.ensureInitialized DONE');
  }

  final windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    // On macOS we prefer the native title bar (traffic lights + centered title).
    // On Windows/Linux we use a custom title bar for a more consistent look.
    titleBarStyle: isMacOS ? TitleBarStyle.normal : TitleBarStyle.hidden,
    title: 'Kumiho Browser',
  );

  if (PerfLogger.enabled) {
    PerfLogger.mark('windowManager.waitUntilReadyToShow START');
  }
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (PerfLogger.enabled) {
      PerfLogger.mark('windowManager.show START');
    }
    await windowManager.show();
    if (PerfLogger.enabled) {
      PerfLogger.mark('windowManager.show DONE');
    }

    if (PerfLogger.enabled) {
      PerfLogger.mark('windowManager.focus START');
    }
    await windowManager.focus();
    if (PerfLogger.enabled) {
      PerfLogger.mark('windowManager.focus DONE');
    }
  });
  if (PerfLogger.enabled) {
    PerfLogger.mark('windowManager.waitUntilReadyToShow DONE');
  }

  runApp(
    ProviderScope(
      overrides: [
        firebaseEnabledProvider.overrideWithValue(firebaseEnabled),
      ],
      child: const KumihoAssetBrowserApp(),
    ),
  );

  // Diagnostic: check when the event loop is actually free after startup
  if (PerfLogger.enabled) {
    scheduleMicrotask(() {
      PerfLogger.mark('main: first microtask after runApp');
    });
    Future<void>.delayed(Duration.zero).then((_) {
      PerfLogger.mark('main: first Timer(Duration.zero) after runApp');
    });
    Future<void>.delayed(const Duration(milliseconds: 100)).then((_) {
      PerfLogger.mark('main: Timer(100ms) after runApp');
    });
    // More granular timers to detect when the stall begins
    Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
      PerfLogger.mark('main: Timer(500ms) after runApp');
    });
    Future<void>.delayed(const Duration(milliseconds: 1000)).then((_) {
      PerfLogger.mark('main: Timer(1s) after runApp');
    });
    Future<void>.delayed(const Duration(milliseconds: 2000)).then((_) {
      PerfLogger.mark('main: Timer(2s) after runApp');
    });
    Future<void>.delayed(const Duration(milliseconds: 5000)).then((_) {
      PerfLogger.mark('main: Timer(5s) after runApp');
    });
    Future<void>.delayed(const Duration(milliseconds: 10000)).then((_) {
      PerfLogger.mark('main: Timer(10s) after runApp');
    });
  }
}

/// Main application widget for Kumiho Browser
class KumihoAssetBrowserApp extends ConsumerWidget {
  const KumihoAssetBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipAppProviders =
        const String.fromEnvironment('SKIP_APP_PROVIDERS', defaultValue: '0') ==
            '1';

    if (skipAppProviders) {
      if (PerfLogger.enabled) {
        PerfLogger.log('SKIP_APP_PROVIDERS enabled: not watching providers/widgets');
      }

      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: Text('SKIP_APP_PROVIDERS')),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    // Keep Firebase auth token refreshed in the background.
    ref.watch(authTokenAutoRefreshProvider);

    final skipHomeUi =
      const String.fromEnvironment('SKIP_HOME_UI', defaultValue: '0') == '1';

    final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    
    return MaterialApp(
      title: 'Kumiho Browser',
      debugShowCheckedModeBanner: false,
      themeMode: settings.useDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: KumihoTheme.lightTheme,
      darkTheme: KumihoTheme.darkTheme,
      builder: (context, child) {
        // Apply global font scale based on user settings
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.uiFontScale),
          ),
          child: child!,
        );
      },
      home: skipHomeUi
          ? const Scaffold(body: Center(child: Text('SKIP_HOME_UI')))
          : AutoRefreshController(
              child: KeyboardShortcutsHandler(
                child: isMacOS
                    ? const MediaBrowserPage()
                    : _WindowFrame(child: const MediaBrowserPage()),
              ),
            ),
    );
  }
}

/// Custom window frame with title bar for dragging and window controls
class _WindowFrame extends StatefulWidget {
  final Widget child;
  const _WindowFrame({required this.child});

  @override
  State<_WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<_WindowFrame> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // IMPORTANT (Windows): window_manager.isMaximized() has been observed to
    // stall the main isolate for ~20s+ (see PERF logs). Do not query on startup.
    // Instead, rely on WindowListener callbacks to keep state updated.
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (!isWindows) {
      unawaited(_init());
    }
  }

  Future<void> _init() async {
    if (PerfLogger.enabled) {
      PerfLogger.mark('_WindowFrameState._init START');
    }

    try {
      if (PerfLogger.enabled) {
        PerfLogger.mark('_WindowFrameState: windowManager.isMaximized() START');
      }
      _isMaximized = await windowManager.isMaximized();
      if (PerfLogger.enabled) {
        PerfLogger.mark('_WindowFrameState: windowManager.isMaximized() DONE');
      }
    } catch (e, st) {
      debugPrint('windowManager.isMaximized failed: $e');
      debugPrintStack(stackTrace: st);
    }

    if (!mounted) return;
    setState(() {});

    if (PerfLogger.enabled) {
      PerfLogger.mark('_WindowFrameState._init DONE');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Custom title bar
        GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: () async {
            if (_isMaximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          child: Container(
            height: 32,
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                const SizedBox(width: 12),
                // App icon/title
                Image.asset(
                  'assets/icons/common/icon_16x16.png',
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Kumiho Browser',
                  style: TextStyle(
                    color: KumihoTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                // Window controls
                _WindowButton(
                  icon: Icons.remove,
                  onPressed: () => windowManager.minimize(),
                ),
                _WindowButton(
                  icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                  iconSize: _isMaximized ? 14 : 16,
                  onPressed: () async {
                    if (_isMaximized) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  },
                ),
                _WindowButton(
                  icon: Icons.close,
                  hoverColor: Colors.red,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ),
        // Main content
        Expanded(child: widget.child),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color? hoverColor;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.iconSize = 16,
    this.hoverColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _isHovered && widget.hoverColor != null
                ? Colors.white
                : KumihoTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
