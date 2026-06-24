// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// Deletes any leftover "ce-probe-*" test projects from a self-hosted Kumiho
// server (Community Edition). Also reports whether deleteProject resolves a
// project by `name` or by `projectId`.
//
// Usage: dart run tool/cleanup_probe.dart [host] [port]

import 'dart:io';

import 'package:kumiho/kumiho.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 9190;

  final client = KumihoClient(host: host, port: port, secure: false, token: '');
  try {
    final projects = await client.projects();
    final stray = projects.where((p) => p.name.startsWith('ce-probe-')).toList();
    stdout.writeln('Found ${stray.length} ce-probe project(s)');
    for (final p in stray) {
      stdout.writeln('- name=${p.name} projectId=${p.projectId} deprecated=${p.deprecated}');
      try {
        await client.deleteProject(p.projectId, force: true);
        stdout.writeln('  deleted via projectId');
      } catch (e1) {
        try {
          await client.deleteProject(p.name, force: true);
          stdout.writeln('  deleted via name');
        } catch (e2) {
          stderr.writeln('  FAILED byId=$e1  byName=$e2');
        }
      }
    }
    final after = await client.projects();
    final remaining = after.where((p) => p.name.startsWith('ce-probe-')).length;
    stdout.writeln('Remaining ce-probe projects: $remaining');
  } finally {
    await client.shutdownAsync();
  }
}
