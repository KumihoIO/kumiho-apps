// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../services/asset_actions.dart';
import '../theme/kumiho_theme.dart';
import 'artifact_viewer.dart';

Color _tagAccent(BuildContext context, Color base) {
  if (KumihoTheme.isDarkMode(context)) return base;
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withLightness((hsl.lightness * 0.74).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
      .toColor();
}

Color _tagTextAccent(BuildContext context, Color base) {
  if (KumihoTheme.isDarkMode(context)) return base;
  final accent = _tagAccent(context, base);
  final hsl = HSLColor.fromColor(accent);
  return hsl.withLightness((hsl.lightness * 0.82).clamp(0.0, 1.0)).toColor();
}

/// Helper to format DateTime as relative string
String _formatRelativeDate(DateTime? date) {
  if (date == null) return 'N/A';
  final now = DateTime.now();
  final difference = now.difference(date);
  
  if (difference.inDays > 365) {
    return '${(difference.inDays / 365).floor()}y ago';
  } else if (difference.inDays > 30) {
    return '${(difference.inDays / 30).floor()}mo ago';
  } else if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'just now';
  }
}

/// Detail panel for list view mode with 3 sections:
/// - Revisions (40%)
/// - Information (40%)
/// - Artifacts (20%)
class ListDetailPanel extends ConsumerWidget {
  const ListDetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    final state = ref.watch(browserProvider);
    final notifier = ref.read(browserProvider.notifier);
    final selection = ref.watch(listViewSelectionNotifierProvider);

    return Row(
      children: [
        // Resize handle
        _ResizeHandle(
          onDrag: (delta) => notifier.setDetailPanelWidth(state.detailPanelWidth - delta),
        ),
        // Detail panel content
        Container(
          width: state.detailPanelWidth,
          color: colors.backgroundSidebar,
          child: selection.selectedItem == null
              ? const _EmptyState()
              : _ListDetailContent(selection: selection),
        ),
      ],
    );
  }
}

// ==================== RESIZE HANDLE ==================== //

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;

  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          decoration: BoxDecoration(
            color: colors.borderDark,
            border: Border(
              left: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: colors.textVeryDimmed,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== EMPTY STATE ==================== //

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 48, color: colors.textVeryDimmed.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Select an item to view details',
            style: TextStyle(color: colors.textDimmed.withValues(alpha: 0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ==================== MAIN CONTENT ==================== //

class _ListDetailContent extends ConsumerWidget {
  final ListViewSelection selection;

  const _ListDetailContent({required this.selection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = KumihoTheme.of(context);
    return Column(
      children: [
        // Header with item name
        _ItemHeader(item: selection.selectedItem!),
        // 3 sections
        Expanded(
          child: Column(
            children: [
              // Revisions section (40%)
              Expanded(
                flex: 40,
                child: _RevisionsSection(itemKref: selection.selectedItem!.itemKref),
              ),
              Divider(height: 1, color: colors.borderSubtle),
              // Information section (40%)
              Expanded(
                flex: 40,
                child: _InformationSection(selection: selection),
              ),
              Divider(height: 1, color: colors.borderSubtle),
              // Artifacts section (20%)
              Expanded(
                flex: 20,
                child: _ArtifactsSection(selection: selection),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== ITEM HEADER ==================== //

class _ItemHeader extends StatelessWidget {
  final ItemListEntry item;

  const _ItemHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(item.kindIcon, size: 20, color: item.kindColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _CopyableKref(kref: item.itemKref),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== COPYABLE KREF ==================== //

class _CopyableKref extends StatelessWidget {
  final String kref;

  const _CopyableKref({required this.kref});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return InkWell(
      onTap: () => _copyToClipboard(context, kref),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                kref,
                style: TextStyle(
                  color: colors.textDimmed.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.copy_outlined,
              size: 12,
              color: colors.textDimmed.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

void _copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Copied: $text'),
      duration: const Duration(seconds: 2),
      backgroundColor: KumihoTheme.primary,
    ),
  );
}

// ==================== REVISIONS SECTION ==================== //

class _RevisionsSection extends ConsumerWidget {
  final String itemKref;

  const _RevisionsSection({required this.itemKref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisionsAsync = ref.watch(itemRevisionsProvider(itemKref));
    final selection = ref.watch(listViewSelectionNotifierProvider);
    final notifier = ref.read(listViewSelectionNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Revisions', icon: Icons.history),
        Expanded(
          child: revisionsAsync.when(
            data: (revisions) {
              if (revisions.isEmpty) {
                return const _EmptySectionState(message: 'No revisions');
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: revisions.length,
                itemBuilder: (context, index) {
                  final revision = revisions[index];
                  final isSelected = selection.selectedRevision?.revisionKref == revision.revisionKref;
                  return _RevisionRow(
                    revision: revision,
                    isSelected: isSelected,
                    onTap: () => notifier.selectRevision(revision),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (error, _) => _ErrorState(message: error.toString()),
          ),
        ),
      ],
    );
  }
}

class _RevisionRow extends StatelessWidget {
  final RevisionListEntry revision;
  final bool isSelected;
  final VoidCallback onTap;

  const _RevisionRow({
    required this.revision,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final isDark = KumihoTheme.isDarkMode(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? KumihoTheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? KumihoTheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // Revision number
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.backgroundCard,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v${revision.number}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Tags
            Expanded(
              child: Wrap(
                spacing: 4,
                children: revision.tags.map((tag) {
                  final tagColor = RevisionListEntry.getTagColor(tag);
                  final accent = _tagAccent(context, tagColor);
                  final textAccent = _tagTextAccent(context, tagColor);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.20 : 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: textAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Author/username
            SizedBox(
              width: 60,
              child: Text(
                revision.username.isNotEmpty ? revision.username : revision.author,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Created date
            Text(
              _formatRelativeDate(revision.createdAt),
              style: TextStyle(
                color: colors.textVeryDimmed,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== INFORMATION SECTION == //

class _InformationSection extends ConsumerWidget {
  final ListViewSelection selection;

  const _InformationSection({required this.selection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Priority: artifact > revision > item
    final artifact = selection.selectedArtifact;
    final revision = selection.selectedRevision;
    final item = selection.selectedItem!;

    // Determine what to show and the title
    String sectionTitle;
    Widget content;

    if (artifact != null) {
      sectionTitle = 'Artifact Info';
      content = _ArtifactInfoTree(artifact: artifact);
    } else if (revision != null) {
      sectionTitle = 'Revision Info';
      content = _RevisionInfoTree(revisionKref: revision.revisionKref);
    } else {
      sectionTitle = 'Item Info';
      content = _ItemInfoTree(item: item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: sectionTitle, icon: Icons.info_outline),
        Expanded(child: content),
      ],
    );
  }
}

class _ItemInfoTree extends StatelessWidget {
  final ItemListEntry item;

  const _ItemInfoTree({required this.item});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Name', value: item.name),
          _InfoRow(label: 'Kind', value: item.kind),
            _InfoRow(label: 'Author', value: item.username.isNotEmpty ? item.username : item.author),
           _InfoRow(label: 'Revisions', value: item.revisionCount < 0 ? '—' : '${item.revisionCount}'),
            _InfoRow(label: 'Created', value: item.createdAt?.toIso8601String().split('T').first ?? 'N/A'),
            _InfoRow(label: 'Modified', value: item.modifiedAt?.toIso8601String().split('T').first ?? 'N/A'),
            _InfoRow(label: 'Kref', value: item.itemKref, copyable: true),
            if (item.latestTags.isNotEmpty)
              _InfoRow(label: 'Tags', value: item.latestTags.join(', ')),
            // Metadata section
          if (item.metadata.isNotEmpty)
            ..._buildMetadataRows(context, item.metadata),
        ],
      ),
    );
  }

  List<Widget> _buildMetadataRows(BuildContext context, Map<String, String> metadata) {
    final widgets = <Widget>[];
    if (metadata.isEmpty) return widgets;
    final colors = KumihoTheme.of(context);

    widgets.add(Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        'Metadata',
        style: TextStyle(
          color: colors.textDimmed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ));

    metadata.forEach((key, value) {
      widgets.add(_InfoRow(
        label: key,
        value: value,
        indent: 12,
      ));
    });

    return widgets;
  }
}

class _RevisionInfoTree extends ConsumerWidget {
  final String revisionKref;

  const _RevisionInfoTree({required this.revisionKref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(revisionDetailProvider(revisionKref));

    return detailAsync.when(
      data: (detail) {
        if (detail == null) {
          return const _EmptySectionState(message: 'No revision details');
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Revision', value: 'v${detail.number}'),
                _InfoRow(label: 'Author', value: detail.username.isNotEmpty ? detail.username : detail.author),
                _InfoRow(label: 'Created', value: detail.createdAt?.toIso8601String().split('T').first ?? 'N/A'),
              if (detail.tags.isNotEmpty)
                _InfoRow(label: 'Tags', value: detail.tags.join(', ')),
              _InfoRow(label: 'Kref', value: revisionKref, copyable: true),
              // Metadata section
              if (detail.metadata.isNotEmpty)
                ..._buildMetadataRows(context, detail.metadata),
            ],
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => _ErrorState(message: error.toString()),
    );
  }

  List<Widget> _buildMetadataRows(BuildContext context, Map<String, String> metadata) {
    final widgets = <Widget>[];
    if (metadata.isEmpty) return widgets;
    final colors = KumihoTheme.of(context);

    widgets.add(Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        'Metadata',
        style: TextStyle(
          color: colors.textDimmed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ));

    metadata.forEach((key, value) {
      widgets.add(_InfoRow(
        label: key,
        value: value,
        indent: 12,
      ));
    });

    return widgets;
  }
}

class _ArtifactInfoTree extends StatelessWidget {
  final ArtifactListEntry artifact;

  const _ArtifactInfoTree({required this.artifact});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Name', value: artifact.name),
          _InfoRow(label: 'Location', value: artifact.location, copyable: true),
          _InfoRow(label: 'Extension', value: artifact.fileExtension.isNotEmpty ? artifact.fileExtension : 'N/A'),
          _InfoRow(label: 'Filename', value: artifact.filename),
          _InfoRow(label: 'Author', value: artifact.username.isNotEmpty ? artifact.username : artifact.author),
          _InfoRow(label: 'Created', value: artifact.createdAt?.toIso8601String().split('T').first ?? 'N/A'),
          _InfoRow(label: 'Modified', value: artifact.modifiedAt?.toIso8601String().split('T').first ?? 'N/A'),
          _InfoRow(label: 'Kref', value: artifact.artifactKref, copyable: true),
          // Metadata section
          if (artifact.metadata.isNotEmpty)
            ..._buildMetadataRows(context, artifact.metadata),
        ],
      ),
    );
  }

  List<Widget> _buildMetadataRows(BuildContext context, Map<String, String> metadata) {
    final widgets = <Widget>[];
    if (metadata.isEmpty) return widgets;
    final colors = KumihoTheme.of(context);

    widgets.add(Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        'Metadata',
        style: TextStyle(
          color: colors.textDimmed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ));

    metadata.forEach((key, value) {
      widgets.add(_InfoRow(
        label: key,
        value: value,
        indent: 12,
      ));
    });

    return widgets;
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final double indent;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.indent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tree connector
          if (indent > 0) ...[
            Container(
              width: 8,
              height: 12,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.borderSubtle, width: 1),
                  bottom: BorderSide(color: colors.borderSubtle, width: 1),
                ),
              ),
            ),
          ],
          // Label
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textDimmed,
                fontSize: 11,
              ),
            ),
          ),
          // Value
          Expanded(
            child: copyable
                ? InkWell(
                    onTap: () => _copyToClipboard(context, value),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.copy_outlined,
                          size: 10,
                          color: colors.textDimmed.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ==================== ARTIFACTS SECTION ==================== //

class _ArtifactsSection extends ConsumerWidget {
  final ListViewSelection selection;

  const _ArtifactsSection({required this.selection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revision = selection.selectedRevision;
    final revisionKref = revision?.revisionKref;

    // Offer "Add thumbnail" only on a mutable (unpublished) revision that does
    // not already have a 'thumbnail' artifact.
    Widget? action;
    if (revisionKref != null && revision != null && !revision.isPublished) {
      final hasThumbnail = ref.watch(revisionArtifactsProvider(revisionKref)).maybeWhen(
            data: (artifacts) => artifacts.any((a) => a.name == 'thumbnail'),
            orElse: () => true,
          );
      if (!hasThumbnail) {
        action = _SectionAction(
          icon: Icons.add_photo_alternate_outlined,
          tooltip: 'Add thumbnail',
          onTap: () => _addThumbnail(context, ref, revisionKref),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Artifacts', icon: Icons.folder_outlined, action: action),
        Expanded(
          child: revisionKref == null
              ? const _EmptySectionState(message: 'Select a revision')
              : _ArtifactsList(
                  revisionKref: revisionKref,
                  revisionMutable: revision != null && !revision.isPublished,
                ),
        ),
      ],
    );
  }

  Future<void> _addThumbnail(
      BuildContext context, WidgetRef ref, String revisionKref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await AssetActions.addThumbnail(ref, revisionKref);
      if (path != null) {
        messenger?.showSnackBar(const SnackBar(content: Text('Thumbnail added')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Failed to add thumbnail: $e')));
    }
  }
}

class _ArtifactsList extends ConsumerWidget {
  final String revisionKref;
  final bool revisionMutable;

  const _ArtifactsList({required this.revisionKref, required this.revisionMutable});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifactsAsync = ref.watch(revisionArtifactsProvider(revisionKref));
    final selection = ref.watch(listViewSelectionNotifierProvider);
    final notifier = ref.read(listViewSelectionNotifierProvider.notifier);

    return artifactsAsync.when(
      data: (artifacts) {
        if (artifacts.isEmpty) {
          return const _EmptySectionState(message: 'No artifacts');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: artifacts.length,
          itemBuilder: (context, index) {
            final artifact = artifacts[index];
            final isSelected = selection.selectedArtifact?.artifactKref == artifact.artifactKref;
            return _ArtifactRow(
              artifact: artifact,
              isSelected: isSelected,
              revisionMutable: revisionMutable,
              onTap: () => notifier.selectArtifact(artifact),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => _ErrorState(message: error.toString()),
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  final ArtifactListEntry artifact;
  final bool isSelected;
  final bool revisionMutable;
  final VoidCallback onTap;

  const _ArtifactRow({
    required this.artifact,
    required this.isSelected,
    required this.revisionMutable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? KumihoTheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? KumihoTheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // File type icon
            Icon(
              artifact.icon,
              size: 16,
              color: isSelected ? KumihoTheme.primary : colors.textDimmed,
            ),
            const SizedBox(width: 8),
            // Name and location
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artifact.name,
                    style: TextStyle(
                      color: isSelected ? colors.textPrimary : colors.textSecondary,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    artifact.location,
                    style: TextStyle(
                      color: colors.textDimmed.withValues(alpha: 0.7),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Open / edit the artifact content.
            IconButton(
              onPressed: () => ArtifactViewerDialog.show(
                context,
                artifactName: artifact.name,
                location: artifact.location,
                revisionMutable: revisionMutable,
              ),
              icon: Icon(
                Icons.open_in_new,
                size: 14,
                color: colors.textDimmed.withValues(alpha: 0.7),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Open / edit',
            ),
            // Copy icon - only this triggers copy
            IconButton(
              onPressed: () => _copyToClipboard(context, artifact.location),
              icon: Icon(
                Icons.copy_outlined,
                size: 14,
                color: colors.textDimmed.withValues(alpha: 0.7),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Copy location',
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== SECTION HEADER ==================== //

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? action;

  const _SectionHeader({required this.title, required this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.textDimmed),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          if (action != null) ...[
            const Spacer(),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Compact icon action used in a [_SectionHeader] trailing slot.
class _SectionAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SectionAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 16, color: colors.textSecondary),
        ),
      ),
    );
  }
}

// ==================== HELPER WIDGETS ==================== //

class _EmptySectionState extends StatelessWidget {
  final String message;

  const _EmptySectionState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: colors.textDimmed.withValues(alpha: 0.5),
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Error: $message',
          style: const TextStyle(
            color: Colors.redAccent,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
