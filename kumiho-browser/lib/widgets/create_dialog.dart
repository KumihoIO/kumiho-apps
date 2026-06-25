// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/kumiho_provider.dart';
import '../services/asset_actions.dart';

/// The kind of entity a [CreateDialog] creates.
enum CreateKind { project, space, item, revision, artifact }

/// A single parameterized dialog for creating any node in the Kumiho hierarchy
/// (project / space / item / revision / artifact), mirroring the web app's
/// create modal. Fields shown depend on [kind]; required context (parent space
/// path, item kref, revision kref) is supplied by the caller.
class CreateDialog extends ConsumerStatefulWidget {
  final CreateKind kind;
  final String? parentPath; // space, item
  final String? itemKref; // revision
  final String? revisionKref; // artifact
  final String? contextLabel; // shown under the title, e.g. "in /proj/space"

  const CreateDialog({
    super.key,
    required this.kind,
    this.parentPath,
    this.itemKref,
    this.revisionKref,
    this.contextLabel,
  });

  static Future<void> show(
    BuildContext context, {
    required CreateKind kind,
    String? parentPath,
    String? itemKref,
    String? revisionKref,
    String? contextLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CreateDialog(
        kind: kind,
        parentPath: parentPath,
        itemKref: itemKref,
        revisionKref: revisionKref,
        contextLabel: contextLabel,
      ),
    );
  }

  @override
  ConsumerState<CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends ConsumerState<CreateDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _kind = TextEditingController();
  final _location = TextEditingController();
  final _metadata = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.kind == CreateKind.artifact) {
      _name.text = 'content.md';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _kind.dispose();
    _location.dispose();
    _metadata.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.kind) {
      case CreateKind.project:
        return 'New project';
      case CreateKind.space:
        return 'New space';
      case CreateKind.item:
        return 'New item';
      case CreateKind.revision:
        return 'New revision';
      case CreateKind.artifact:
        return 'New artifact';
    }
  }

  bool get _canSubmit {
    switch (widget.kind) {
      case CreateKind.project:
      case CreateKind.space:
        return _name.text.trim().isNotEmpty;
      case CreateKind.item:
        return _name.text.trim().isNotEmpty && _kind.text.trim().isNotEmpty;
      case CreateKind.revision:
        return true; // auto-numbered, no required fields
      case CreateKind.artifact:
        return _name.text.trim().isNotEmpty && _location.text.trim().isNotEmpty;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ref = this.ref;
      final metadata = AssetActions.parseMetadata(_metadata.text);
      switch (widget.kind) {
        case CreateKind.project:
          final name = _name.text.trim();
          await AssetActions.createProject(ref, name,
              description: _description.text.trim());
          // Navigate to the new project.
          ref.read(selectedProjectNameProvider.notifier).state = name;
          break;
        case CreateKind.space:
          await AssetActions.createSpace(
              ref, widget.parentPath!, _name.text.trim());
          break;
        case CreateKind.item:
          await AssetActions.createItem(
              ref, widget.parentPath!, _name.text.trim(), _kind.text.trim());
          break;
        case CreateKind.revision:
          await AssetActions.createRevision(ref, widget.itemKref!,
              metadata: metadata);
          break;
        case CreateKind.artifact:
          await AssetActions.createArtifact(
              ref, widget.revisionKref!, _name.text.trim(), _location.text.trim(),
              metadata: metadata);
          break;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$_title created')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickLocation() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose the artifact file',
      withData: false,
    );
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _location.text = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_title),
          if (widget.contextLabel != null && widget.contextLabel!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.contextLabel!,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._fields(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_canSubmit && !_submitting) ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  List<Widget> _fields() {
    final onChanged = (_) => setState(() {});
    switch (widget.kind) {
      case CreateKind.project:
        return [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: onChanged,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
            maxLines: 2,
          ),
        ];
      case CreateKind.space:
        return [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Space name'),
            onChanged: onChanged,
            onSubmitted: (_) => _submit(),
          ),
        ];
      case CreateKind.item:
        return [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Item name'),
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kind,
            decoration: const InputDecoration(
              labelText: 'Kind',
              hintText: 'e.g. model, texture, image, document, workflow',
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _metadataField(),
        ];
      case CreateKind.revision:
        return [
          const Text(
            'A new revision is created with the next version number.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          _metadataField(),
        ];
      case CreateKind.artifact:
        return [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Artifact name'),
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _location,
                  decoration: const InputDecoration(
                    labelText: 'Location / path reference',
                  ),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickLocation,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Browse'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _metadataField(),
        ];
    }
  }

  Widget _metadataField() {
    return TextField(
      controller: _metadata,
      maxLines: 3,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: const InputDecoration(
        labelText: 'Metadata (optional)',
        hintText: 'JSON object, or key: value lines',
        alignLabelWithHint: true,
      ),
    );
  }
}
