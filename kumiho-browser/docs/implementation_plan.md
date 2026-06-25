# 🦊 Kumiho Browser — Implementation Plan v1.0

**From UI Mockup to Production: kumiho-dart SDK Integration**

---

## 📋 Current State Assessment

### ✅ Completed (UI Mockup Phase)
- [x] Flutter desktop app structure with window management
- [x] Component-based architecture (`lib/widgets/`, `lib/pages/`, `lib/providers/`)
- [x] Adobe Premiere Pro-style dark theme UI
- [x] Header bar with project/space dropdowns, view toggle, zoom slider
- [x] Collapsible playlist sidebar
- [x] Media grid/list views with clip containers
- [x] Resizable detail panel with metadata display
- [x] Bottom playlist area with drag-drop reordering
- [x] Riverpod state management (mock data)
- [x] Theme constants (`KumihoTheme`)

### 🔄 Next Phase: kumiho-dart SDK Integration

---

## 📦 1. kumiho-dart SDK Packaging

### Current Setup (Local Path Dependency)

The browser already references kumiho-dart as a local path dependency:

```yaml
# pubspec.yaml
dependencies:
  kumiho:
    path: ../kumiho-dart
```

This works for **local development** when both repos are siblings:
```
KumihoSaaS/
├── kumiho-asset-browser/   # The browser app
├── kumiho-dart/            # The SDK
└── ...
```

### Packaging Options for Production

#### Option A: Git Dependency (Recommended for Now)

```yaml
dependencies:
  kumiho:
    git:
      url: https://github.com/kumihoclouds/kumiho-dart.git
      ref: main  # or specific tag like v0.2.0
```

**Pros:** No publishing required, easy CI/CD, private repo support  
**Cons:** Requires Git access, slower than pub.dev

#### Option B: Pub.dev Publication (Future)

```yaml
dependencies:
  kumiho: ^0.2.0
```

**Pros:** Standard Dart package management, caching, versioning  
**Cons:** Public package (unless using private pub server)

#### Option C: Private Pub Server (Enterprise)

For enterprise deployment, consider [unpub](https://github.com/nicklockwood/unpub) or Google Cloud Artifact Registry.

### Recommended Approach

1. **Development Phase:** Keep `path: ../kumiho-dart`
2. **Alpha/Beta:** Switch to `git:` dependency with tags
3. **Production:** Publish to pub.dev (public) or private registry

---

## 🏗 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kumiho Browser (Flutter)                     │
├─────────────────────────────────────────────────────────────────┤
│  UI Layer                                                        │
│  ┌─────────────┬──────────────┬──────────────┬──────────────┐   │
│  │ HeaderBar   │ Sidebar      │ MediaViews   │ DetailPanel  │   │
│  │             │ (Playlists)  │ (Grid/List)  │              │   │
│  └─────────────┴──────────────┴──────────────┴──────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  State Layer (Riverpod)                                          │
│  ┌─────────────┬──────────────┬──────────────┬──────────────┐   │
│  │ AuthState   │ ProjectState │ BrowserState │ SearchState  │   │
│  │             │              │              │              │   │
│  └─────────────┴──────────────┴──────────────┴──────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Service Layer                                                   │
│  ┌─────────────┬──────────────┬──────────────┬──────────────┐   │
│  │ AuthService │ KumihoService│ CacheService │ ThumbnailSvc │   │
│  │             │ (SDK Wrapper)│ (SQLite/Hive)│              │   │
│  └─────────────┴──────────────┴──────────────┴──────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  kumiho-dart SDK                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ KumihoClient → gRPC → Kumiho Server (Rust) → Neo4j          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔐 3. Authentication Flow

### Firebase Popup Authentication (MVP)

The browser uses **Firebase Authentication** with popup-based login for seamless UX.

#### Firebase Configuration (Embedded)

```dart
// lib/core/constants/firebase_config.dart
class FirebaseConfig {
  static const String apiKey = 'AIzaSyBFAo7Nv48xAvbN18rL-3W41Dqheporh8E';
  static const String authDomain = 'kumiho-server.firebaseapp.com';
  static const String projectId = 'kumiho-server';
  static const String appId = '1:1024102474822:web:7d06c46d0682c6c8175647';
}
```

#### Auth Service Implementation

```dart
// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Current user stream for reactive UI
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  /// Get current Firebase ID token for gRPC calls
  Future<String?> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }
  
  /// Sign in with Google popup
  Future<UserCredential> signInWithGoogle() async {
    final googleProvider = GoogleAuthProvider();
    return _auth.signInWithPopup(googleProvider);
  }
  
  /// Sign in with GitHub popup
  Future<UserCredential> signInWithGitHub() async {
    final githubProvider = GithubAuthProvider();
    return _auth.signInWithPopup(githubProvider);
  }
  
  /// Sign in with email/password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }
  
  /// Sign out
  Future<void> signOut() => _auth.signOut();
}
```

#### Authentication Flow Diagram

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Kumiho Browser     │────▶│ Firebase Auth       │────▶│ Firebase ID         │
│  (Flutter Desktop)  │     │ (Popup Login)       │     │ Token               │
└─────────────────────┘     └─────────────────────┘     └──────────┬──────────┘
                                                                   │
                                                                   ▼
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Neo4j Graph DB     │◀────│ Kumiho Server       │◀────│ kumiho-dart SDK     │
│  (Tenant Data)      │     │ (Rust gRPC)         │     │ (gRPC + Token)      │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

#### Supported Auth Providers

| Provider | Status | Notes |
|----------|--------|-------|
| Google | ✅ MVP | Primary login method |
| GitHub | ✅ MVP | Popular with AI creators |
| Email/Password | ✅ MVP | Fallback option |
| Apple | 🔮 Future | For macOS users |

#### Token Management

- **Auto-refresh**: kumiho-dart SDK handles token refresh automatically
- **Secure storage**: Token cached via `flutter_secure_storage`
- **Expiry handling**: SDK refreshes token 5 minutes before expiry

### Token Storage Locations

| Platform | Storage |
|----------|---------|
| Windows | Windows Credential Manager via `flutter_secure_storage` |
| macOS | Keychain via `flutter_secure_storage` |
| Linux | Secret Service (libsecret) |
| Web | Browser localStorage (Firebase handles this) |

### Desktop-Specific: Firebase Auth for Flutter Desktop

For Windows/macOS/Linux, Firebase popup uses system browser:

```dart
// lib/services/desktop_auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:desktop_webview_auth/desktop_webview_auth.dart';

class DesktopAuthService extends AuthService {
  /// Sign in using desktop webview for OAuth
  Future<UserCredential> signInWithGoogleDesktop() async {
    final result = await DesktopWebviewAuth.signIn(
      ProviderArgs.google(
        clientId: '<GOOGLE_CLIENT_ID>',
        redirectUri: 'https://kumiho-server.firebaseapp.com/__/auth/handler',
      ),
    );
    final credential = GoogleAuthProvider.credential(
      accessToken: result.accessToken,
      idToken: result.idToken,
    );
    return _auth.signInWithCredential(credential);
  }
}
```

---

## 📁 4. Implementation Phases

### Phase 1: Core SDK Integration (Week 1-2)

#### 1.1 Create Service Layer

```
lib/services/
├── kumiho_service.dart      # SDK wrapper with connection management
├── auth_service.dart        # Authentication & token management
├── cache_service.dart       # Local SQLite/Hive caching
└── thumbnail_service.dart   # Thumbnail generation & caching
```

#### 1.2 Update Providers

```dart
// lib/providers/auth_provider.dart
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// lib/providers/kumiho_provider.dart
final kumihoClientProvider = FutureProvider<KumihoClient>((ref) async {
  final authService = ref.watch(authServiceProvider);
  final idToken = await authService.getIdToken();
  
  if (idToken == null) throw Exception('Not authenticated');
  
  return KumihoClient(
    host: 'api.kumiho.cloud',  // or from settings
    port: 443,
    token: idToken,  // Firebase ID Token
  );
});

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  return client.listProjects();
});
```

#### 1.3 Data Model Mapping

Map SDK models to UI models:

| SDK Model | UI Model | Notes |
|-----------|----------|-------|
| `Item` | `MediaItem` | Add thumbnail path, local cache status |
| `Revision` | Part of `MediaItem` | Current revision displayed |
| `Artifact` | `ArtifactInfo` | File paths, mime types |
| `Project` | `Project` | Direct mapping |
| `Space` | `Space` | Hierarchical navigation |
| `Edge` | `LineageEdge` | For graph visualization |

### Phase 2: Gallery & Browsing (Week 2-3)

#### 2.1 Replace Mock Data

```dart
// lib/providers/browser_provider.dart
final mediaItemsProvider = FutureProvider.family<List<MediaItem>, SpacePath>((ref, path) async {
  final client = await ref.watch(kumihoClientProvider.future);
  final space = await client.getSpace(path);
  final items = await space.getItems();
  
  return items.map((item) => MediaItem.fromSdkItem(item)).toList();
});
```

#### 2.2 Thumbnail Pipeline

```dart
// lib/services/thumbnail_service.dart
class ThumbnailService {
  final _cache = <String, Uint8List>{};
  
  Future<Uint8List?> getThumbnail(String artifactPath) async {
    // 1. Check memory cache
    // 2. Check disk cache (Hive)
    // 3. Generate from artifact (if local file)
    // 4. Request from server (if remote)
  }
}
```

#### 2.3 Implement Real Navigation

- Project dropdown → `listProjects()`
- Space dropdown → `project.getSpaces()`
- Breadcrumb → Navigate space hierarchy
- Search → `client.searchItems(query)`

### Phase 3: Detail Panel & Metadata (Week 3-4)

#### 3.1 Full Metadata Display

```dart
// From PRD Section 8: Detail Panel
class DetailPanelData {
  final Item item;
  final Revision revision;
  final List<Artifact> artifacts;
  final Map<String, String> metadata;
  
  // Parsed metadata fields
  String? get prompt => metadata['prompt'];
  String? get negativePrompt => metadata['negative_prompt'];
  String? get model => metadata['model'];
  List<String> get loras => metadata['loras']?.split(',') ?? [];
  int? get seed => int.tryParse(metadata['seed'] ?? '');
  int? get steps => int.tryParse(metadata['steps'] ?? '');
  double? get cfg => double.tryParse(metadata['cfg'] ?? '');
  String? get sampler => metadata['sampler'];
  String? get resolution => metadata['resolution'];
}
```

#### 3.2 Revision History

```dart
final revisionsProvider = FutureProvider.family<List<Revision>, String>((ref, itemKref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  final item = await client.getItem(itemKref);
  return item.getRevisions();
});
```

### Phase 4: Lineage Graph (Week 4-5)

#### 4.1 Graph Data Provider

```dart
// lib/providers/lineage_provider.dart
final lineageGraphProvider = FutureProvider.family<LineageGraph, String>((ref, revisionKref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  
  // Get dependencies (what this revision uses)
  final deps = await client.getDependencies(revisionKref);
  
  // Get dependents (what uses this revision)
  final dependents = await client.getDependents(revisionKref);
  
  return LineageGraph(
    center: revisionKref,
    dependencies: deps,
    dependents: dependents,
  );
});
```

#### 4.2 Graph Visualization

Options:
1. **graphview** package - Force-directed layout
2. **flutter_graph_view** - Interactive graph
3. Custom Canvas rendering for performance

### Phase 5: Search & Filtering (Week 5-6)

#### 5.1 Search Implementation

```dart
// Per PRD Section 10: Search & Filter
class SearchQuery {
  String? promptText;
  String? modelName;
  String? loraName;
  String? inputFileName;
  IntRange? seedRange;
  DateRange? dateRange;
  String? resolution;
  bool? favoritesOnly;
  String? projectFilter;
}

final searchResultsProvider = FutureProvider.family<List<MediaItem>, SearchQuery>((ref, query) async {
  final client = await ref.watch(kumihoClientProvider.future);
  // Use SDK search API
  return client.searchItems(
    prompt: query.promptText,
    model: query.modelName,
    // ... other filters
  );
});
```

### Phase 6: Playlists & Collections (Week 6-7)

#### 6.1 Bundle Integration

Kumiho Bundles = Browser Playlists

```dart
final playlistsProvider = FutureProvider<List<Bundle>>((ref) async {
  final client = await ref.watch(kumihoClientProvider.future);
  final space = await client.getSpace('/user-playlists');
  return space.getBundles();
});

// Add item to playlist
Future<void> addToPlaylist(Bundle playlist, Item item) async {
  await playlist.addMember(item.kref.uri);
}
```

### Phase 7: Social Sharing (Week 7-8)

#### 7.1 Share Card Generation

```dart
// lib/services/share_service.dart
class ShareService {
  Future<Uint8List> generateShareCard(MediaItem item) async {
    // 1. Load thumbnail
    // 2. Overlay metadata (model, prompt preview, seed)
    // 3. Add "Generated with Kumiho" watermark (optional)
    // 4. Return PNG bytes
  }
  
  Future<void> shareToTwitter(MediaItem item) async {
    final card = await generateShareCard(item);
    // Use platform share APIs
  }
}
```

---

## 📂 5. File Structure (Target)

```
lib/
├── main.dart                    # App entry point
├── main_browser.dart            # Standalone browser entry
├── app/
│   ├── app.dart                 # App widget
│   └── router.dart              # Go Router config
├── core/
│   ├── constants/
│   │   └── api_constants.dart   # Server URLs, timeouts
│   ├── errors/
│   │   └── app_exceptions.dart  # Custom exceptions
│   └── utils/
│       ├── date_utils.dart
│       └── string_utils.dart
├── models/                      # UI data models
│   ├── models.dart              # Barrel export
│   ├── media_item.dart          # Extended with SDK mapping
│   ├── playlist.dart
│   └── lineage_node.dart
├── services/                    # Business logic
│   ├── services.dart            # Barrel export
│   ├── kumiho_service.dart      # SDK wrapper
│   ├── auth_service.dart        # Authentication
│   ├── cache_service.dart       # Local caching
│   ├── thumbnail_service.dart   # Thumbnail pipeline
│   └── share_service.dart       # Social sharing
├── providers/                   # Riverpod state
│   ├── providers.dart           # Barrel export
│   ├── auth_provider.dart       # Auth state
│   ├── kumiho_provider.dart     # SDK client provider
│   ├── browser_provider.dart    # UI state
│   ├── search_provider.dart     # Search state
│   └── lineage_provider.dart    # Graph data
├── pages/
│   ├── pages.dart
│   ├── media_browser_page.dart
│   ├── lineage_graph_page.dart
│   ├── settings_page.dart
│   └── login_page.dart
├── widgets/
│   ├── widgets.dart
│   ├── header_bar.dart
│   ├── playlist_sidebar.dart
│   ├── search_filter_bar.dart
│   ├── clip_container.dart
│   ├── media_views.dart
│   ├── detail_panel.dart
│   ├── playlist_area.dart
│   └── lineage_graph.dart       # Graph visualization
└── theme/
    └── kumiho_theme.dart
```

---

## 🧪 6. Testing Strategy

### Unit Tests
- Service layer (mocked SDK)
- Provider logic
- Model transformations

### Widget Tests
- Component rendering
- User interactions
- State updates

### Integration Tests
- Full flow with real SDK (staging server)
- Authentication flow
- CRUD operations

---

## 📊 7. Milestone Summary

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1-2 | Core SDK | Service layer, auth, providers |
| 2-3 | Gallery | Real data browsing, thumbnails |
| 3-4 | Details | Full metadata display, revisions |
| 4-5 | Lineage | Graph visualization |
| 5-6 | Search | Full-text search, filters |
| 6-7 | Playlists | Bundle integration |
| 7-8 | Sharing | Social share cards |

---

## 🚀 8. Getting Started

### Prerequisites

1. Kumiho server running (local or cloud)
2. API key from Kumiho Cloud dashboard
3. Flutter SDK 3.5+

### Development Setup

```powershell
# Clone repos (if not already)
git clone https://github.com/kumihoclouds/kumiho-asset-browser.git
git clone https://github.com/kumihoclouds/kumiho-dart.git

# Ensure they're siblings
ls
# kumiho-asset-browser/
# kumiho-dart/

# Get dependencies
cd kumiho-asset-browser
flutter pub get

# Run the browser
flutter run -d windows -t lib/main_browser.dart
```

### Environment Variables

```powershell
# For development with local server
$env:KUMIHO_HOST = "localhost"
$env:KUMIHO_PORT = "50051"
$env:KUMIHO_AUTH_TOKEN = "your-dev-token"

# For production
$env:KUMIHO_HOST = "api.kumiho.cloud"
$env:KUMIHO_PORT = "443"
```

---

## 📝 9. Open Questions

1. **Thumbnail Generation**: Client-side or server-side? (Recommendation: Client-side for local files, server-side for cloud)
2. **Offline Mode**: How much functionality without network? (Recommendation: Read-only with local cache)
3. **Multi-tenant**: Single workspace or multi-project? (PRD suggests project switching)
4. **ComfyUI Integration**: Direct plugin communication or file watching? (PRD: Logger Node via gRPC)

---

## 🎨 10. ComfyUI Integration

The Kumiho Browser is designed to work seamlessly with **kumiho-comfyui** custom nodes. Assets created in ComfyUI workflows automatically appear in the browser with full lineage tracking.

### ComfyUI Node Overview

| Node | Category | Purpose |
|------|----------|---------|
| **Kumiho Load Asset** | `Kumiho/IO` | Load assets via kref:// URI or dropdown |
| **Kumiho Save Image** | `Kumiho/IO` | Save images with auto-lineage |
| **Kumiho Save Video** | `Kumiho/IO` | Save videos with inline preview |
| **Kumiho Search Items** | `Kumiho/Search` | Search assets by name, kind, context |
| **Kumiho Create Edge** | `Kumiho/Graph` | Create dependency relationships |
| **Kumiho Tag Revision** | `Kumiho/Graph` | Apply tags (approved, published, etc.) |
| **Kumiho Get Dependencies** | `Kumiho/Graph` | Query dependency graph |

### kref:// URI Format

Both ComfyUI nodes and the browser use the same kref:// URI scheme:

```
kref://project/space/item.kind?r=revision&a=artifact

Examples:
- kref://myproject/characters/hero.model
- kref://myproject/textures/skin.texture?r=latest
- kref://myproject/renders/final.image?r=5
- kref://myproject/workflows/processing.workflow?r=published
```

### Browser ↔ ComfyUI Workflow

```
┌─────────────────────┐                    ┌─────────────────────┐
│   Kumiho Browser    │                    │      ComfyUI        │
│   (Flutter Desktop) │                    │   (Python Nodes)    │
└──────────┬──────────┘                    └──────────┬──────────┘
           │                                          │
           │  1. Browse & select assets               │
           │  2. Copy kref:// URI                     │
           │                                          │
           │ ─────────────────────────────────────▶   │
           │                                          │
           │                    3. Paste in Kumiho Load Asset
           │                    4. Generate new content
           │                    5. Save with Kumiho Save Image
           │                                          │
           │ ◀─────────────────────────────────────   │
           │                                          │
           │  6. Auto-refresh shows new assets        │
           │  7. View lineage graph (DERIVED_FROM)    │
           │                                          │
           ▼                                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Kumiho Cloud (gRPC)                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Items     │  │  Revisions  │  │   Edges     │              │
│  │  (Assets)   │  │  (Versions) │  │  (Lineage)  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

### Automatic Lineage Tracking

When ComfyUI saves an image via `Kumiho Save Image` with `source_krefs`:

```python
# ComfyUI workflow creates DERIVED_FROM edges automatically
[Kumiho Load Asset] ──────▶ [Processing] ──────▶ [Kumiho Save Image]
     │                                                   │
     │ kref://project/inputs/photo.image                 │
     │                                                   │
     └───────────── source_krefs ────────────────────────┘
                          │
                          ▼
              Creates: DERIVED_FROM edge
              Source: new_output.image
              Target: photo.image
```

The browser's **Lineage Graph** view displays these relationships visually.

### Browser Features for ComfyUI Users

| Feature | Browser Capability |
|---------|-------------------|
| **Asset Discovery** | Search/filter items by model, LoRA, prompt, seed |
| **Version History** | Browse all revisions of an item |
| **Lineage Graph** | Visualize what generated what |
| **Metadata View** | See full ComfyUI workflow parameters |
| **Quick Copy** | Copy kref:// URI for ComfyUI nodes |
| **Batch Operations** | Tag/organize multiple outputs |
| **Share Cards** | Generate social media share images |

### Metadata from ComfyUI Workflows

The browser displays ComfyUI-specific metadata stored by save nodes:

```dart
// Detail panel shows:
class ComfyUIMetadata {
  String? checkpoint;      // Stable Diffusion model
  List<String> loras;      // LoRA models used
  String? prompt;          // Positive prompt
  String? negativePrompt;  // Negative prompt
  int? seed;               // Generation seed
  int? steps;              // Sampling steps
  double? cfg;             // CFG scale
  String? sampler;         // Sampler name
  String? scheduler;       // Scheduler type
  String? resolution;      // Output resolution
  String? workflowJson;    // Full workflow (expandable)
}
```

### Authentication Difference

| Client | Auth Method | Notes |
|--------|-------------|-------|
| **Browser** | Firebase Popup | Google/GitHub/Email login |
| **ComfyUI** | API Key or CLI | `kumiho-auth login` creates `~/.kumiho/authentication.json` |

ComfyUI users authenticate via CLI:
```bash
pip install kumiho-cli
kumiho-auth login      # Opens browser for OAuth
kumiho-auth status     # Verify authentication
```

The browser uses Firebase popup directly for a more integrated desktop experience.

### Future: Direct Browser-ComfyUI Communication

Planned features:
1. **Launch Workflow**: Open ComfyUI with selected asset pre-loaded
2. **Workflow Templates**: Store and apply workflow presets
3. **Live Preview**: Watch ComfyUI output folder for real-time updates
4. **Batch Generation**: Queue multiple generations from browser

---

## 📚 11. References

- [PRD.md](./PRD.md) - Product Requirements Document
- [kumiho-dart SDK](../kumiho-dart/) - Dart client library
- [kumiho-python SDK](https://pypi.org/project/kumiho/) - Python SDK (v0.4.2+)
- [kumiho-comfyui](../kumiho-comfyui/) - ComfyUI custom nodes
- [Kumiho Server](../kumiho-server/) - Rust gRPC backend
- [Neo4j Graph Model](./graph-schema.md) - Data model documentation
- [Kumiho Docs](https://docs.kumiho.io) - Full API documentation

---

*Last Updated: December 5, 2025*
