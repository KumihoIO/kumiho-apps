import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/playlist_thumbnail_service.dart';

class WindowsPlaylistThumbnail extends StatefulWidget {
  final String uri;
  final int targetPx;
  final Widget placeholder;
  final Widget loading;

  const WindowsPlaylistThumbnail({
    super.key,
    required this.uri,
    required this.targetPx,
    required this.placeholder,
    required this.loading,
  });

  @override
  State<WindowsPlaylistThumbnail> createState() => _WindowsPlaylistThumbnailState();
}

class _WindowsPlaylistThumbnailState extends State<WindowsPlaylistThumbnail> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = PlaylistThumbnailService.instance.getThumbnailBytes(
      uri: widget.uri,
      targetPx: widget.targetPx,
    );
  }

  @override
  void didUpdateWidget(covariant WindowsPlaylistThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.targetPx != widget.targetPx) {
      _future = PlaylistThumbnailService.instance.getThumbnailBytes(
        uri: widget.uri,
        targetPx: widget.targetPx,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return widget.loading;
        }
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return widget.placeholder;
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}
