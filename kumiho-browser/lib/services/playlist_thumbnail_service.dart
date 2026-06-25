import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/perf/perf_logger.dart';

/// Generates small, square thumbnails off the UI isolate on Windows.
///
/// Why: decoding many large thumbnails on Windows can hard-stall the UI thread.
/// This service decodes+resizes in a worker isolate, then returns small JPEG
/// bytes that are cheap to display.
class PlaylistThumbnailService {
  PlaylistThumbnailService._();
  static final PlaylistThumbnailService instance = PlaylistThumbnailService._();

  static const bool _enabled =
      String.fromEnvironment('WINDOWS_BG_PLAYLIST_THUMBNAILS', defaultValue: '1') == '1';

  // Memory cache: key -> bytes.
  final LinkedHashMap<String, Uint8List> _memCache = LinkedHashMap();
  static const int _maxMemEntries = 256;

  // Deduplicate in-flight requests.
  final Map<String, Future<Uint8List?>> _pending = {};

  // Worker isolate.
  Isolate? _worker;
  SendPort? _workerSendPort;
  Future<void>? _workerInit;

  // Cache directory.
  Directory? _cacheDir;
  Future<void>? _cacheInit;

  Future<void> _ensureCacheDir() {
    if (_cacheInit != null) return _cacheInit!;
    final completer = Completer<void>();
    _cacheInit = completer.future;
    () async {
      final root = await getApplicationSupportDirectory();
      final dir = Directory(path.join(root.path, 'playlist_thumbnails'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      completer.complete();
    }().catchError((e, st) {
      completer.completeError(e, st);
    });
    return _cacheInit!;
  }

  Future<void> _ensureWorker() {
    if (_workerInit != null) return _workerInit!;
    final completer = Completer<void>();
    _workerInit = completer.future;

    () async {
      final ready = ReceivePort();
      _worker = await Isolate.spawn(_thumbnailWorkerMain, ready.sendPort);
      final sendPort = await ready.first as SendPort;
      _workerSendPort = sendPort;
      completer.complete();
    }().catchError((e, st) {
      completer.completeError(e, st);
    });

    return _workerInit!;
  }

  void _remember(String key, Uint8List bytes) {
    _memCache.remove(key);
    _memCache[key] = bytes;
    while (_memCache.length > _maxMemEntries) {
      _memCache.remove(_memCache.keys.first);
    }
  }

  /// Returns small JPEG bytes for [uri], resized to a square of [targetPx].
  ///
  /// - `uri` can be a local file path or an http(s) URL.
  /// - On non-Windows platforms, or when disabled, returns null so callers can
  ///   fall back to `Image.file`/`Image.network`.
  Future<Uint8List?> getThumbnailBytes({
    required String uri,
    required int targetPx,
  }) async {
    if (!_enabled) return null;
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.windows) return null;

    final px = targetPx.clamp(64, 512);

    await _ensureCacheDir();
    await _ensureWorker();

    final key = await _computeKey(uri: uri, targetPx: px);

    final cached = _memCache[key];
    if (cached != null) return cached;

    return _pending.putIfAbsent(key, () async {
      // Disk cache.
      final diskPath = path.join(_cacheDir!.path, '$key.jpg');
      final diskFile = File(diskPath);
      try {
        if (await diskFile.exists()) {
          final bytes = await diskFile.readAsBytes();
          _remember(key, bytes);
          return bytes;
        }
      } catch (_) {
        // Ignore disk cache failures.
      }

      // Worker decode.
      final reply = ReceivePort();
      _workerSendPort!.send(<Object?>[uri, px, reply.sendPort]);

      final result = await reply.first;
      reply.close();

      if (result is TransferableTypedData) {
        final bytes = result.materialize().asUint8List();
        _remember(key, bytes);
        // Best-effort write to disk (don’t block the UI for flush).
        unawaited(diskFile.writeAsBytes(bytes, flush: false));
        return bytes;
      }

      return null;
    }).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<String> _computeKey({
    required String uri,
    required int targetPx,
  }) async {
    // Prefer a stable key that changes when the source file changes.
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return '${uri.hashCode}_$targetPx';
    }

    try {
      final stat = await File(uri).stat();
      return '${uri.hashCode}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_$targetPx';
    } catch (_) {
      return '${uri.hashCode}_$targetPx';
    }
  }
}

// ==================== Worker Isolate ====================

void _thumbnailWorkerMain(SendPort readyPort) {
  final receive = ReceivePort();
  readyPort.send(receive.sendPort);

  receive.listen((message) async {
    // message: [uri, targetPx, replyPort]
    if (message is! List || message.length != 3) return;

    final uri = message[0] as String?;
    final targetPx = message[1] as int?;
    final reply = message[2] as SendPort?;
    if (uri == null || targetPx == null || reply == null) return;

    try {
      final bytes = await _decodeResizeSquareJpeg(uri: uri, targetPx: targetPx);
      if (bytes == null) {
        reply.send(null);
        return;
      }
      reply.send(TransferableTypedData.fromList(<Uint8List>[bytes]));
    } catch (e) {
      // Avoid crashing the worker isolate.
      if (PerfLogger.enabled) {
        PerfLogger.log('PlaylistThumbnailService.worker FAILED: $e');
      }
      reply.send(null);
    }
  });
}

Future<Uint8List?> _decodeResizeSquareJpeg({
  required String uri,
  required int targetPx,
}) async {
  final sourceBytes = await _readSourceBytes(uri);
  if (sourceBytes == null || sourceBytes.isEmpty) return null;

  final decoded = im.decodeImage(sourceBytes);
  if (decoded == null) return null;

  final square = _resizeCoverAndCrop(decoded, targetPx);
  final jpg = im.encodeJpg(square, quality: 82);
  return Uint8List.fromList(jpg);
}

Future<Uint8List?> _readSourceBytes(String uri) async {
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(uri));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
        // Guardrail: don't accidentally try to thumbnail huge remote files.
        if (chunks.length > 25 * 1024 * 1024) {
          return null;
        }
      }
      return Uint8List.fromList(chunks);
    } finally {
      client.close(force: true);
    }
  }

  try {
    final file = File(uri);
    if (!await file.exists()) return null;
    final len = await file.length();
    if (len <= 0 || len > 250 * 1024 * 1024) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

im.Image _resizeCoverAndCrop(im.Image src, int target) {
  final w = src.width;
  final h = src.height;
  if (w <= 0 || h <= 0) {
    return im.Image(width: target, height: target);
  }

  final scale = math.max(target / w, target / h);
  var newW = (w * scale).round();
  var newH = (h * scale).round();
  if (newW < target) newW = target;
  if (newH < target) newH = target;

  final resized = im.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: im.Interpolation.average,
  );

  final x = ((resized.width - target) / 2).round().clamp(0, resized.width - 1) as int;
  final y = ((resized.height - target) / 2).round().clamp(0, resized.height - 1) as int;
  final cropW = target.clamp(1, resized.width - x) as int;
  final cropH = target.clamp(1, resized.height - y) as int;

  final cropped = im.copyCrop(resized, x: x, y: y, width: cropW, height: cropH);
  if (cropped.width == target && cropped.height == target) return cropped;
  return im.copyResize(cropped, width: target, height: target, interpolation: im.Interpolation.average);
}
