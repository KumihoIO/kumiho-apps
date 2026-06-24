// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../providers/kumiho_provider.dart';

/// Shared mutating actions against the Kumiho server.
///
/// All methods are intended to be called from UI event handlers (button taps,
/// menu selections) — never during a widget/provider build, which would trip
/// Riverpod's build-phase assertions. Each obtains the client lazily from
/// [kumihoClientProvider] and refreshes the affected providers on success.
class AssetActions {
  AssetActions._();

  /// Picks a local image file and attaches it to [revisionKref] as an artifact
  /// named 'thumbnail' (the app's thumbnail convention), then makes it the
  /// revision's default artifact so it renders as the preview.
  ///
  /// Returns the chosen file path, or null if the user cancelled the picker.
  /// Throws if the client is unavailable or the server rejects the call.
  static Future<String?> addThumbnail(WidgetRef ref, String revisionKref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose a thumbnail image',
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return null;

    final client = await ref.read(kumihoClientProvider.future);
    if (client == null) {
      throw Exception('Kumiho client unavailable');
    }

    await client.createArtifact(
      revisionKref,
      'thumbnail',
      path,
      metadata: {'contentType': _imageMimeForPath(path)},
    );
    await client.setDefaultArtifact(revisionKref, 'thumbnail');

    // Refresh the revision's artifact list and the grid/list views.
    ref.invalidate(revisionArtifactsProvider(revisionKref));
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
    return path;
  }

  static String _imageMimeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.svg':
        return 'image/svg+xml';
      default:
        return 'application/octet-stream';
    }
  }
}
