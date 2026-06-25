<div align="center">

# Kumiho Apps

**Open-source client applications for the [Kumiho](https://kumiho.io) platform** — a graph-native creative & AI asset management system.

Each app is a thin client over the open-source Kumiho SDKs. Your files never leave your storage (bring-your-own-storage), and the heavy lifting stays in your own Kumiho server — [Kumiho Cloud](https://kumiho.io) or a self-hosted **Community Edition**.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Windows](https://img.shields.io/badge/Windows-0078D6?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)
![Web](https://img.shields.io/badge/Web-4285F4?logo=googlechrome&logoColor=white)

</div>

---

## What's inside

This monorepo hosts three independent apps. Each has its own detailed README.

| | App | What it is | Platforms | Docs |
|:--:|-----|------------|-----------|:----:|
| 🗂️ | **Kumiho Browser** | Desktop browser for versioned assets & the human-audit UI for Cognitive Memory | Windows · macOS · Linux | [README »](kumiho-browser/README.md) |
| 📥 | **Kumiho Ingest Studio** | Desktop app that registers local files as Kumiho artifacts via a local Python worker | Windows · macOS · Linux | [README »](ingest/README.md) |
| 📝 | **Kumiho Blog** | Next.js reference web app for a blog built on the Kumiho API | Web | [README »](blog/README.md) |

---

### 🗂️ Kumiho Browser &nbsp;·&nbsp; `kumiho-browser/`

A Flutter desktop app for browsing and managing versioned creative assets — projects, spaces, items, revisions, and their dependencies — on the Kumiho platform over gRPC. It doubles as the human-facing **audit UI for the Kumiho Cognitive Memory graph**, letting you inspect agent-recorded conversations, decisions, and facts as items with full history and lineage.

- Browse and organize projects, spaces, and versioned items with revision history
- Visualize dependency graphs and lineage between assets
- Inspect agent memories, decisions, and facts with full provenance (Cognitive Memory audit)
- Connect to Kumiho Cloud **or** a self-hosted Community Edition server (plaintext gRPC on loopback)
- Bring-your-own-key social sharing, dark/light themes, built-in media playback

**Tech:** Flutter · Dart · gRPC · Riverpod · Firebase Auth &nbsp;—&nbsp; **[Full documentation »](kumiho-browser/README.md)**

---

### 📥 Kumiho Ingest Studio &nbsp;·&nbsp; `ingest/`

A Tauri 2 desktop app that registers local files as Kumiho artifacts — **bring-your-own storage, no byte uploads** — by driving the `kumiho` Python SDK in an app-managed local worker process. Includes an optional **Storyboard Studio** module that slices contact-sheet images into ordered panels client-side.

- Firebase-authenticated ingest of local files as Kumiho artifacts (no uploads)
- App-managed Python venv with an in-app "Update SDK" button
- Local Python worker driving the kumiho SDK over stdio JSON-RPC
- Browse projects/spaces/items and optionally move files into a structured path
- Storyboard Studio: client-side contact-sheet slicing into ordered, sequenced artifacts
- Built-in Tauri auto-updater (GitHub Releases)

**Tech:** Tauri 2 · Rust · React · TypeScript · Vite · Python &nbsp;—&nbsp; **[Full documentation »](ingest/README.md)**

---

### 📝 Kumiho Blog &nbsp;·&nbsp; `blog/`

A Next.js 15 reference web app showing how to build a blog on top of the Kumiho API (proxied via a Kumiho FastAPI backend). Posts are stored in Kumiho's hierarchical Project / Space / Item / Revision model with Firebase authentication.

- Create, edit, publish, list, and read Markdown posts
- Admin dashboard for posts, categories, and settings
- Next.js API routes proxying to the Kumiho FastAPI backend
- Firebase auth with multi-tenant and anonymous access
- Tailwind CSS responsive UI with dark mode

**Tech:** Next.js 15 · React 19 · TypeScript · Tailwind CSS · Firebase Auth &nbsp;—&nbsp; **[Full documentation »](blog/README.md)**

---

## Install

The desktop apps ship installers for Windows, macOS, and Linux on the [Releases](https://github.com/KumihoIO/kumiho-apps/releases) page. To grab the latest with one line:

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.ps1 | iex   # Kumiho Browser
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.ps1 | iex    # Ingest Studio
```

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.sh | sh   # Kumiho Browser
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.sh | sh    # Ingest Studio
```

Building from source and the release process are documented in **[RELEASING.md](RELEASING.md)**.

---

## Repository layout

```
kumiho-apps/
├── kumiho-browser/   # Kumiho Browser  — Flutter desktop
├── ingest/          # Kumiho Ingest Studio — Tauri desktop + Python worker
├── blog/            # Kumiho Blog — Next.js web
├── install/         # one-line installer scripts
├── RELEASING.md     # release pipeline + signing/update setup
└── .github/         # CI: per-app build & release workflows
```

---

## License

[MIT](LICENSE) © Kumiho Clouds. The Kumiho server is distributed separately under its own terms.
