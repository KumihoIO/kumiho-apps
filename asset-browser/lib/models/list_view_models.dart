// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';

/// Represents a space (folder) entry in the list view
class SpaceListEntry {
  final String spacePath;
  final String name;
  final String author;
  final String username;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final int childCount;
  final bool deprecated;

  const SpaceListEntry({
    required this.spacePath,
    required this.name,
    required this.author,
    required this.username,
    this.createdAt,
    this.modifiedAt,
    this.childCount = 0,
    this.deprecated = false,
  });

  /// Folder icon
  IconData get icon => Icons.folder;

  /// Folder color - yellow/amber like typical folder icons
  Color get color => const Color(0xFFFFB74D);

  SpaceListEntry copyWith({
    String? spacePath,
    String? name,
    String? author,
    String? username,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? childCount,
    bool? deprecated,
  }) {
    return SpaceListEntry(
      spacePath: spacePath ?? this.spacePath,
      name: name ?? this.name,
      author: author ?? this.author,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      childCount: childCount ?? this.childCount,
      deprecated: deprecated ?? this.deprecated,
    );
  }
}

/// Union type for list view entries - can be either a space or an item
sealed class ListViewEntry {
  const ListViewEntry();
}

class SpaceEntry extends ListViewEntry {
  final SpaceListEntry space;
  const SpaceEntry(this.space);
}

class ItemEntry extends ListViewEntry {
  final ItemListEntry item;
  const ItemEntry(this.item);
}

/// Represents an item entry in the list view
/// Different from MediaItem which represents artifacts
class ItemListEntry {
  final String itemKref;
  final String name;
  final String kind;
  final String author;
  final String username;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final int revisionCount;
  final List<String> latestTags;
  final bool deprecated;
  final Map<String, String> metadata;

  const ItemListEntry({
    required this.itemKref,
    required this.name,
    required this.kind,
    required this.author,
    required this.username,
    this.createdAt,
    this.modifiedAt,
    this.revisionCount = 0,
    this.latestTags = const [],
    this.deprecated = false,
    this.metadata = const {},
  });

  /// Get icon for item kind
  IconData get kindIcon {
    switch (kind.toLowerCase()) {
      case 'model':
      case 'checkpoint':
        return Icons.view_in_ar;
      case 'lora':
        return Icons.tune;
      case 'texture':
        return Icons.texture;
      case 'image':
        return Icons.image;
      case 'workflow':
        return Icons.account_tree;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Get color for item kind
  Color get kindColor {
    switch (kind.toLowerCase()) {
      case 'model':
      case 'checkpoint':
        return const Color(0xFFE17055);
      case 'lora':
        return const Color(0xFFFFB347);
      case 'texture':
        return const Color(0xFF4ECDC4);
      case 'image':
        return const Color(0xFF74B9FF);
      case 'workflow':
        return const Color(0xFFA29BFE);
      case 'video':
        return const Color(0xFFFF7675);
      case 'audio':
        return const Color(0xFF00B894);
      default:
        return const Color(0xFF636E72);
    }
  }

  ItemListEntry copyWith({
    String? itemKref,
    String? name,
    String? kind,
    String? author,
    String? username,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? revisionCount,
    List<String>? latestTags,
    bool? deprecated,
    Map<String, String>? metadata,
  }) {
    return ItemListEntry(
      itemKref: itemKref ?? this.itemKref,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      author: author ?? this.author,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      revisionCount: revisionCount ?? this.revisionCount,
      latestTags: latestTags ?? this.latestTags,
      deprecated: deprecated ?? this.deprecated,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Represents a revision entry in the detail panel
class RevisionListEntry {
  final String revisionKref;
  final int number;
  final List<String> tags;
  final String author;
  final String username;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isLatest;
  final bool isPublished;
  final bool deprecated;
  final Map<String, String> metadata;
  final String? defaultArtifact;

  const RevisionListEntry({
    required this.revisionKref,
    required this.number,
    this.tags = const [],
    required this.author,
    required this.username,
    this.createdAt,
    this.modifiedAt,
    this.isLatest = false,
    this.isPublished = false,
    this.deprecated = false,
    this.metadata = const {},
    this.defaultArtifact,
  });

  /// Check if revision has a specific tag
  bool hasTag(String tag) => tags.contains(tag);

  /// Get display label for revision (e.g., "v10")
  String get displayLabel => 'v$number';

  /// Get color for a specific tag
  static Color getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'latest':
        return const Color(0xFF00B894);
      case 'published':
        return const Color(0xFF0984E3);
      case 'delivered':
        return const Color(0xFFE17055);
      case 'approved':
        return const Color(0xFF6C5CE7);
      case 'wip':
        return const Color(0xFFFDAB46);
      case 'review':
        return const Color(0xFFFF7675);
      default:
        return const Color(0xFF636E72);
    }
  }

  RevisionListEntry copyWith({
    String? revisionKref,
    int? number,
    List<String>? tags,
    String? author,
    String? username,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isLatest,
    bool? isPublished,
    bool? deprecated,
    Map<String, String>? metadata,
    String? defaultArtifact,
  }) {
    return RevisionListEntry(
      revisionKref: revisionKref ?? this.revisionKref,
      number: number ?? this.number,
      tags: tags ?? this.tags,
      author: author ?? this.author,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isLatest: isLatest ?? this.isLatest,
      isPublished: isPublished ?? this.isPublished,
      deprecated: deprecated ?? this.deprecated,
      metadata: metadata ?? this.metadata,
      defaultArtifact: defaultArtifact ?? this.defaultArtifact,
    );
  }
}

/// Represents an artifact entry in the detail panel
class ArtifactListEntry {
  final String artifactKref;
  final String name;
  final String location;
  final String author;
  final String username;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool deprecated;
  final Map<String, String> metadata;

  const ArtifactListEntry({
    required this.artifactKref,
    required this.name,
    required this.location,
    required this.author,
    required this.username,
    this.createdAt,
    this.modifiedAt,
    this.deprecated = false,
    this.metadata = const {},
  });

  /// Get file extension from location
  String get fileExtension {
    final parts = location.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get icon based on file extension
  IconData get icon {
    switch (fileExtension) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'webm':
      case 'avi':
        return Icons.videocam;
      case 'fbx':
      case 'obj':
      case 'glb':
      case 'gltf':
        return Icons.view_in_ar;
      case 'safetensors':
      case 'ckpt':
      case 'pt':
      case 'pth':
        return Icons.memory;
      case 'json':
        return Icons.data_object;
      case 'zip':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Get filename from location path
  String get filename {
    final parts = location.split('/');
    return parts.isNotEmpty ? parts.last : location;
  }

  ArtifactListEntry copyWith({
    String? artifactKref,
    String? name,
    String? location,
    String? author,
    String? username,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? deprecated,
    Map<String, String>? metadata,
  }) {
    return ArtifactListEntry(
      artifactKref: artifactKref ?? this.artifactKref,
      name: name ?? this.name,
      location: location ?? this.location,
      author: author ?? this.author,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      deprecated: deprecated ?? this.deprecated,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Selection state for list view detail panel
class ListViewSelection {
  final ItemListEntry? selectedItem;
  final RevisionListEntry? selectedRevision;
  final ArtifactListEntry? selectedArtifact;

  const ListViewSelection({
    this.selectedItem,
    this.selectedRevision,
    this.selectedArtifact,
  });

  ListViewSelection copyWith({
    ItemListEntry? selectedItem,
    RevisionListEntry? selectedRevision,
    ArtifactListEntry? selectedArtifact,
    bool clearItem = false,
    bool clearRevision = false,
    bool clearArtifact = false,
  }) {
    return ListViewSelection(
      selectedItem: clearItem ? null : (selectedItem ?? this.selectedItem),
      selectedRevision: clearRevision ? null : (selectedRevision ?? this.selectedRevision),
      selectedArtifact: clearArtifact ? null : (selectedArtifact ?? this.selectedArtifact),
    );
  }

  /// Check if anything is selected
  bool get hasSelection => selectedItem != null;

  /// Clear all selections
  static const ListViewSelection empty = ListViewSelection();
}
