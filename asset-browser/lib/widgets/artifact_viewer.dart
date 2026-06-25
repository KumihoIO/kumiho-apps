// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../theme/kumiho_theme.dart';

enum _ArtifactKind { markdown, text, image, video, binary }

/// A viewer/editor for a single artifact, resolved from its `location`.
///
/// Markdown and text content is loaded from the local file at `location` (or
/// fetched read-only over http(s) for remote URLs) and can be edited in place
/// and saved back to the local file when the owning revision is mutable. Images
/// preview inline; video/binary fall back to copy-path / open-externally.
///
/// Kumiho is BYO-storage: it stores only the `location` string, so this widget
/// reads and writes the underlying file itself.
class ArtifactViewerDialog extends StatefulWidget {
  final String artifactName;
  final String location;

  /// Whether the owning revision is mutable (unpublished). Editing and saving
  /// are only offered when this is true AND `location` is a local file.
  final bool revisionMutable;

  const ArtifactViewerDialog({
    super.key,
    required this.artifactName,
    required this.location,
    required this.revisionMutable,
  });

  static Future<void> show(
    BuildContext context, {
    required String artifactName,
    required String location,
    required bool revisionMutable,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ArtifactViewerDialog(
        artifactName: artifactName,
        location: location,
        revisionMutable: revisionMutable,
      ),
    );
  }

  /// Whether the artifact at [location] is a markdown/text file the in-app
  /// editor can meaningfully open (used to gate the grid "View / edit" action).
  static bool isTextual(String location) {
    final kind = _ArtifactViewerDialogState._detectKind(location);
    return kind == _ArtifactKind.markdown || kind == _ArtifactKind.text;
  }

  @override
  State<ArtifactViewerDialog> createState() => _ArtifactViewerDialogState();
}

class _ArtifactViewerDialogState extends State<ArtifactViewerDialog> {
  late final _ArtifactKind _kind;
  late final bool _isRemote;
  late final String? _localPathValue;
  final _controller = TextEditingController();

  bool _loading = true;
  String? _error;
  String _content = '';
  bool _editing = false;
  bool _dirty = false;
  bool _saving = false;

  bool get _isTextual =>
      _kind == _ArtifactKind.markdown || _kind == _ArtifactKind.text;

  bool get _canEdit =>
      widget.revisionMutable && _localPathValue != null && _isTextual;

  @override
  void initState() {
    super.initState();
    _kind = _detectKind(widget.location);
    _isRemote = _looksRemote(widget.location);
    _localPathValue = _localPath(widget.location);
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static bool _looksRemote(String location) =>
      location.startsWith('http://') || location.startsWith('https://');

  static _ArtifactKind _detectKind(String location) {
    final ext = p.extension(location.split('?').first).toLowerCase();
    const markdownExts = {'.md', '.markdown', '.mdx'};
    const textExts = {
      '.txt', '.json', '.yaml', '.yml', '.toml', '.ini', '.csv', '.tsv',
      '.xml', '.html', '.htm', '.css', '.js', '.ts', '.tsx', '.jsx', '.py',
      '.rs', '.go', '.sh', '.bash', '.zsh', '.sql', '.env', '.log', '.c',
      '.cpp', '.h', '.hpp', '.java', '.kt', '.dart', '.rb', '.php', '.lua',
      '.r', '.cfg', '.conf', '.properties', '.gradle', '.gitignore',
    };
    const imageExts = {
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.avif',
    };
    const videoExts = {'.mp4', '.webm', '.mov', '.m4v', '.ogv', '.mkv'};
    if (markdownExts.contains(ext)) return _ArtifactKind.markdown;
    if (textExts.contains(ext)) return _ArtifactKind.text;
    if (imageExts.contains(ext)) return _ArtifactKind.image;
    if (videoExts.contains(ext)) return _ArtifactKind.video;
    return _ArtifactKind.binary;
  }

  /// Filesystem path for a local location (handles `file://` URIs, plain paths
  /// and Windows drive letters), or null if it is not a readable local path.
  static String? _localPath(String location) {
    if (location.isEmpty || _looksRemote(location)) return null;
    try {
      final uri = Uri.parse(location);
      if (uri.scheme == 'file') return uri.toFilePath();
      // No scheme, or a single-letter "scheme" that is really a Windows drive
      // (e.g. C:\...), means a plain local path.
      if (uri.scheme.isEmpty || uri.scheme.length == 1) return location;
      // smb:, s3:, gs:, etc. — not a local file.
      return null;
    } catch (_) {
      return location;
    }
  }

  Future<void> _load() async {
    if (!_isTextual) {
      setState(() => _loading = false);
      return;
    }
    try {
      String text;
      if (_isRemote) {
        final resp = await http.get(Uri.parse(widget.location));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        text = resp.body;
      } else if (_localPathValue != null) {
        text = await File(_localPathValue).readAsString();
      } else {
        throw Exception('Unsupported location scheme');
      }
      if (!mounted) return;
      setState(() {
        _content = text;
        _controller.text = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final path = _localPathValue;
    if (path == null) return;
    setState(() => _saving = true);
    try {
      await File(path).writeAsString(_controller.text);
      if (!mounted) return;
      setState(() {
        _content = _controller.text;
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _openExternally() async {
    final uri = _isRemote
        ? Uri.parse(widget.location)
        : (_localPathValue != null ? Uri.file(_localPathValue) : null);
    if (uri == null) return;
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Could not open location')));
      }
    }
  }

  void _copyLocation() {
    Clipboard.setData(ClipboardData(text: widget.location));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Location copied')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (size.width * 0.7).clamp(420.0, 1000.0),
        height: (size.height * 0.82).clamp(360.0, 900.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(colors),
            Divider(height: 1, color: colors.borderSubtle),
            Expanded(child: _buildBody(colors)),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(KumihoColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: colors.backgroundHeader,
      child: Row(
        children: [
          Icon(_kindIcon, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.artifactName,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_canEdit && !_loading && _error == null) ...[
            _HeaderButton(
              icon: _editing ? Icons.visibility_outlined : Icons.edit_outlined,
              tooltip: _editing ? 'Preview' : 'Edit',
              onTap: () => setState(() => _editing = !_editing),
            ),
            if (_editing)
              _HeaderButton(
                icon: Icons.save_outlined,
                tooltip: 'Save',
                enabled: _dirty && !_saving,
                onTap: _save,
              ),
          ],
          _HeaderButton(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(KumihoColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return _buildFallback(colors, 'Could not load: $_error');
    }
    switch (_kind) {
      case _ArtifactKind.image:
        return _buildImage(colors);
      case _ArtifactKind.video:
        return _buildFallback(colors, 'Video artifact');
      case _ArtifactKind.binary:
        return _buildFallback(colors, 'Binary artifact');
      case _ArtifactKind.markdown:
        return _editing ? _buildEditor(colors) : _buildMarkdown(colors);
      case _ArtifactKind.text:
        return _editing ? _buildEditor(colors) : _buildPlainText(colors);
    }
  }

  Widget _buildMarkdown(KumihoColors colors) {
    return Markdown(
      data: _content,
      selectable: true,
      padding: const EdgeInsets.all(16),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
        code: TextStyle(
          color: colors.textPrimary,
          fontFamily: 'monospace',
          backgroundColor: colors.backgroundHeader,
          fontSize: 12,
        ),
        codeblockDecoration: BoxDecoration(
          color: colors.backgroundHeader,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
    );
  }

  Widget _buildPlainText(KumihoColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _content,
        style: TextStyle(
          color: colors.textSecondary,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildEditor(KumihoColors colors) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        onChanged: (_) {
          if (!_dirty) setState(() => _dirty = true);
        },
        style: TextStyle(
          color: colors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.backgroundHeader.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.borderSubtle),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

  Widget _buildImage(KumihoColors colors) {
    final Widget image = _isRemote
        ? Image.network(widget.location, fit: BoxFit.contain)
        : (_localPathValue != null
            ? Image.file(File(_localPathValue), fit: BoxFit.contain)
            : const SizedBox.shrink());
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: image,
        ),
      ),
    );
  }

  Widget _buildFallback(KumihoColors colors, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_kindIcon, size: 40, color: colors.textDimmed),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _openExternally,
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Open externally'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _copyLocation,
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copy location'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(KumihoColors colors) {
    String status;
    IconData icon;
    if (_canEdit) {
      status = _editing
          ? 'Editing — saves to the local file'
          : 'Mutable revision — open the editor to change this file';
      icon = Icons.edit_outlined;
    } else if (_isTextual && _localPathValue != null) {
      status = 'Read-only — published (immutable) revision';
      icon = Icons.lock_outline;
    } else if (_isRemote) {
      status = 'Read-only — remote location';
      icon = Icons.cloud_outlined;
    } else {
      status = 'Read-only';
      icon = Icons.lock_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
        border: Border(top: BorderSide(color: colors.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: colors.textDimmed),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(color: colors.textDimmed, fontSize: 11)),
          const Spacer(),
          Flexible(
            child: Text(
              widget.location,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textDimmed.withValues(alpha: 0.7),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _kindIcon {
    switch (_kind) {
      case _ArtifactKind.markdown:
        return Icons.article_outlined;
      case _ArtifactKind.text:
        return Icons.description_outlined;
      case _ArtifactKind.image:
        return Icons.image_outlined;
      case _ArtifactKind.video:
        return Icons.movie_outlined;
      case _ArtifactKind.binary:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 17,
            color: enabled ? colors.textSecondary : colors.textDimmed.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
