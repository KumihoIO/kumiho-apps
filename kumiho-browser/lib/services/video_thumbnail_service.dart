// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/perf/perf_logger.dart';
import '../core/utils/media_source.dart';

/// Service for extracting thumbnails from video files
class VideoThumbnailService {
  static final VideoThumbnailService _instance = VideoThumbnailService._internal();
  factory VideoThumbnailService() => _instance;
  VideoThumbnailService._internal();

  // NOTE: media_kit uses platform channels; initialization must happen on the
  // main isolate.
  static Future<void>? _mediaKitInit;

  static Future<void> _ensureMediaKitInitialized() {
    final existing = _mediaKitInit;
    if (existing != null) return existing;

    final fut = () async {
      if (kIsWeb) return;
      MediaKit.ensureInitialized();
    }();

    _mediaKitInit = fut;
    return fut;
  }

  // Cache directory for thumbnails
  String? _cacheDir;

  // Serialize initialization to avoid a stampede of platform calls on startup.
  Future<void>? _initFuture;
  
  // In-memory cache of thumbnail paths
  final Map<String, String> _thumbnailCache = {};
  
  // Track pending extractions to avoid duplicates
  final Map<String, Completer<String?>> _pendingExtractions = {};

  // Serialize extraction work. On Windows, creating multiple media_kit Players
  // in parallel during startup can stall the main isolate.
  Future<void> _extractionChain = Future.value();
  
  // Cache settings (can be updated from settings)
  int _maxCacheSizeMb = 500;
  bool _autoClearEnabled = false;

  /// Update cache settings
  void updateSettings({int? maxCacheSizeMb, bool? autoClearEnabled}) {
    if (maxCacheSizeMb != null) _maxCacheSizeMb = maxCacheSizeMb;
    if (autoClearEnabled != null) _autoClearEnabled = autoClearEnabled;
  }

  /// Initialize the service and create cache directory
  Future<void> init() async {
    if (_cacheDir != null) return;
    if (_initFuture != null) return _initFuture;

    final startMs = PerfLogger.sinceStartMs();
    if (PerfLogger.enabled) {
      PerfLogger.log('VideoThumbnailService.init START +${startMs}ms');
    }

    final completer = Completer<void>();
    _initFuture = completer.future;

    try {
      final appDir = await getApplicationSupportDirectory();
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnailService.init got app dir (${appDir.path})');
      }
      _cacheDir = path.join(appDir.path, 'video_thumbnails');
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      if (PerfLogger.enabled) {
        final endMs = PerfLogger.sinceStartMs();
        PerfLogger.log('VideoThumbnailService.init END +${endMs}ms');
      }
    }
  }

  /// Get thumbnail for a video file
  /// Returns the path to the cached thumbnail, or null if extraction fails
  Future<String?> getThumbnail(String videoPath) async {
    if (PerfLogger.enabled) {
      PerfLogger.log('VideoThumbnailService.getThumbnail START pathHash=${videoPath.hashCode}');
    }
    await init();
    
    // Generate a unique key for this video
    final cacheKey = _getCacheKey(videoPath);
    
    // Check memory cache first
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey];
    }
    
    // Check disk cache
    final thumbnailPath = path.join(_cacheDir!, '$cacheKey.jpg');
    if (PerfLogger.enabled) {
      PerfLogger.log('VideoThumbnailService.getThumbnail diskCheck key=$cacheKey');
    }
    if (await File(thumbnailPath).exists()) {
      _thumbnailCache[cacheKey] = thumbnailPath;
      return thumbnailPath;
    }
    
    // Check if extraction is already pending
    if (_pendingExtractions.containsKey(cacheKey)) {
      return _pendingExtractions[cacheKey]!.future;
    }
    
    // Start new extraction
    final completer = Completer<String?>();
    _pendingExtractions[cacheKey] = completer;
    
    try {
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnailService.getThumbnail queueExtract key=$cacheKey');
      }
      final result = await _runSerializedExtraction(
        label: cacheKey,
        action: () => _extractThumbnail(videoPath, thumbnailPath),
      );
      if (result != null) {
        _thumbnailCache[cacheKey] = result;
        // Check cache size and auto-clear if needed
        if (_autoClearEnabled) {
          _checkAndEnforceCacheLimit();
        }
      }
      completer.complete(result);
    } catch (e) {
      debugPrint('VideoThumbnailService: Error extracting thumbnail: $e');
      completer.complete(null);
    } finally {
      _pendingExtractions.remove(cacheKey);
    }
    
    return completer.future;
  }

  Future<T> _runSerializedExtraction<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    final start = DateTime.now();

    // Queue behind any ongoing extraction.
    final previous = _extractionChain;
    final gate = Completer<void>();
    _extractionChain = previous.whenComplete(() => gate.future);

    await previous;
    if (PerfLogger.enabled) {
      PerfLogger.log('VideoThumbnailService.extract START key=$label');
    }

    try {
      // Yield once before doing any heavy work.
      await Future<void>.delayed(Duration.zero);
      return await action();
    } finally {
      gate.complete();
      if (PerfLogger.enabled) {
        final ms = DateTime.now().difference(start).inMilliseconds;
        PerfLogger.log('VideoThumbnailService.extract END key=$label (${ms}ms)');
      }
    }
  }

  /// Extract thumbnail from video using media_kit
  Future<String?> _extractThumbnail(String videoPath, String outputPath) async {
    Player? player;
    // Keep a strong reference so the underlying video output stays alive while
    // taking a screenshot on Windows.
    // ignore: unused_local_variable
    VideoController? controller;
    
    try {
      // Ensure MediaKit is initialized before creating a Player.
      try {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.mediaKitEnsure START');
        }
        await _ensureMediaKitInitialized();
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.mediaKitEnsure DONE');
        }
      } catch (e, st) {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.mediaKitEnsure FAILED: $e');
        }
        debugPrint('VideoThumbnailService: MediaKit.ensureInitialized failed: $e');
        debugPrintStack(stackTrace: st);
        return null;
      }

      final normalizedSource = normalizeMediaSource(videoPath);
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnailService.source normalized=${_short(normalizedSource)}');
      }

      // Create a player for extraction
      player = Player(
        configuration: const PlayerConfiguration(
          // Disable audio for thumbnail extraction
          pitch: false,
          protocolWhitelist: ['file', 'http', 'https'],
        ),
      );
      
      controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          // Hardware texture output can remain 0x0 offscreen, making screenshot
          // return null on Windows.
          enableHardwareAcceleration: false,
        ),
      );
      
      // Open the video
      try {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.open START');
        }
        await player.open(Media(normalizedSource), play: true);
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.open DONE');
        }
      } catch (e, st) {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.open FAILED: $e');
        }
        debugPrint('VideoThumbnailService: open failed src=$normalizedSource err=$e');
        debugPrintStack(stackTrace: st);
        return null;
      }
      
      // Wait for video to be ready (duration available)
      await _waitForDuration(player, timeout: const Duration(seconds: 5));
      
      final duration = player.state.duration;
      if (duration == Duration.zero) {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.duration ZERO (giving up)');
        }
        return null;
      }

      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnailService.duration ms=${duration.inMilliseconds}');
      }
      
      // Seek to 10% of the video or 1 second, whichever is smaller
      final seekPosition = Duration(
        milliseconds: (duration.inMilliseconds * 0.1).round().clamp(0, 1000),
      );
      await player.seek(seekPosition);
      
      // Wait a bit for the frame to render
      await Future.delayed(const Duration(milliseconds: 500));

      // Some sources report duration but still don't yield a decoded frame.
      await _waitForVideoDimensions(player, timeout: const Duration(seconds: 2));
      
      // Take screenshot
      final screenshot = await player.screenshot();
      
      if (screenshot == null) {
        if (PerfLogger.enabled) {
          PerfLogger.log('VideoThumbnailService.screenshot NULL');
        }
        return null;
      }

      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnailService.screenshot bytes=${screenshot.length}');
      }
      
      // Save the screenshot
      final file = File(outputPath);
      await file.writeAsBytes(screenshot);
      
      return outputPath;
      
    } catch (e) {
      debugPrint('VideoThumbnailService: Error extracting thumbnail: $e');
      return null;
    } finally {
      // Clean up
      await player?.dispose();
    }
  }

  /// Wait for duration to be available
  Future<void> _waitForDuration(Player player, {required Duration timeout}) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Listen for duration
    final subscription = player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Also check current state
    if (player.state.duration > Duration.zero) {
      completer.complete();
    }
    
    await completer.future;
    timeoutTimer.cancel();
    await subscription.cancel();
  }

  Future<void> _waitForVideoDimensions(Player player, {required Duration timeout}) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    int? lastWidth;
    int? lastHeight;

    final widthSub = player.stream.width.listen((w) {
      lastWidth = w;
      if ((w ?? 0) > 0 && (lastHeight ?? 0) > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });
    final heightSub = player.stream.height.listen((h) {
      lastHeight = h;
      if ((lastWidth ?? 0) > 0 && (h ?? 0) > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;
    timeoutTimer.cancel();
    await widthSub.cancel();
    await heightSub.cancel();

    if (PerfLogger.enabled) {
      PerfLogger.log('VideoThumbnailService.dimensions w=${lastWidth ?? 0} h=${lastHeight ?? 0}');
    }
  }

  String _short(String s, {int max = 120}) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// Generate a unique cache key for a video path
  String _getCacheKey(String videoPath) {
    // Avoid synchronous filesystem calls here; this function may run on the UI
    // isolate from many widgets.
    return videoPath.hashCode.toRadixString(36);
  }

  /// Clear all cached thumbnails
  Future<void> clearCache() async {
    await init();
    _thumbnailCache.clear();
    
    final dir = Directory(_cacheDir!);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }
  }

  /// Get size of thumbnail cache
  Future<int> getCacheSize() async {
    await init();
    int size = 0;
    
    final dir = Directory(_cacheDir!);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    }
    
    return size;
  }
  
  /// Check cache size and clear old files if limit exceeded
  Future<void> _checkAndEnforceCacheLimit() async {
    try {
      final currentSize = await getCacheSize();
      final maxSizeBytes = _maxCacheSizeMb * 1024 * 1024;
      
      if (currentSize > maxSizeBytes) {
        await _clearOldestFiles(currentSize - maxSizeBytes);
      }
    } catch (e) {
      debugPrint('VideoThumbnailService: Error enforcing cache limit: $e');
    }
  }
  
  /// Clear oldest files to free up specified bytes
  Future<void> _clearOldestFiles(int bytesToFree) async {
    await init();
    
    final dir = Directory(_cacheDir!);
    if (!await dir.exists()) return;
    
    // Get all files with their modification times
    final files = <MapEntry<File, DateTime>>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          files.add(MapEntry(entity, stat.accessed));
        } catch (_) {
          // Skip files we can't stat
        }
      }
    }
    
    // Sort by access time (oldest first)
    files.sort((a, b) => a.value.compareTo(b.value));
    
    // Delete oldest files until we've freed enough space
    int freedBytes = 0;
    for (final entry in files) {
      if (freedBytes >= bytesToFree) break;
      
      try {
        final fileSize = await entry.key.length();
        await entry.key.delete();
        freedBytes += fileSize;
        
        // Also remove from memory cache
        final fileName = path.basenameWithoutExtension(entry.key.path);
        _thumbnailCache.remove(fileName);
      } catch (e) {
        debugPrint('VideoThumbnailService: Error deleting cache file: $e');
      }
    }
  }
  
  /// Get number of cached thumbnails
  Future<int> getCacheCount() async {
    await init();
    int count = 0;
    
    final dir = Directory(_cacheDir!);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) count++;
      }
    }
    
    return count;
  }
}

/// Global instance for convenience
final videoThumbnailService = VideoThumbnailService();
