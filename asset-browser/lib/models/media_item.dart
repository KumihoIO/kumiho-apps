// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';

/// Represents a media item (image, video, etc.) in the browser
class MediaItem {
  final String id;
  final String name;
  final String artifactName;
  final String type;
  final String kind;  // Item kind (model, texture, workflow, etc.)
  final String revision;
  final List<String> tags;
  final String author;
  final DateTime date;
  final Color thumbColor;
  final String? thumbnailPath;
  final String? kref;      // Kumiho reference URI (e.g., kref://project/space/item.kind?r=1)
  final String? location;  // File location path
  final String? revisionKref; // Revision kref for destructive actions
  final bool deprecated;
  final ItemMetadata? metadata;

  const MediaItem({
    required this.id,
    required this.name,
    required this.artifactName,
    required this.type,
    required this.kind,
    required this.revision,
    required this.tags,
    required this.author,
    required this.date,
    required this.thumbColor,
    this.thumbnailPath,
    this.kref,
    this.location,
    this.revisionKref,
    this.deprecated = false,
    this.metadata,
  });

  bool get isVideo => type == 'mp4' || type == 'mov' || type == 'webm';
  bool get isImage => !isVideo;

  /// Check if thumbnail is a local file path
  bool get hasLocalThumbnail => thumbnailPath != null && !thumbnailPath!.startsWith('http');

  /// Check if thumbnail is an HTTP URL
  bool get hasHttpThumbnail => thumbnailPath != null && thumbnailPath!.startsWith('http');

  MediaItem copyWith({
    String? id,
    String? name,
    String? artifactName,
    String? type,
    String? kind,
    String? revision,
    List<String>? tags,
    String? author,
    DateTime? date,
    Color? thumbColor,
    String? thumbnailPath,
    String? kref,
    String? location,
    String? revisionKref,
    bool? deprecated,
    ItemMetadata? metadata,
  }) {
    return MediaItem(
      id: id ?? this.id,
      name: name ?? this.name,
      artifactName: artifactName ?? this.artifactName,
      type: type ?? this.type,
      kind: kind ?? this.kind,
      revision: revision ?? this.revision,
      tags: tags ?? this.tags,
      author: author ?? this.author,
      date: date ?? this.date,
      thumbColor: thumbColor ?? this.thumbColor,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      kref: kref ?? this.kref,
      location: location ?? this.location,
      revisionKref: revisionKref ?? this.revisionKref,
      deprecated: deprecated ?? this.deprecated,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artifactName': artifactName,
      'type': type,
      'kind': kind,
      'revision': revision,
      'tags': tags,
      'author': author,
      'date': date.toIso8601String(),
      'thumbColor': thumbColor.value,
      'thumbnailPath': thumbnailPath,
      'kref': kref,
      'location': location,
      'revisionKref': revisionKref,
      'deprecated': deprecated,
      'metadata': metadata?.toJson(),
    };
  }

  /// Create from JSON
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      name: json['name'] as String,
      artifactName: json['artifactName'] as String,
      type: json['type'] as String,
      kind: json['kind'] as String? ?? 'unknown',
      revision: json['revision'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      author: json['author'] as String,
      date: DateTime.parse(json['date'] as String),
      thumbColor: Color(json['thumbColor'] as int),
      thumbnailPath: json['thumbnailPath'] as String?,
      kref: json['kref'] as String?,
      location: json['location'] as String?,
      revisionKref: json['revisionKref'] as String?,
      deprecated: json['deprecated'] as bool? ?? false,
      metadata: json['metadata'] != null 
          ? ItemMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Metadata associated with a media item (generation settings, etc.)
class ItemMetadata {
  final String? prompt;
  final String? negativePrompt;
  final String? model;
  final List<String>? loras;
  final int? seed;
  final int? steps;
  final double? cfg;
  final String? sampler;
  final String? resolution;

  const ItemMetadata({
    this.prompt,
    this.negativePrompt,
    this.model,
    this.loras,
    this.seed,
    this.steps,
    this.cfg,
    this.sampler,
    this.resolution,
  });

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'model': model,
      'loras': loras,
      'seed': seed,
      'steps': steps,
      'cfg': cfg,
      'sampler': sampler,
      'resolution': resolution,
    };
  }

  /// Flatten to map of string values for search matching
  Map<String, String> toSearchMap() {
    final map = <String, String>{};
    void add(String key, Object? value) {
      if (value == null) return;
      map[key] = value.toString();
    }

    add('prompt', prompt);
    add('negativePrompt', negativePrompt);
    add('model', model);
    add('loras', loras?.join(', '));
    add('seed', seed);
    add('steps', steps);
    add('cfg', cfg);
    add('sampler', sampler);
    add('resolution', resolution);
    return map;
  }

  /// Create from JSON
  factory ItemMetadata.fromJson(Map<String, dynamic> json) {
    return ItemMetadata(
      prompt: json['prompt'] as String?,
      negativePrompt: json['negativePrompt'] as String?,
      model: json['model'] as String?,
      loras: (json['loras'] as List<dynamic>?)?.cast<String>(),
      seed: json['seed'] as int?,
      steps: json['steps'] as int?,
      cfg: (json['cfg'] as num?)?.toDouble(),
      sampler: json['sampler'] as String?,
      resolution: json['resolution'] as String?,
    );
  }
}
