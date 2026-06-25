# Kumiho Browser

A modern desktop application for browsing and managing creative assets using the [Kumiho Cloud](https://kumiho.io) platform.

## Features

- 📁 **Project Management** - Create, browse, and organize projects
- 🗂️ **Space Navigation** - Hierarchical folder structure for assets
- 📦 **Item Browser** - View and manage versioned assets (models, textures, workflows, etc.)
- 🔄 **Revision History** - Track all versions of your assets
- 🔗 **Dependency Graph** - Visualize relationships between assets
- 🧠 **Cognitive Memory Audit** - Browse recorded AI agent memories as versioned items and trace reasoning dependencies
- 🎨 **Modern UI** - Fluent Design System for a native Windows experience
- 🌙 **Dark/Light Themes** - Choose your preferred appearance
- 🔐 **Secure Authentication** - Firebase-based authentication

## Human-auditable AI memory (Cognitive Memory)

Kumiho Browser (`kumiho-browser`) is also the human-facing UI for the Kumiho Cognitive Memory graph. When agents store conversations, tool runs, and consolidated decisions/facts as Items and Revisions, you can inspect them in the same interface as any other asset — with full history, provenance, and dependency/lineage visualization for audit and troubleshooting.

## Release Notes

- [docs/RELEASE_NOTES_v1.0.1.md](docs/RELEASE_NOTES_v1.0.1.md) (latest)
- [docs/RELEASE_NOTES_v1.0.0.md](docs/RELEASE_NOTES_v1.0.0.md)

## Screenshots

*Coming soon*

## Install

Prebuilt installers for Windows, macOS, and Linux are published on the
[Releases](https://github.com/KumihoIO/kumiho-apps/releases) page. To grab the
latest with one line:

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.ps1 | iex
```

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.sh | sh
```

The script downloads the right artifact for your OS (`.exe` on Windows, `.dmg`
on macOS, `.deb`/`.rpm`/`.AppImage` on Linux) from the latest release.

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.5.0
- Windows 10/11, macOS 10.14+, or Linux

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/kumihoclouds/kumiho-asset-browser.git
   cd kumiho-asset-browser
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the application:
   ```bash
   flutter run -d windows  # or macos, linux
   ```

### Environment Configuration

The application uses `--dart-define` for environment configuration:

| Environment | Control Plane URL | Command |
|-------------|-------------------|---------|
| Development | `http://localhost:3000` | `flutter run -d windows` (default) |
| Production | `https://control.kumiho.cloud` | `flutter run -d windows --dart-define=ENVIRONMENT=production` |

These settings apply to **Kumiho Cloud** only. A self-hosted Community Edition
server needs **no control plane URL** — see
[Connecting to a self-hosted server](#connecting-to-a-self-hosted-server-community-edition)
below.

**Available flags:**
- `ENVIRONMENT` - Set to `development` or `production`
- `CONTROL_PLANE_URL` - Override the control plane URL directly (Kumiho Cloud)
- `DATA_PLANE_URL` - Override the default data plane URL

### Connecting to a self-hosted server (Community Edition)

Kumiho Browser can connect directly to a self-hosted [Kumiho Server
Community Edition (CE)](https://github.com/KumihoIO/kumiho-server-community)
instance — no Firebase sign-in or control-plane discovery required.

CE serves plaintext gRPC on loopback (default `127.0.0.1:9190`) and does not
require authentication. To connect:

1. Start the CE server (see the [kumiho-server-community](https://github.com/KumihoIO/kumiho-server-community) docs for Neo4j setup):
   ```powershell
   $env:KUMIHO_DEPLOYMENT_MODE = "self_hosted_ce"
   $env:KUMIHO_NEO4J_PORT = "7687"
   $env:KUMIHO_DB_NAME = "neo4j"
   $env:KUMIHO_DB_USER = "neo4j"
   $env:KUMIHO_DB_PASS = "your-local-password"
   cargo run --bin kumiho_server
   ```
2. In Kumiho Browser, open **Settings → Account → Local / Self-hosted Server**,
   toggle **Use local server** on, and confirm the host/port (defaults to
   `127.0.0.1` / `9190`, TLS off).

Enabling local mode bypasses the cloud auth/discovery flow entirely; the
existing cloud sign-in flow is unaffected when the toggle is off.

You can verify connectivity outside the app with the bundled probe:

```bash
dart run tool/ce_probe.dart            # defaults to 127.0.0.1 9190
dart run tool/ce_probe.dart <host> <port>
```

### Social sharing (bring your own API keys)

The app ships with **no bundled social media API keys**. To share assets to
X/Twitter, register your own app in the [X Developer Portal](https://developer.twitter.com/),
set its OAuth callback URL to `http://localhost:8642/callback`, then enter your
API key and secret under **Settings → Sharing → Social App Credentials**. The
credentials are stored locally on your device only.

### Building for Production

```bash
# Windows - Development (localhost)
.\scripts\build_dev.ps1

# Windows - Production (control.kumiho.cloud)
.\scripts\build_production.ps1

# Or manually:
flutter build windows --release --dart-define=ENVIRONMENT=production

# macOS
flutter build macos --release --dart-define=ENVIRONMENT=production

# Linux
flutter build linux --release --dart-define=ENVIRONMENT=production
```

### Regenerating App Icons

Icons are generated from `assets/images/kumiho_symbol_736.png`.

```bash
python -m pip install pillow
python scripts/regenerate_icons.py
```

## Project Structure

```
lib/
├── app/                    # Application configuration
│   ├── app.dart           # Main app widget
│   └── router.dart        # Route configuration
├── core/                   # Core functionality
│   ├── constants/         # App constants
│   ├── services/          # Services (Kumiho client, logger)
│   └── theme/             # Theme configuration
└── features/              # Feature modules
    ├── auth/              # Authentication
    ├── home/              # Dashboard/Home
    ├── projects/          # Project management
    ├── settings/          # App settings
    └── shell/             # Navigation shell
```

## Architecture

This application follows a clean architecture pattern with:

- **Riverpod** for state management
- **GoRouter** for navigation
- **Fluent UI** for Windows-style UI components
- **Kumiho SDK** for backend communication

## Dependencies

### Kumiho SDK

The application uses the [Kumiho Dart SDK](https://github.com/KumihoIO/kumiho-SDKs/tree/main/dart) (the `dart/` package in the `KumihoIO/kumiho-SDKs` monorepo) for communicating with the Kumiho backend. The SDK provides:

- gRPC-based communication
- Project, Space, and Item management
- Revision and artifact tracking
- Dependency graph operations

## Configuration

### Server Connection

By default, the application connects to `api.kumiho.cloud:443`. You can change this in Settings or by setting environment variables:

- `KUMIHO_HOST` - Server hostname
- `KUMIHO_PORT` - Server port
- `KUMIHO_AUTH_TOKEN` - Authentication token

### Authentication

The application supports multiple authentication methods:

1. **Email/Password** - Traditional login
2. **Token-based** - Use existing Kumiho CLI credentials
3. **Offline Mode** - Browse without authentication (limited features)

## Development

### Running Tests

```bash
flutter test
```

### Generating Code

For Riverpod generators:

```bash
dart run build_runner build
```

### Linting

```bash
flutter analyze
```

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a PR.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Projects

- [kumiho-dart](../kumiho-dart) - Dart SDK for Kumiho Cloud
- [kumiho-python](../kumiho-python) - Python SDK for Kumiho Cloud
- [kumiho-cpp](../kumiho-cpp) - C++ SDK for Kumiho Cloud
- [kumiho-comfyui](../kumiho-comfyui) - ComfyUI integration

## Support

- 📖 [Documentation](https://docs.kumiho.io)
- 💬 [Discord Community](https://discord.gg/Utp2P8G69P)
- 🐛 [Issue Tracker](https://github.com/kumihoclouds/kumiho-asset-browser/issues)
