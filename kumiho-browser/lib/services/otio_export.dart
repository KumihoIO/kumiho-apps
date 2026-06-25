// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';

/// One clip in a playlist timeline.
class OtioClipInput {
  final String name;

  /// `target_url` for the clip's media reference: a `file://` URI for local
  /// paths or an http(s) URL for remote media.
  final String targetUrl;

  /// Clip duration in seconds. When unknown a default is used (playlists don't
  /// carry per-item media durations).
  final double? durationSeconds;

  /// Extra key/values stored under the media reference's
  /// `metadata.kumiho` (e.g. the source revision/artifact kref).
  final Map<String, String> metadata;

  const OtioClipInput({
    required this.name,
    required this.targetUrl,
    this.durationSeconds,
    this.metadata = const {},
  });
}

/// Builds an OpenTimelineIO timeline (the `.otio` JSON interchange format)
/// directly, without a native OTIO binding. The emitted document conforms to
/// the standard OTIO schema (Timeline.1 / Stack.1 / Track.1 / Clip.2 /
/// ExternalReference.1 / TimeRange.1 / RationalTime.1) and loads in OTIO tools.
class OtioExport {
  static const double rate = 24.0;
  static const double defaultClipSeconds = 5.0;

  /// Builds a single-video-track timeline from [clips], in order.
  static Map<String, dynamic> buildTimeline({
    required String name,
    required List<OtioClipInput> clips,
  }) {
    return {
      'OTIO_SCHEMA': 'Timeline.1',
      'name': name,
      'global_start_time': _rationalTime(0),
      'metadata': {
        'kumiho': {'generator': 'kumiho-asset-browser'},
      },
      'tracks': {
        'OTIO_SCHEMA': 'Stack.1',
        'name': 'tracks',
        'children': [
          {
            'OTIO_SCHEMA': 'Track.1',
            'name': 'Video',
            'kind': 'Video',
            'children': [for (final clip in clips) _clip(clip)],
          },
        ],
      },
    };
  }

  static Map<String, dynamic> _clip(OtioClipInput clip) {
    final durationFrames = (clip.durationSeconds ?? defaultClipSeconds) * rate;
    // Use Clip.1 (single `media_reference`), the most widely supported form for
    // importers like DaVinci Resolve — OTIO upgrades it to Clip.2 internally.
    // The media reference carries an `available_range` so importers know the
    // media's extent, which is required to place still images.
    return {
      'OTIO_SCHEMA': 'Clip.1',
      'name': clip.name,
      'source_range': _timeRange(durationFrames),
      'media_reference': {
        'OTIO_SCHEMA': 'ExternalReference.1',
        'target_url': clip.targetUrl,
        'available_range': _timeRange(durationFrames),
        if (clip.metadata.isNotEmpty) 'metadata': {'kumiho': clip.metadata},
      },
    };
  }

  static Map<String, dynamic> _timeRange(num durationFrames) => {
        'OTIO_SCHEMA': 'TimeRange.1',
        'start_time': _rationalTime(0),
        'duration': _rationalTime(durationFrames),
      };

  static Map<String, dynamic> _rationalTime(num value) => {
        'OTIO_SCHEMA': 'RationalTime.1',
        'value': value,
        'rate': rate,
      };

  /// Pretty-prints a timeline document to `.otio` JSON text.
  static String encode(Map<String, dynamic> timeline) =>
      const JsonEncoder.withIndent('  ').convert(timeline);
}
