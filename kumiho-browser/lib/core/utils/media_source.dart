// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/foundation.dart';

/// Repairs and normalizes media sources for playback/thumbnailing.
///
/// - Leaves http(s) and file URIs unchanged.
/// - Converts Windows absolute/UNC paths to `file:///...` URIs.
/// - Repairs control characters introduced by JSON escape decoding (e.g. "\t").
String normalizeMediaSource(String input) {
  final trimmed = repairPossiblyEscapedWindowsPath(input).trim();
  if (trimmed.isEmpty) return trimmed;

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://')) {
    return trimmed;
  }

  // If it already looks like a URI with a scheme, keep it.
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
  if (hasScheme) return trimmed;

  // Windows absolute path or UNC path -> file:// URI.
  final isWindowsAbs = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed) || trimmed.startsWith('\\\\');
  if (isWindowsAbs) {
    return Uri.file(trimmed, windows: true).toString();
  }

  return trimmed;
}

/// Some Windows paths arrive via JSON with sequences like "\t" (tab) and
/// "\v" (vertical tab) interpreted as escapes, turning into control chars.
/// That corrupts the path (e.g. outputs\videos\test -> outputs<0x0B>ideos<0x09>est).
///
/// Repair by expanding common control chars back into backslash + letter.
String repairPossiblyEscapedWindowsPath(String input) {
  if (input.isEmpty) return input;

  // Fast check: if there are no ASCII control chars, return as-is.
  final hasControl = input.codeUnits.any((c) => c < 0x20);
  if (!hasControl) return input;

  // Only apply this repair on Windows desktop; on other platforms these control
  // characters are unlikely to appear in paths and we want to be conservative.
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (!isWindows) return input;

  return input
      .replaceAll('\t', r'\\t')
      .replaceAll('\n', r'\\n')
      .replaceAll('\r', r'\\r')
      .replaceAll('\f', r'\\f')
      .replaceAll('\b', r'\\b')
      // Vertical tab isn't common, but we've observed it in production logs.
      .replaceAll(String.fromCharCode(0x0B), r'\\v');
}
