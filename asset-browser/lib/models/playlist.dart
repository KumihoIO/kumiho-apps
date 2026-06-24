// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'media_item.dart';

/// Represents a playlist/collection of media items
class Playlist {
  final String id;
  final String name;
  final int itemCount;
  final Color color;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<MediaItem> items; // Actual items in the playlist

  const Playlist({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.color,
    this.description,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  Playlist copyWith({
    String? id,
    String? name,
    int? itemCount,
    Color? color,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<MediaItem>? items,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      itemCount: itemCount ?? this.itemCount,
      color: color ?? this.color,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'itemCount': itemCount,
      'color': color.value,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory Playlist.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>?)
        ?.map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
        .toList() ?? [];
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      itemCount: json['itemCount'] as int? ?? itemsList.length,
      color: Color(json['color'] as int),
      description: json['description'] as String?,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'] as String) 
          : null,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String) 
          : null,
      items: itemsList,
    );
  }
}
