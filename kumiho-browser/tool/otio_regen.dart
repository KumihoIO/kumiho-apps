// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds
//
// Rewrites an existing .otio file in place using the corrected OtioExport
// schema (so a file exported by an older build can be re-tested without
// re-exporting). Reads clips (name, target_url, duration, metadata) from the
// old document and re-emits a fresh, importer-friendly timeline.
//
// Usage: dart run tool/otio_regen.dart [path-to.otio]

import 'dart:convert';
import 'dart:io';

import '../lib/services/otio_export.dart';

String _toNativePath(String url) {
  if (url.startsWith('file://')) {
    try {
      return Uri.parse(url).toFilePath();
    } catch (_) {
      return url;
    }
  }
  return url;
}

double? _seconds(Map<String, dynamic>? sourceRange) {
  final dur = sourceRange?['duration'] as Map<String, dynamic>?;
  final value = (dur?['value'] as num?)?.toDouble();
  final rate = (dur?['rate'] as num?)?.toDouble();
  if (value == null || rate == null || rate == 0) return null;
  return value / rate;
}

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args[0]
      : r'C:\Users\isake\.kumiho\exports\otio\test.otio';

  final file = File(path);
  final doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final name = doc['name'] as String? ?? 'timeline';
  final stack = doc['tracks'] as Map<String, dynamic>;

  final clips = <OtioClipInput>[];
  for (final track in (stack['children'] as List? ?? const [])) {
    for (final raw in ((track as Map)['children'] as List? ?? const [])) {
      final clip = raw as Map<String, dynamic>;
      final mr = clip['media_reference'] as Map<String, dynamic>?;
      final targetUrl = mr?['target_url'] as String?;
      if (targetUrl == null || targetUrl.isEmpty) continue;
      final meta = <String, String>{};
      final kmeta = (mr?['metadata'] as Map?)?['kumiho'] as Map?;
      kmeta?.forEach((k, v) => meta['$k'] = '$v');
      clips.add(OtioClipInput(
        name: clip['name'] as String? ?? 'clip',
        targetUrl: _toNativePath(targetUrl),
        durationSeconds: _seconds(clip['source_range'] as Map<String, dynamic>?),
        metadata: meta,
      ));
    }
  }

  final fixed = OtioExport.encode(OtioExport.buildTimeline(name: name, clips: clips));
  await file.writeAsString(fixed);
  stdout.writeln('Rewrote $path with ${clips.length} clip(s) using corrected OTIO schema (Clip.1 + available_range).');
}
