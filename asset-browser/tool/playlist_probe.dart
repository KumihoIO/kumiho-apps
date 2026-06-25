// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// Validates the "playlist as a dummy item/revision + edges" model against a
// self-hosted Kumiho server (CE). Bundles can't be used because bundle members
// are item krefs, not revision krefs — a playlist must pin specific revisions.
//
// Creates two member items+revisions and a playlist item(kind='playlist')
// +revision, then links the playlist revision to each member revision with an
// edge (trying a custom 'PLAYLIST_MEMBER' type, falling back to REFERENCED),
// reads the edges back, and force-deletes the probe project.
//
// Usage: dart run tool/playlist_probe.dart [host] [port]

import 'dart:io';

import 'package:kumiho/kumiho.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 9190;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final projName = 'pl-probe-$stamp';

  final client = KumihoClient(host: host, port: port, secure: false, token: '');
  String? projectId;
  try {
    stdout.writeln('Playlist-model probe @ $host:$port  project=$projName\n');
    await client.createProject(projName);
    final project = await client.project(projName);
    projectId = project.projectId;

    final media = await project.createSpace('media');
    final shotA = await media.createItem('shotA', 'video');
    final shotARev = await shotA.createRevision();
    final shotB = await media.createItem('shotB', 'video');
    final shotBRev = await shotB.createRevision();
    stdout.writeln('  OK   member revisions: ${shotARev.kref.uri} , ${shotBRev.kref.uri}');

    final playlists = await project.createSpace('playlists');
    final pl = await playlists.createItem('my-playlist', 'playlist');
    final plRev = await pl.createRevision(metadata: {'name': 'My Playlist'});
    stdout.writeln('  OK   playlist revision: ${plRev.kref.uri}');

    // Try a custom edge type; fall back to a known one if the server rejects it.
    var edgeType = 'PLAYLIST_MEMBER';
    try {
      await client.createEdge(plRev.kref.uri, shotARev.kref.uri, edgeType,
          metadata: {'order': '0'});
      stdout.writeln('  OK   custom edge type "$edgeType" accepted');
    } catch (e) {
      stdout.writeln('  --   custom edge type rejected ($e)\n       falling back to REFERENCED');
      edgeType = EdgeType.referenced;
      await client.createEdge(plRev.kref.uri, shotARev.kref.uri, edgeType,
          metadata: {'order': '0', 'role': 'playlist_member'});
    }
    await client.createEdge(plRev.kref.uri, shotBRev.kref.uri, edgeType,
        metadata: {'order': '1', 'role': 'playlist_member'});

    final edges = await client.getEdges(plRev.kref.uri);
    stdout.writeln('  OK   getEdges(playlist) -> ${edges.edges.length} edge(s):');
    for (final e in edges.edges) {
      stdout.writeln('         ${e.edgeType}: ${e.sourceKref.uri} -> ${e.targetKref.uri}');
    }

    stdout.writeln('\nALL OK  (use edgeType="$edgeType")');
  } catch (e, st) {
    stderr.writeln('  FAIL -> $e');
    stderr.writeln(st);
  } finally {
    if (projectId != null) {
      try {
        await client.deleteProject(projectId, force: true);
        stdout.writeln('cleanup: deleted $projName');
      } catch (e) {
        stderr.writeln('cleanup FAILED ($projName) -> $e');
      }
    }
    await client.shutdownAsync();
  }
}
