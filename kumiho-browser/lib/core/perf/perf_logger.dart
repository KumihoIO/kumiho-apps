import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PerfLogger {
  PerfLogger._();

  static final DateTime _appStart = DateTime.now();
  static final Stopwatch _sinceStart = Stopwatch()..start();

  /// Enable with: `--dart-define=PERF_LOG=1`
  static const bool enabled =
      String.fromEnvironment('PERF_LOG', defaultValue: '0') == '1';

  /// Log slow frames above this threshold.
  static const int slowFrameThresholdMs = 32;

  static int _slowFrameLogCount = 0;
  static DateTime _slowFrameWindowStart = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _lastSlowFrameLog = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _frameTimingsInstalled = false;
  static Timer? _stallTimer;
  static int _lastStallTickMs = 0;

  static void log(String message) {
    if (!enabled) return;
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    final sinceStartMs = _sinceStart.elapsedMilliseconds;
    debugPrint('[PERF $h:$m:$s.$ms +${sinceStartMs}ms] $message');
  }

  static int sinceStartMs() {
    // Prefer monotonic time (Stopwatch) to avoid issues if wall clock changes.
    return _sinceStart.elapsedMilliseconds;
  }

  static void mark(String name, {Map<String, Object?>? fields}) {
    if (!enabled) return;
    log('$name +${sinceStartMs()}ms${_fmtFields(fields)}');
  }

  static String _fmtFields(Map<String, Object?>? fields) {
    if (fields == null || fields.isEmpty) return '';
    final parts = <String>[];
    for (final entry in fields.entries) {
      parts.add('${entry.key}=${entry.value}');
    }
    return ' (${parts.join(', ')})';
  }

  static T timeSync<T>(
    String name,
    T Function() fn, {
    Map<String, Object?>? fields,
  }) {
    if (!enabled) return fn();
    final sw = Stopwatch()..start();
    try {
      return fn();
    } finally {
      sw.stop();
      log('$name ${sw.elapsedMilliseconds}ms${_fmtFields(fields)}');
    }
  }

  static Future<T> timeAsync<T>(
    String name,
    Future<T> Function() fn, {
    Map<String, Object?>? fields,
  }) async {
    if (!enabled) return await fn();
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      sw.stop();
      log('$name ${sw.elapsedMilliseconds}ms${_fmtFields(fields)}');
    }
  }

  /// Installs a frame timing callback that logs slow frames.
  ///
  /// This is intentionally lightweight and rate-limited.
  static void installFrameTimingsIfEnabled() {
    if (!enabled) return;
    if (_frameTimingsInstalled) return;
    _frameTimingsInstalled = true;

    // Log when the first frame is scheduled and when it completes.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      log('First frame rendered +${sinceStartMs()}ms');
    });

    // Detect long periods where the main isolate (Flutter UI thread) is not
    // making progress. This logs only when we observe a large tick gap, so it
    // should stay low-noise even with PERF_LOG enabled.
    _lastStallTickMs = sinceStartMs();
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final nowMs = sinceStartMs();
      final delta = nowMs - _lastStallTickMs;
      _lastStallTickMs = nowMs;

      // If the timer itself fires late, the main isolate was stalled.
      if (delta >= 1000) {
        log('Main isolate stall detected: ${delta}ms without a timer tick');
      }
    });

    SchedulerBinding.instance.addTimingsCallback((timings) {
      final now = DateTime.now();

      // Reset window every 10s.
      if (now.difference(_slowFrameWindowStart).inSeconds >= 10) {
        _slowFrameWindowStart = now;
        _slowFrameLogCount = 0;
      }

      for (final t in timings) {
        final buildMs = t.buildDuration.inMilliseconds;
        final rasterMs = t.rasterDuration.inMilliseconds;
        final totalMs = t.totalSpan.inMilliseconds;

        final isSlow = buildMs >= slowFrameThresholdMs ||
            rasterMs >= slowFrameThresholdMs ||
            totalMs >= slowFrameThresholdMs;
        if (!isSlow) continue;

        // Rate-limit: max 8 logs per 10s, and at most one every 250ms.
        if (_slowFrameLogCount >= 8) return;
        if (now.difference(_lastSlowFrameLog).inMilliseconds < 250) continue;

        _slowFrameLogCount++;
        _lastSlowFrameLog = now;

        log('Slow frame: build=${buildMs}ms raster=${rasterMs}ms total=${totalMs}ms');
      }
    });

    // Helpful one-time banner so it's obvious this is on.
    scheduleMicrotask(() {
      log('Perf logging enabled (slow frames >= ${slowFrameThresholdMs}ms).');
    });
  }
}
