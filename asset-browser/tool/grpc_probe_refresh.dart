import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kumiho/kumiho.dart';

Future<String> refreshIdToken({
  required String apiKey,
  required String refreshToken,
}) async {
  final url = Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey');
  final res = await http.post(
    url,
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    },
  ).timeout(const Duration(seconds: 15));

  if (res.statusCode != 200) {
    throw 'refresh failed: HTTP ${res.statusCode}: ${res.body}';
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final idToken = (json['id_token'] as String?) ?? '';
  if (idToken.isEmpty) throw 'refresh failed: missing id_token';
  return idToken;
}

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
  final apiKey = (authJson['api_key'] as String?) ?? '';
  final refreshToken = (authJson['refresh_token'] as String?) ?? '';
  if (apiKey.isEmpty || refreshToken.isEmpty) {
    stderr.writeln('Missing api_key/refresh_token in auth file');
    exit(2);
  }

  stdout.writeln('Refreshing Firebase ID token...');
  final tokenSw = Stopwatch()..start();
  final token = await refreshIdToken(apiKey: apiKey, refreshToken: refreshToken);
  tokenSw.stop();
  stdout.writeln('Got fresh ID token in ${tokenSw.elapsedMilliseconds}ms');

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
