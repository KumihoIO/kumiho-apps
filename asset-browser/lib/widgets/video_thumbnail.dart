// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/video_thumbnail_service.dart';
import '../theme/kumiho_theme.dart';

import '../core/perf/perf_logger.dart';

/// Widget that displays a video thumbnail, extracting it if necessary
class VideoThumbnail extends StatefulWidget {
  final String videoPath;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const VideoThumbnail({
    super.key,
    required this.videoPath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  // Startup bisection toggles.
  static const bool _disableVideoThumbnails =
      String.fromEnvironment('DISABLE_VIDEO_THUMBNAILS', defaultValue: '0') == '1';
  // If unset, default to a conservative Windows-only delay. This prevents
  // early MediaKit/FFmpeg initialization paths from blocking the UI isolate.
  static final int _startupDeferMs = _computeStartupDeferMs();

  static int _computeStartupDeferMs() {
    // Use -1 as a sentinel so we can distinguish "not provided".
    const envValue = int.fromEnvironment('STARTUP_DEFER_VIDEO_THUMBNAILS_MS', defaultValue: -1);
    if (envValue >= 0) return envValue;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      // Short delay to avoid extract storms immediately at first frame.
      return 2000;
    }

    return 0;
  }

  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _loadThumbnail();
    }
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (_disableVideoThumbnails) {
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnail: DISABLED (skip extract)');
      }
      if (mounted) {
        setState(() {
          _thumbnailPath = null;
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    // Optional startup deferral so we can confirm whether video thumbnail
    // extraction (and media_kit initialization) is the source of the stall.
    if (_startupDeferMs > 0) {
      final sinceStart = PerfLogger.sinceStartMs();
      if (sinceStart < _startupDeferMs) {
        final remaining = (_startupDeferMs - sinceStart).clamp(0, _startupDeferMs);
        if (PerfLogger.enabled) {
          PerfLogger.log(
            'VideoThumbnail: deferring extract remaining=${remaining}ms (sinceStart=${sinceStart}ms target=${_startupDeferMs}ms)',
          );
        }
        _deferTimer?.cancel();
        _deferTimer = Timer(Duration(milliseconds: remaining), () {
          if (mounted) {
            _loadThumbnail();
          }
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnail: extract START');
      }
      final path = await videoThumbnailService.getThumbnail(widget.videoPath);
      if (mounted) {
        setState(() {
          _thumbnailPath = path;
          _isLoading = false;
          _hasError = path == null;
        });
      }
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnail: extract DONE ok=${path != null}');
      }
    } catch (e) {
      if (PerfLogger.enabled) {
        PerfLogger.log('VideoThumbnail: extract FAILED $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ?? _buildDefaultPlaceholder();
    }

    if (_hasError || _thumbnailPath == null) {
      return widget.errorWidget ?? _buildDefaultError();
    }

    return Image.file(
      File(_thumbnailPath!),
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => widget.errorWidget ?? _buildDefaultError(),
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KumihoTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultError() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: Icon(
          Icons.videocam,
          color: KumihoTheme.textMuted,
          size: 32,
        ),
      ),
    );
  }
}
