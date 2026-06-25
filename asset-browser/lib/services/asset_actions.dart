// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kumiho/kumiho.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
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

  /// Creates a project. Refreshes the project/grid views on success.
  static Future<void> createProject(WidgetRef ref, String name,
      {String? description}) async {
    final client = await _client(ref);
    await client.createProject(
      name,
      description: (description != null && description.isNotEmpty) ? description : null,
    );
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  /// Creates a space under [parentPath] (e.g. '/project' or '/project/space').
  static Future<void> createSpace(
      WidgetRef ref, String parentPath, String name) async {
    final client = await _client(ref);
    await client.createSpace(parentPath, name);
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  /// Creates an item of [kind] under the space at [parentPath].
  static Future<void> createItem(
      WidgetRef ref, String parentPath, String name, String kind) async {
    final client = await _client(ref);
    await client.createItem(parentPath, name, kind);
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  /// Creates a new (auto-numbered) revision of [itemKref].
  static Future<void> createRevision(WidgetRef ref, String itemKref,
      {Map<String, String>? metadata}) async {
    final client = await _client(ref);
    await client.createRevision(itemKref, metadata: metadata);
    ref.invalidate(itemRevisionsProvider(itemKref));
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  /// Creates an artifact named [name] pointing at [location] on [revisionKref].
  static Future<void> createArtifact(
      WidgetRef ref, String revisionKref, String name, String location,
      {Map<String, String>? metadata}) async {
    final client = await _client(ref);
    await client.createArtifact(revisionKref, name, location, metadata: metadata);
    ref.invalidate(revisionArtifactsProvider(revisionKref));
    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
  }

  /// Edge type linking a playlist revision to each of its member revisions.
  static const String playlistMemberEdge = 'PLAYLIST_MEMBER';

  /// Records [playlist] into Kumiho under [projectName]'s `playlists` space as
  /// an item(kind='playlist') plus a NEW revision (each save is a version), and
  /// links that revision to every member revision with a [playlistMemberEdge]
  /// edge carrying the member's order, name, location and artifact kref.
  ///
  /// Bundles can't be used (bundle members are item krefs, not revision krefs),
  /// so the playlist's exact revisions are pinned via edges instead.
  ///
  /// Returns the new playlist revision kref.
  static Future<String> savePlaylistToKumiho(
      WidgetRef ref, Playlist playlist, String projectName) async {
    final client = await _client(ref);

    // Ensure the playlists space + the playlist item exist (idempotent).
    await client.createSpace('/$projectName', 'playlists', existsError: false);
    final itemName = krefSafeName(playlist.name);
    final itemResp = await client.createItem(
        '/$projectName/playlists', itemName, 'playlist', existsError: false);
    final itemKref = itemResp.kref.uri;

    // A new revision snapshots the current playlist contents.
    final rev = await client.createRevision(itemKref, metadata: {
      'name': playlist.name,
      'item_count': '${playlist.items.length}',
      if (playlist.description != null && playlist.description!.isNotEmpty)
        'description': playlist.description!,
    });
    final revKref = rev.kref.uri;

    // Pin each member revision in order.
    var order = 0;
    for (final item in playlist.items) {
      final memberRev = item.revisionKref;
      if (memberRev != null && memberRev.isNotEmpty) {
        await client.createEdge(revKref, memberRev, playlistMemberEdge, metadata: {
          'order': '$order',
          'name': item.name,
          'type': item.type,
          if (item.location != null && item.location!.isNotEmpty)
            'location': item.location!,
          if (item.kref != null && item.kref!.isNotEmpty) 'artifact': item.kref!,
        });
      }
      order++;
    }

    ref.read(kumihoRefreshTriggerProvider.notifier).state++;
    return revKref;
  }

  /// Sanitizes [name] into a kref-safe item name (lowercase, alphanumerics and
  /// `-`/`_` only).
  static String krefSafeName(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'playlist' : cleaned;
  }

  /// Parses a metadata blob: a JSON object, or `key: value` / `key=value`
  /// lines (blank lines and #comments skipped). Returns null if empty.
  static Map<String, String>? parseMetadata(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), '$v'));
      }
    } catch (_) {
      // Not JSON — fall through to line parsing.
    }
    final result = <String, String>{};
    for (final raw in const LineSplitter().convert(trimmed)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final colon = line.indexOf(':');
      final equals = line.indexOf('=');
      int sep;
      if (colon == -1) {
        sep = equals;
      } else if (equals == -1) {
        sep = colon;
      } else {
        sep = colon < equals ? colon : equals;
      }
      if (sep <= 0) continue;
      final key = line.substring(0, sep).trim();
      final value = line.substring(sep + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result.isEmpty ? null : result;
  }

  static Future<KumihoClient> _client(WidgetRef ref) async {
    final client = await ref.read(kumihoClientProvider.future);
    if (client == null) {
      throw Exception('Kumiho client unavailable');
    }
    return client;
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
