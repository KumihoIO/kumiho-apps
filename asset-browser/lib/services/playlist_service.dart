// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/models.dart';

import '../core/perf/perf_logger.dart';

List<dynamic> _decodePlaylistsContent(String content) {
  final json = jsonDecode(content) as Map<String, dynamic>;
  final playlistsJson = json['playlists'] as List<dynamic>?;
  return playlistsJson ?? const <dynamic>[];
}

/// Service for persisting playlists to ~/.kumiho/ folder
class PlaylistService {
  static const String _playlistsFileName = 'playlists.json';
  static const String _kumihoFolder = '.kumiho';

  /// Get the kumiho config directory path
  static String get _kumihoDir {
    final home = Platform.environment['USERPROFILE'] ?? 
                 Platform.environment['HOME'] ?? 
                 '.';
    return path.join(home, _kumihoFolder);
  }

  /// Get the playlists file path
  static String get _playlistsPath => path.join(_kumihoDir, _playlistsFileName);

  /// Ensure the ~/.kumiho directory exists
  static Future<void> _ensureDirectoryExists() async {
    final dir = Directory(_kumihoDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Load all playlists from disk
  static Future<List<Playlist>> loadPlaylists() async {
    try {
      final file = File(_playlistsPath);
      if (!await file.exists()) {
        return [];
      }

      if (PerfLogger.enabled) {
        PerfLogger.mark('PlaylistService.loadPlaylists START');
      }

      final content = await file.readAsString();
      if (PerfLogger.enabled) {
        PerfLogger.log('PlaylistService.loadPlaylists: read ${content.length} chars');
      }

      // NOTE (Windows): Spawning the first background isolate via compute()
      // can block the main isolate for ~20-30s during early startup. Since
      // playlists.json is typically small, decode on the UI isolate to keep
      // startup responsive.
      await Future<void>.delayed(Duration.zero);

      if (PerfLogger.enabled) {
        PerfLogger.mark('PlaylistService.loadPlaylists: jsonDecode START');
      }
      final playlistsJson = _decodePlaylistsContent(content);

      if (PerfLogger.enabled) {
        PerfLogger.mark(
          'PlaylistService.loadPlaylists: jsonDecode DONE',
          fields: {'count': playlistsJson.length},
        );
      }

      if (PerfLogger.enabled) {
        PerfLogger.mark('PlaylistService.loadPlaylists: map START');
      }

      final playlists = playlistsJson
          .whereType<Map<String, dynamic>>()
          .map(Playlist.fromJson)
          .toList(growable: false);

      if (PerfLogger.enabled) {
        PerfLogger.mark(
          'PlaylistService.loadPlaylists: map DONE',
          fields: {'count': playlists.length},
        );
        PerfLogger.mark('PlaylistService.loadPlaylists DONE');
      }

      return playlists;
    } catch (e) {
      debugPrint('Error loading playlists: $e');
      return [];
    }
  }

  /// Save all playlists to disk
  static Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      await _ensureDirectoryExists();
      
      final json = {
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
      };

      final file = File(_playlistsPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  /// Save a single playlist (updates existing or adds new)
  static Future<void> savePlaylist(Playlist playlist) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlist.id);
    
    if (index >= 0) {
      playlists[index] = playlist;
    } else {
      playlists.add(playlist);
    }
    
    await savePlaylists(playlists);
  }

  /// Delete a playlist by ID
  static Future<void> deletePlaylist(String playlistId) async {
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == playlistId);
    await savePlaylists(playlists);
  }

  /// Create a new playlist with a unique ID
  static Playlist createNewPlaylist({
    required String name,
    Color? color,
    String? description,
  }) {
    final id = 'playlist_${DateTime.now().millisecondsSinceEpoch}';
    return Playlist(
      id: id,
      name: name,
      itemCount: 0,
      color: color ?? const Color(0xFF6B4EFF),
      description: description,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: [],
    );
  }
}
