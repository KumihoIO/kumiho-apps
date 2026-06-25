// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// Smoke test for a self-hosted Kumiho server (Community Edition).
//
// CE serves plaintext gRPC on loopback (default 127.0.0.1:9190) and does not
// require authentication, so no token or TLS is used.
//
// Usage:
//   dart run tool/ce_probe.dart [host] [port]
//   dart run tool/ce_probe.dart            # defaults to 127.0.0.1 9190

import 'dart:io';

import 'package:kumiho/kumiho.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 9190;

  stdout.writeln('Connecting to CE at $host:$port (plaintext, no auth)');
  final client = KumihoClient(host: host, port: port, secure: false, token: '');

  final sw = Stopwatch()..start();
  try {
    final projects = await client.projects();
    sw.stop();
    stdout.writeln('projects() ok in ${sw.elapsedMilliseconds}ms: count=${projects.length}');
    for (final p in projects.take(20)) {
      stdout.writeln('- ${p.name}');
    }
  } catch (e, st) {
    sw.stop();
    stderr.writeln('projects() failed in ${sw.elapsedMilliseconds}ms: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    await client.shutdownAsync();
  }
}
