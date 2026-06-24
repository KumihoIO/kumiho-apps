import 'dart:io';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'us-central1.kumiho.cloud';
  final port = args.length > 1 ? int.parse(args[1]) : 443;

  stdout.writeln('Probing TLS to $host:$port');

  // 1) Raw TLS connect with ALPN h2.
  try {
    final socket = await SecureSocket.connect(
      host,
      port,
      supportedProtocols: const ['h2', 'http/1.1'],
      timeout: const Duration(seconds: 10),
    );
    stdout.writeln('SecureSocket connected. selectedProtocol=${socket.selectedProtocol}');
    socket.destroy();
  } catch (e, st) {
    stdout.writeln('SecureSocket.connect failed: $e');
    stdout.writeln(st);
  }

  // 2) HTTPS GET using Dart HttpClient.
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final req = await client.getUrl(Uri.parse('https://$host/'));
    final res = await req.close();
    stdout.writeln('HttpClient GET status=${res.statusCode}');
    await res.drain();
    client.close(force: true);
  } catch (e, st) {
    stdout.writeln('HttpClient GET failed: $e');
    stdout.writeln(st);
  }
}
