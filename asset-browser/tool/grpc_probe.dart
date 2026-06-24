import 'dart:convert';
import 'dart:io';

import 'package:kumiho/kumiho.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'us-central1.kumiho.cloud';
  final port = args.length > 1 ? int.parse(args[1]) : 443;

  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('Missing USERPROFILE/HOME');
    exit(2);
  }

  final authFile = File('$home/.kumiho/kumiho_authentication.json');
  if (!authFile.existsSync()) {
    stderr.writeln('Missing auth file: ${authFile.path}');
    exit(2);
  }

  final authJson = jsonDecode(authFile.readAsStringSync()) as Map<String, dynamic>;
  final token = (authJson['id_token'] as String?) ?? '';
  if (token.isEmpty) {
    stderr.writeln('Missing id_token in auth file');
    exit(2);
  }

  stdout.writeln('Connecting to $host:$port secure=true');
  final client = KumihoClient(host: host, port: port, secure: true, token: token);

  final sw = Stopwatch()..start();
  try {
    final projects = await client.projects();
    sw.stop();
    stdout.writeln('projects() ok in ${sw.elapsedMilliseconds}ms: count=${projects.length}');
    for (final p in projects.take(10)) {
      stdout.writeln('- ${p.name}');
    }
  } catch (e, st) {
    sw.stop();
    stderr.writeln('projects() failed in ${sw.elapsedMilliseconds}ms: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
