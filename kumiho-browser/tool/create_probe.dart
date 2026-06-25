// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// End-to-end smoke test for the Kumiho CREATE / edit chain against a
// self-hosted Kumiho server (Community Edition) on plaintext loopback gRPC.
//
// Exercises every mutating call the asset-browser's new features rely on:
// create project/space/item/revision/artifact, set the default artifact,
// update metadata, create a dependency edge, and create a bundle with a
// member. It works inside an isolated "ce-probe-<timestamp>" project and
// force-deletes that project at the end, so it leaves the server clean.
//
// Usage:
//   dart run tool/create_probe.dart [host] [port]
//   dart run tool/create_probe.dart            # defaults to 127.0.0.1 9190

import 'dart:io';

import 'package:kumiho/kumiho.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 9190;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final projName = 'ce-probe-$stamp';

  // CE is BYO-storage: an artifact stores only a `location` string, never
  // bytes. Create real local files so the locations resolve even if the
  // server ever validates them.
  final tmp = await Directory.systemTemp.createTemp('ce_probe_');
  final md = File('${tmp.path}/notes.md')
    ..writeAsStringSync('# CE probe\n\nMarkdown artifact body.\n');
  final png = File('${tmp.path}/thumbnail.png')
    ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final client = KumihoClient(host: host, port: port, secure: false, token: '');
  var failures = 0;
  // deleteProject resolves a project by its UUID projectId, NOT its name.
  String? projectId;
  void step(String label, Object? value) => stdout.writeln('  OK   $label -> $value');

  try {
    stdout.writeln('CE create-chain probe @ $host:$port   project=$projName\n');

    await client.createProject(projName, description: 'CE probe');
    step('createProject', projName);
    final project = await client.project(projName);
    projectId = project.projectId;

    final space = await project.createSpace('assets');
    step('createSpace', space.kref);

    final item = await space.createItem('hero', 'model');
    step('createItem', item.kref.uri);

    final rev = await item.createRevision(metadata: {'stage': 'draft'});
    step('createRevision', 'r=${rev.number} published=${rev.published} ${rev.kref.uri}');

    final thumb = await rev.createArtifact('thumbnail', png.path,
        metadata: {'contentType': 'image/png'});
    step('createArtifact(thumbnail)', thumb.name);

    final notes = await rev.createArtifact('notes.md', md.path,
        metadata: {'contentType': 'text/markdown'});
    step('createArtifact(notes.md)', notes.name);

    await rev.setDefaultArtifact('thumbnail');
    step('setDefaultArtifact', 'thumbnail');

    final updated =
        await client.updateRevisionMetadata(rev.kref.uri, {'stage': 'review', 'owner': 'probe'});
    step('updateRevisionMetadata', updated.metadata);

    final artifacts = await rev.getArtifacts();
    step('getArtifacts', artifacts.map((a) => a.name).toList());

    // Dependency edge: a second item/revision that `hero` depends on.
    final dep = await space.createItem('rig', 'model');
    final depRev = await dep.createRevision();
    await rev.createEdge(depRev, EdgeType.dependsOn);
    step('createEdge(DEPENDS_ON)', '${rev.kref.uri}  ->  ${depRev.kref.uri}');

    final edges = await client.getEdges(rev.kref.uri);
    step('getEdges', '${edges.edges.length} edge(s)');

    // Bundle aggregating the hero item.
    final bundle = await project.createBundle('release-pack');
    step('createBundle', bundle.name);
    await bundle.addMember(item.kref);
    step('bundle.addMember', item.kref.uri);
    // NOTE: bundle.getMembers() is broken in the SDK (reads a non-existent
    // `memberKrefs` getter on GetBundleMembersResponse); skip it here.

    stdout.writeln('\nALL STEPS PASSED');
  } catch (e, st) {
    failures++;
    stderr.writeln('  FAIL -> $e');
    stderr.writeln(st);
  } finally {
    // Cleanup: force-delete the isolated probe project (cascades to contents).
    // deleteProject resolves by projectId (UUID), not name.
    try {
      if (projectId != null) {
        await client.deleteProject(projectId, force: true);
        stdout.writeln('cleanup: deleted project $projName');
      }
    } catch (e) {
      stderr.writeln('cleanup FAILED (delete "$projName" manually) -> $e');
    }
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
    await client.shutdownAsync();
  }
  exitCode = failures == 0 ? 0 : 1;
}
