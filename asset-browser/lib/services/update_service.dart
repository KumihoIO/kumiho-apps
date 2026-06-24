// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AppUpdateAsset {
  final String name;
  final Uri downloadUrl;

  const AppUpdateAsset({required this.name, required this.downloadUrl});
}

class AppUpdateCheckResult {
  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final Uri releasePageUrl;
  final AppUpdateAsset? windowsInstaller;
  final AppUpdateAsset? macArtifact;
  final AppUpdateAsset? linuxDeb;
  final AppUpdateAsset? linuxRpm;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.releasePageUrl,
    this.windowsInstaller,
    this.macArtifact,
    this.linuxDeb,
    this.linuxRpm,
  });
}

class UpdateService {
  /// Public distribution repo to check for updates.
  ///
  /// Override at build time with:
  /// - UPDATE_GITHUB_OWNER
  /// - UPDATE_GITHUB_REPO
  ///
  /// Example:
  /// flutter build windows --dart-define=UPDATE_GITHUB_OWNER=kumihoclouds --dart-define=UPDATE_GITHUB_REPO=kumiho-browser
  static const String _owner = String.fromEnvironment('UPDATE_GITHUB_OWNER', defaultValue: 'kumihoclouds');
  static const String _repo = String.fromEnvironment('UPDATE_GITHUB_REPO', defaultValue: 'kumiho-browser');

  static Uri get _latestReleaseApi => Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');
  static Uri get _tagsApi => Uri.parse('https://api.github.com/repos/$_owner/$_repo/tags?per_page=100');
  static Uri get _fallbackReleasePage => Uri.parse('https://github.com/$_owner/$_repo/releases');

  Future<AppUpdateCheckResult> checkForUpdates({required String currentVersion}) async {
    final headers = const {
      'Accept': 'application/vnd.github+json',
      // GitHub API recommends a UA; some requests get rejected without it.
      'User-Agent': 'kumiho-browser',
    };

    final response = await http.get(_latestReleaseApi, headers: headers);

    // Some repos deliberately do not use GitHub Releases (only tags). In that case,
    // fall back to the tags API so Linux can still "Check for updates" and offer a
    // downloads page.
    if (response.statusCode == 404) {
      final latest = await _fetchLatestVersionFromTags(headers: headers) ?? '0.0.0';
      final updateAvailable = _compareSemver(_stripBuild(currentVersion), latest) < 0;
      return AppUpdateCheckResult(
        currentVersion: _stripBuild(currentVersion),
        latestVersion: latest,
        updateAvailable: updateAvailable,
        releasePageUrl: _fallbackReleasePage,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Update check failed: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    final releasePage = Uri.tryParse((json['html_url'] as String?) ?? '') ?? _fallbackReleasePage;

    final latest = _normalizeVersionFromTag(tagName) ?? '0.0.0';

    final assetsJson = (json['assets'] as List<dynamic>?) ?? const [];
    final assets = <AppUpdateAsset>[];
    for (final item in assetsJson) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim();
      final url = (item['browser_download_url'] as String?)?.trim();
      if (name == null || url == null) continue;
      final parsed = Uri.tryParse(url);
      if (parsed == null) continue;
      assets.add(AppUpdateAsset(name: name, downloadUrl: parsed));
    }

    final updateAvailable = _compareSemver(_stripBuild(currentVersion), latest) < 0;

    return AppUpdateCheckResult(
      currentVersion: _stripBuild(currentVersion),
      latestVersion: latest,
      updateAvailable: updateAvailable,
      releasePageUrl: releasePage,
      windowsInstaller: _pickWindowsInstaller(assets),
      macArtifact: _pickMacArtifact(assets),
      linuxDeb: _pickLinuxDeb(assets),
      linuxRpm: _pickLinuxRpm(assets),
    );
  }

  Future<String?> _fetchLatestVersionFromTags({required Map<String, String> headers}) async {
    final response = await http.get(_tagsApi, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final json = jsonDecode(response.body);
    if (json is! List) return null;

    String? best;
    for (final item in json) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final v = _normalizeVersionFromTag(name);
      if (v == null) continue;
      if (best == null || _compareSemver(v, best) > 0) {
        best = v;
      }
    }
    return best;
  }

  Future<File> downloadToTemp({
    required Uri url,
    required String fileName,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final request = http.Request('GET', url);
    request.headers['User-Agent'] = 'kumiho-browser';
    final streamed = await http.Client().send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('Download failed: HTTP ${streamed.statusCode}');
    }

    final contentLength = streamed.contentLength;
    final total = (contentLength != null && contentLength > 0) ? contentLength : null;
    final tempDir = Directory.systemTemp.createTempSync('kumiho_update_');
    final outFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    final sink = outFile.openWrite();

    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }

    return outFile;
  }

  Future<void> launchWindowsInstallerAndExit({required File installer}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows installer updates are only supported on Windows');
    }

    await Process.start(
      installer.path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );

    // Give the detached process a moment to start before exiting.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  static String _stripBuild(String version) {
    final plus = version.indexOf('+');
    return plus >= 0 ? version.substring(0, plus) : version;
  }

  static String? _normalizeVersionFromTag(String tagName) {
    var t = tagName;
    if (t.startsWith('browser-v')) t = t.substring('browser-v'.length);
    if (t.startsWith('v')) t = t.substring(1);
    final m = RegExp(r'^([0-9]+\.[0-9]+\.[0-9]+)').firstMatch(t);
    return m?.group(1);
  }

  static int _compareSemver(String a, String b) {
    final pa = _parseSemver(a);
    final pb = _parseSemver(b);
    for (var i = 0; i < 3; i++) {
      final d = pa[i].compareTo(pb[i]);
      if (d != 0) return d;
    }
    return 0;
  }

  static List<int> _parseSemver(String v) {
    final parts = v.split('.');
    int p(int i) => (i < parts.length) ? int.tryParse(parts[i]) ?? 0 : 0;
    return [p(0), p(1), p(2)];
  }

  static AppUpdateAsset? _pickWindowsInstaller(List<AppUpdateAsset> assets) {
    // Prefer the Inno Setup installer.
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('.exe') && n.contains('kumihobrowsersetup')) return a;
    }
    // Fallback: any exe.
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.exe')) return a;
    }
    return null;
  }

  static AppUpdateAsset? _pickMacArtifact(List<AppUpdateAsset> assets) {
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('.dmg')) return a;
    }
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.contains('macos') && n.endsWith('.zip')) return a;
    }
    return null;
  }

  static AppUpdateAsset? _pickLinuxDeb(List<AppUpdateAsset> assets) {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.deb')) return a;
    }
    return null;
  }

  static AppUpdateAsset? _pickLinuxRpm(List<AppUpdateAsset> assets) {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.rpm')) return a;
    }
    return null;
  }
}
