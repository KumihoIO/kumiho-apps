// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kumiho/kumiho.dart';

import '../providers/kumiho_provider.dart';
import '../providers/settings_provider.dart';

/// Widget that manages auto-refresh timer based on settings.
/// Wraps child widget and handles timer lifecycle automatically.
class AutoRefreshController extends ConsumerStatefulWidget {
  final Widget child;

  const AutoRefreshController({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AutoRefreshController> createState() => _AutoRefreshControllerState();
}

class _AutoRefreshControllerState extends ConsumerState<AutoRefreshController> {
  Timer? _refreshTimer;
  Timer? _streamRetryTimer;
  StreamSubscription<Event>? _eventSub;
  DateTime? _lastRefreshTime;
  String? _activeKrefFilter;

  @override
  void initState() {
    super.initState();
    // Timer will be started by the first build via the listener
  }

  @override
  void dispose() {
    _stopEventStream();
    _stopTimer();
    super.dispose();
  }

  void _startTimer(int intervalSeconds) {
    _stopTimer();
    if (intervalSeconds <= 0) {
      return; // Real-time only, no fallback timer
    }

    _refreshTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _triggerRefresh(),
    );
  }

  void _stopTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _stopEventStream() {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = null;
    _eventSub?.cancel();
    _eventSub = null;
    _activeKrefFilter = null;
  }

  void _triggerRefresh() {
    final now = DateTime.now();
    if (_lastRefreshTime != null && now.difference(_lastRefreshTime!) < const Duration(milliseconds: 500)) {
      return; // Throttle bursts from streams
    }

    _lastRefreshTime = now;
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  String _buildKrefFilter(String projectName, List<String> spacePath) {
    // For project root, allow any depth (including items directly under the project)
    if (spacePath.isEmpty) {
      return 'kref://$projectName/**';
    }

    final scopedPath = '${spacePath.join('/')}/**';
    return 'kref://$projectName/$scopedPath';
  }

  Future<void> _startEventStream(String krefFilter) async {
    final client = await ref.read(kumihoClientProvider.future);
    if (client == null) return;

    if (_activeKrefFilter == krefFilter && _eventSub != null) return;

    await _eventSub?.cancel();
    _activeKrefFilter = krefFilter;

    _eventSub = client.eventStream(krefFilter: krefFilter).listen(
      (event) => _triggerRefresh(),
      onError: (e, st) {
        debugPrint('Event stream error: $e');
        _stopEventStream();
        // Retry once after a short backoff to handle transient disconnects
        _streamRetryTimer = Timer(const Duration(seconds: 5), () {
          final settings = ref.read(settingsProvider);
          if (settings.autoRefreshEnabled) {
            _refreshRealtimeSubscription(settings: settings);
          }
        });
      },
      cancelOnError: true,
    );
  }

  Future<void> _refreshRealtimeSubscription({AppSettings? settings}) async {
    final currentSettings = settings ?? ref.read(settingsProvider);
    if (currentSettings == null || !currentSettings.autoRefreshEnabled) {
      _stopEventStream();
      return;
    }

    final project = await ref.read(selectedProjectProvider.future);
    if (project == null) {
      _stopEventStream();
      return;
    }

    final spacePath = ref.read(selectedSpacePathProvider);
    final krefFilter = _buildKrefFilter(project.name, spacePath);
    await _startEventStream(krefFilter);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to settings changes
    ref.listen<AppSettings>(settingsProvider, (previous, current) {
      final wasEnabled = previous?.autoRefreshEnabled ?? false;
      final isEnabled = current.autoRefreshEnabled;
      final prevInterval = previous?.autoRefreshIntervalSeconds ?? 300;
      final newInterval = current.autoRefreshIntervalSeconds;

      // Handle enable/disable
      if (isEnabled && !wasEnabled) {
        _startTimer(newInterval);
        _refreshRealtimeSubscription(settings: current);
      } else if (!isEnabled && wasEnabled) {
        _stopTimer();
        _stopEventStream();
      } else if (isEnabled && prevInterval != newInterval) {
        // Interval changed while enabled - restart timer
        _startTimer(newInterval);
      }
    });

    // Keep event stream scoped to the current project/space
    ref.listen<AsyncValue<Project?>>(selectedProjectProvider, (prev, next) {
      if (next.hasValue) {
        _refreshRealtimeSubscription();
      } else if (next.hasError) {
        _stopEventStream();
      }
    });

    ref.listen<List<String>>(selectedSpacePathProvider, (prev, next) {
      if (prev != next) {
        _refreshRealtimeSubscription();
      }
    });

    // On first build, check if auto-refresh should be active
    final settings = ref.watch(settingsProvider);
    if (settings.autoRefreshEnabled && _refreshTimer == null) {
      // Use post-frame callback to start timer after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && settings.autoRefreshEnabled) {
          _startTimer(settings.autoRefreshIntervalSeconds);
          _refreshRealtimeSubscription(settings: settings);
        }
      });
    }

    return widget.child;
  }
}
