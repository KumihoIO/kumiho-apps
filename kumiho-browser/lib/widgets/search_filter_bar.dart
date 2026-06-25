// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/browser_provider.dart';
import '../providers/kumiho_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/kumiho_theme.dart';
import 'keyboard_shortcuts_handler.dart';

/// Search bar with filter chips
class SearchFilterBar extends ConsumerWidget {
  const SearchFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFilters = ref.watch(mediaFiltersProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final isGridView = ref.watch(browserProvider.select((s) => s.isGridView));
    final chips = ref.watch(searchChipsProvider);

    void toggleFilter(MediaFilterType filter) {
      final current = ref.read(mediaFiltersProvider);
      final updated = Set<MediaFilterType>.from(current);
      if (updated.contains(filter)) {
        updated.remove(filter);
      } else {
        updated.add(filter);
      }
      ref.read(mediaFiltersProvider.notifier).state = updated;
    }

    final colors = KumihoTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.backgroundSidebar,
        border: Border(
          bottom: BorderSide(color: colors.borderDark, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showFilters = constraints.maxWidth > 400;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SearchInput(
                      value: searchQuery,
                      onChanged: (value) {
                        ref.read(searchQueryProvider.notifier).state = value;
                      },
                    ),
                  ),
                  if (showFilters) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FilterButton(
                              icon: Icons.filter_alt_off,
                              label: 'Clear',
                              isActive: activeFilters.isEmpty && chips.isEmpty && searchQuery.isEmpty,
                              onTap: () {
                                ref.read(mediaFiltersProvider.notifier).state = {};
                                ref.read(searchChipsProvider.notifier).state = [];
                                ref.read(searchQueryProvider.notifier).state = '';
                              },
                            ),
                            if (isGridView) ...[
                              const SizedBox(width: 8),
                              _FilterButton(
                                icon: Icons.image,
                                label: 'Images',
                                isActive: activeFilters.contains(MediaFilterType.images),
                                onTap: () => toggleFilter(MediaFilterType.images),
                              ),
                              const SizedBox(width: 8),
                              _FilterButton(
                                icon: Icons.movie,
                                label: 'Videos',
                                isActive: activeFilters.contains(MediaFilterType.videos),
                                onTap: () => toggleFilter(MediaFilterType.videos),
                              ),
                            ],
                            const SizedBox(width: 8),
                            _FilterButton(
                              icon: Icons.today,
                              label: 'Today',
                              isActive: activeFilters.contains(MediaFilterType.today),
                              onTap: () => toggleFilter(MediaFilterType.today),
                            ),
                            const SizedBox(width: 8),
                            _FilterButton(
                              icon: Icons.date_range,
                              label: 'Week',
                              isActive: activeFilters.contains(MediaFilterType.week),
                              onTap: () => toggleFilter(MediaFilterType.week),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 6),
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: chips
                        .map(
                          (chip) => InputChip(
                            label: Text(
                              chip,
                              style: TextStyle(color: colors.textPrimary, fontSize: 12, height: 1.05),
                            ),
                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            deleteIcon: Icon(Icons.close, size: 11, color: colors.textDimmed),
                            onDeleted: () {
                              final updated = List<String>.from(chips)..remove(chip);
                              ref.read(searchChipsProvider.notifier).state = updated;
                            },
                            backgroundColor: colors.backgroundSecondary,
                            deleteIconColor: colors.textDimmed,
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ==================== SEARCH INPUT ==================== //

class _SearchInput extends ConsumerStatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchInput({
    required this.value,
    required this.onChanged,
  });

  @override
  ConsumerState<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends ConsumerState<_SearchInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addChipFromInput() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chips = ref.read(searchChipsProvider);
    if (!chips.contains(text)) {
      ref.read(searchChipsProvider.notifier).state = [...chips, text];
    }
    _controller.clear();
    widget.onChanged('');
    // Keep focus so user can type the next chip immediately
    ref.read(searchFocusNodeProvider).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final searchFocusNode = ref.watch(searchFocusNodeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.textDimmed),
          const SizedBox(width: 8),
          Expanded(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.keyA, control: true): SelectAllTextIntent(SelectionChangedCause.keyboard),
              },
              child: Actions(
                actions: {
                  SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                    onInvoke: (intent) {
                      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _controller,
                  focusNode: searchFocusNode,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search by prompt, model, LoRA, seed, or filename...',
                    hintStyle: TextStyle(color: colors.textVeryDimmed, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: widget.onChanged,
                  onSubmitted: (_) => _addChipFromInput(),
                  textInputAction: TextInputAction.search,
                ),
              ),
            ),
          ),
          if (widget.value.isNotEmpty || ref.watch(searchChipsProvider).isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: colors.textDimmed),
              onPressed: () {
                ref.read(searchChipsProvider.notifier).state = [];
                _controller.clear();
                widget.onChanged('');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24),
            ),
        ],
      ),
    );
  }
}

// ==================== FILTER BUTTON ==================== //

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? KumihoTheme.primary.withValues(alpha: 0.2) : colors.backgroundCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? KumihoTheme.primary : colors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? KumihoTheme.primary : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? KumihoTheme.primary : colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== LEGACY FILTER CHIP (kept for compatibility) ==================== //

class FilterChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;

  const FilterChip({
    super.key,
    required this.icon,
    required this.label,
    this.initialValue = false,
    this.onChanged,
  });

  @override
  State<FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<FilterChip> {
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _isActive = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        setState(() => _isActive = !_isActive);
        widget.onChanged?.call(_isActive);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _isActive ? KumihoTheme.primary.withValues(alpha: 0.2) : KumihoTheme.backgroundCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isActive ? KumihoTheme.primary : KumihoTheme.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 14,
              color: _isActive ? KumihoTheme.primary : KumihoTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: _isActive ? KumihoTheme.primary : KumihoTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== BREADCRUMB BAR ==================== //

class BreadcrumbBar extends ConsumerWidget {
  const BreadcrumbBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(browserProvider);
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    // Use Kumiho breadcrumb if authenticated
    if (isAuthenticated) {
      final breadcrumbPath = ref.watch(breadcrumbPathProvider);
      final itemCount = ref.watch(itemCountProvider);
      
      final colors = KumihoTheme.of(context);
      
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.backgroundHeader,
          border: Border(
            bottom: BorderSide(color: colors.borderDark, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Breadcrumb items - wrap in Expanded with clipping to prevent overflow
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...breadcrumbPath.asMap().entries.map((entry) {
                      final index = entry.key;
                      final label = entry.value;
                      final isFirst = index == 0;
                      
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isFirst) const _BreadcrumbSeparator(),
                          _KumihoBreadcrumbItem(
                            label: label,
                            isFirst: isFirst,
                            depth: index,
                            onTap: () {
                              // Navigate to this level by truncating the path
                              if (isFirst) {
                                // Clicking project clears all spaces
                                ref.read(selectedSpacePathProvider.notifier).state = [];
                              } else {
                                // Clicking a space truncates to that level
                                final newPath = ref.read(selectedSpacePathProvider).sublist(0, index);
                                ref.read(selectedSpacePathProvider.notifier).state = newPath;
                              }
                            },
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Item count
            Text(
              '$itemCount items',
              style: TextStyle(
                color: colors.textDimmed,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Fallback to mock breadcrumb
    final colors = KumihoTheme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.backgroundHeader,
        border: Border(
          bottom: BorderSide(color: colors.borderDark, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Breadcrumb items - wrap in Expanded with scrolling to prevent overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.selectedProject != null)
                    _BreadcrumbItem(label: state.selectedProject!, isFirst: true),
                  if (state.selectedSpace != null) ...[
                    const _BreadcrumbSeparator(),
                    _BreadcrumbItem(label: state.selectedSpace!),
                  ],
                  if (state.selectedSubSpace != null) ...[
                    const _BreadcrumbSeparator(),
                    _BreadcrumbItem(label: state.selectedSubSpace!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${state.mediaItems.length} items',
            style: TextStyle(
              color: colors.textDimmed,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kumiho breadcrumb item with click to navigate
class _KumihoBreadcrumbItem extends StatelessWidget {
  final String label;
  final bool isFirst;
  final int depth;
  final VoidCallback? onTap;

  const _KumihoBreadcrumbItem({
    required this.label,
    this.isFirst = false,
    required this.depth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFirst) ...[
              Icon(Icons.folder_outlined, size: 14, color: KumihoTheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isFirst ? KumihoTheme.primary : colors.textSecondary,
                fontSize: 12,
                fontWeight: isFirst ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreadcrumbItem extends StatelessWidget {
  final String label;
  final bool isFirst;

  const _BreadcrumbItem({
    required this.label,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFirst) ...[
              Icon(Icons.folder_outlined, size: 14, color: KumihoTheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreadcrumbSeparator extends StatelessWidget {
  const _BreadcrumbSeparator();

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(Icons.chevron_right, size: 16, color: colors.textVeryDimmed),
    );
  }
}
