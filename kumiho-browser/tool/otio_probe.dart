// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// Validates OTIO generation + that the .otio file can be attached to a Kumiho
// revision as an artifact. Builds a tiny timeline, writes it to a temp file,
// re-parses it to confirm it is valid JSON in the OTIO schema, creates a
// project/item/revision, attaches the .otio as an artifact, reads it back, then
// force-deletes the probe project.
//
// Usage: dart run tool/otio_probe.dart [host] [port]

import 'dart:convert';
import 'dart:io';

import 'package:kumiho/kumiho.dart';

import '../lib/services/otio_export.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 9190;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final projName = 'otio-probe-$stamp';

  // 1) Build + validate the OTIO document.
  final timeline = OtioExport.buildTimeline(name: 'My Playlist', clips: const [
    OtioClipInput(name: 'shotA', targetUrl: 'file:///media/shotA.mp4'),
    OtioClipInput(
        name: 'shotB',
        targetUrl: 'https://cdn.example.com/shotB.mp4',
        durationSeconds: 3),
  ]);
  final text = OtioExport.encode(timeline);
  final parsed = jsonDecode(text) as Map<String, dynamic>;
  final track = (((parsed['tracks'] as Map)['children'] as List).first) as Map;
  final clipCount = (track['children'] as List).length;
  stdout.writeln('OTIO doc: schema=${parsed['OTIO_SCHEMA']} track=${track['kind']} clips=$clipCount');
  if (parsed['OTIO_SCHEMA'] != 'Timeline.1' || clipCount != 2) {
    stderr.writeln('FAIL: unexpected OTIO structure');
    exitCode = 1;
    return;
  }

  final tmp = await Directory.systemTemp.createTemp('otio_probe_');
  final otioFile = File('${tmp.path}/timeline.otio')..writeAsStringSync(text);

  // 2) Attach to a Kumiho revision.
  final client = KumihoClient(host: host, port: port, secure: false, token: '');
  String? projectId;
  try {
    await client.createProject(projName);
    final project = await client.project(projName);
    projectId = project.projectId;
    final space = await project.createSpace('playlists');
    final item = await space.createItem('my-playlist', 'playlist');
    final rev = await item.createRevision();
    await client.createArtifact(rev.kref.uri, 'timeline.otio', otioFile.path,
        metadata: {'contentType': 'application/otio+json'});
    final artifacts = await rev.getArtifacts();
    stdout.writeln('attached artifacts: ${artifacts.map((a) => a.name).toList()}');
    stdout.writeln(artifacts.any((a) => a.name == 'timeline.otio')
        ? '\nALL OK'
        : '\nFAIL: timeline.otio not attached');
  } catch (e, st) {
    stderr.writeln('FAIL -> $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    if (projectId != null) {
      try {
        await client.deleteProject(projectId, force: true);
        stdout.writeln('cleanup: deleted $projName');
      } catch (_) {}
    }
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
    await client.shutdownAsync();
  }
}
