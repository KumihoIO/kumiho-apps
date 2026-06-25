// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io';

import 'package:flutter/material.dart';

/// Loads a network image only after a lightweight availability check.
///
/// This avoids noisy `NetworkImageLoadException` logs for known-bad URLs
/// (e.g. 404 profile images) by never attempting to decode them.
class SafeNetworkImage extends StatefulWidget {
  final String? url;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Widget fallback;
  final Duration timeout;

  const SafeNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.timeout = const Duration(seconds: 3),
  });

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  Future<bool>? _isAvailableFuture;

  @override
  void initState() {
    super.initState();
    _isAvailableFuture = _checkAvailable(widget.url);
  }

  @override
  void didUpdateWidget(covariant SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _isAvailableFuture = _checkAvailable(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<bool>(
          future: _isAvailableFuture,
          builder: (context, snapshot) {
            final ok = snapshot.data == true;
            if (!ok) return widget.fallback;

            // Even after a successful probe, the image load could fail transiently.
            // Keep an errorBuilder to fall back silently.
            return Image.network(
              widget.url!,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => widget.fallback,
            );
          },
        ),
      ),
    );
  }

  bool _isValidUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  Future<bool> _checkAvailable(String? url) async {
    if (!_isValidUrl(url)) return false;

    final uri = Uri.parse(url!.trim());

    // Prefer HEAD to avoid downloading the full image.
    // Fall back to GET if the server rejects HEAD.
    Future<HttpClientResponse> open(String method) async {
      final client = HttpClient();
      client.connectionTimeout = widget.timeout;

      final request = await client.openUrl(method, uri).timeout(widget.timeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(widget.timeout);
      // Drain and close to avoid keeping the connection around.
      // ignore: unawaited_futures
      response.drain();
      client.close(force: true);
      return response;
    }

    try {
      final head = await open('HEAD');
      final code = head.statusCode;
      if (code >= 200 && code < 400) return true;
      if (code == 404) return false;
      // Many avatar/image CDNs reject HEAD (405) or require GET for auth/routing
      // and may return 401/403 to HEAD even though GET works.
      final get = await open('GET');
      final getCode = get.statusCode;
      return getCode >= 200 && getCode < 400;
    } catch (_) {
      return false;
    }
  }
}
