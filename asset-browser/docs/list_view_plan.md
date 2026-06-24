# List View Mode Implementation Plan

## Overview
Transform the list view mode to show **Items** (not artifacts) with a hierarchical detail panel showing Revisions → Artifacts, along with auto-collapsing playlist panels.

---

## Phase 1: Data Model & Provider Updates

### 1.1 Create New Data Models
**File:** `lib/models/list_view_models.dart`

```dart
// ItemListEntry - represents an item in list view
class ItemListEntry {
  String itemKref;
  String name;
  String kind;
  String author;
  DateTime createdAt;
  DateTime modifiedAt;
  int revisionCount;
  String? latestTag;
}

// RevisionListEntry - represents a revision in the detail panel
class RevisionListEntry {
  String revisionKref;
  int number;
  List<String> tags;
  String author;
  DateTime modifiedAt;
  bool isLatest;
}

// ArtifactListEntry - represents an artifact
class ArtifactListEntry {
  String artifactKref;
  String name;
  String location;
  DateTime modifiedAt;
  String author;
}
```

### 1.2 Add Providers
**File:** `lib/providers/kumiho_provider.dart`

- `itemsListProvider` - Fetch items for list view (different from grid view which shows artifacts)
- `itemRevisionsProvider(itemKref)` - Fetch revisions for selected item
- `revisionArtifactsProvider(revisionKref)` - Fetch artifacts for selected revision
- `revisionMetadataProvider(revisionKref)` - Fetch full metadata for info panel

### 1.3 Update Browser State
**File:** `lib/providers/browser_provider.dart`

Add new state fields:
- `selectedItemForList: ItemListEntry?` - Currently selected item in list view
- `selectedRevision: RevisionListEntry?` - Currently selected revision
- `selectedArtifact: ArtifactListEntry?` - Currently selected artifact

Add auto-collapse behavior:
- When `isGridView` changes to `false` (list mode):
  - Auto-collapse playlist sidebar (`isPlaylistCollapsed = true`)
  - Auto-hide playlist area at bottom

---

## Phase 2: List View Widget Update

### 2.1 Update List Header
**File:** `lib/widgets/media_views.dart` - `_ListHeader`

New columns:
| Item Name | Kind | Author | Created | Modified |
|-----------|------|--------|---------|----------|

### 2.2 Update List Item Widget
**File:** `lib/widgets/media_views.dart` - `MediaList` & `_ListItem`

- Fetch from `itemsListProvider` instead of artifacts
- Show item-level data (not artifact data)
- Remove thumbnail column (items don't have thumbnails)
- Add icon based on `kind`

### 2.3 Update MediaList Widget
Connect to new `itemsListProvider` for list view mode.

---

## Phase 3: Detail Panel Redesign

### 3.1 Create Section Components
**File:** `lib/widgets/detail_panel.dart`

Create 3 collapsible sections:

#### `_RevisionsSection`
- Vertical scrollable list
- Shows: `v{number}` with tags (badges), author, date
- Tag badges: `latest` (green), `published` (blue), `delivered` (orange)
- Click to select revision
- Selected state highlight

#### `_InfoSection`  
- Tree-view style key-value display
- Scrollable vertically
- Copy-to-clipboard on kref
- Shows metadata from selected revision

#### `_ArtifactsSection`
- Table/list with columns: Name, Location, Modified
- Both horizontal and vertical scroll
- Copy-to-clipboard on location
- Click to select artifact for details

### 3.2 Detail Panel Layout
```
┌─────────────────────────┐
│ Item Header (name/kind) │
├─────────────────────────┤
│ ▼ Revisions (40%)       │ ← Scrollable
│   v10 [latest]          │
│   v9  [published]       │
│   v9  [delivered]       │
│   v8                    │
│   ...                   │
├─────────────────────────┤
│ ▼ Information (40%)     │ ← Scrollable
│   Key: Value            │
│   Kref: xxx    [📋]     │
│   ...                   │
├─────────────────────────┤
│ ▼ Artifacts (20%)       │ ← Both scrolls
│   Name | Location | Date│
│   ...                   │
└─────────────────────────┘
```

### 3.3 Context-Aware Panel Behavior
- **Grid view mode:** Show current detail panel (artifact-focused)
- **List view mode:** Show new 3-section panel (item/revision-focused)

---

## Phase 4: Panel Auto-Collapse

### 4.1 Update `setGridView` Method
**File:** `lib/providers/browser_provider.dart`

```dart
void setGridView(bool isGrid) {
  if (!isGrid) {
    // Switching to list view - collapse playlists
    state = state.copyWith(
      isGridView: false,
      isPlaylistCollapsed: true,
      // Store previous state for restoration
    );
  } else {
    // Switching to grid view - restore previous state
    state = state.copyWith(isGridView: true);
  }
}
```

### 4.2 Update Main Layout
**File:** `lib/screens/browser_screen.dart` (or wherever main layout is)

- Conditionally render playlist area based on `isGridView`
- Auto-collapse sidebar in list mode

---

## Phase 5: Copy-to-Clipboard Feature

### 5.1 Create Reusable Widget
**File:** `lib/widgets/copyable_text.dart`

```dart
class CopyableText extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
}
```

Shows text with clipboard icon, copies on click with snackbar feedback.

---

## Implementation Order

1. **Phase 1.1-1.2**: Data models and providers (foundation)
2. **Phase 4**: Auto-collapse behavior (simple state change)
3. **Phase 2**: List view widget updates (show items)
4. **Phase 3**: Detail panel redesign (main feature)
5. **Phase 5**: Copy-to-clipboard (polish)

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/models/list_view_models.dart` | **NEW** - List view data models |
| `lib/models/models.dart` | Export new models |
| `lib/providers/kumiho_provider.dart` | Add item/revision/artifact providers |
| `lib/providers/browser_provider.dart` | Add list view state, auto-collapse |
| `lib/widgets/media_views.dart` | Update MediaList, _ListHeader, _ListItem |
| `lib/widgets/detail_panel.dart` | Add 3-section layout for list mode |
| `lib/widgets/copyable_text.dart` | **NEW** - Reusable copy widget |
| `lib/screens/browser_screen.dart` | Conditional playlist visibility |

---

## Estimated Complexity
- **Data Models**: Low
- **Providers**: Medium (API integration)
- **List View**: Medium  
- **Detail Panel**: High (most work)
- **Auto-collapse**: Low

---

## Section Height Distribution

| Section | Height % | Rationale |
|---------|----------|-----------|
| Revisions | 40% | Many revisions possible, needs scrolling |
| Information | 40% | Metadata can be extensive, tree-view needs space |
| Artifacts | 20% | Usually fewer artifacts, horizontal scroll handles long paths |
