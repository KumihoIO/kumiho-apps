# 🦊 Kumiho Asset Browser v1.0.0

**Initial Public Release** · December 11, 2025

Kumiho Asset Browser is a modern, cross-platform desktop application that turns creative outputs into **versioned, traceable assets** — without moving or uploading your files.

This release marks the first production-ready client for the Kumiho Cloud platform.

---

## ✨ Core Capabilities

### 🔗 ComfyUI Integration (Images & Videos)

- Native ComfyUI node for saving **images and videos**
- Automatic asset registration on save
- Prompt, model, workflow, and dependency metadata captured
- Outputs immediately appear in Kumiho Browser — no sync, no upload

---

### 📁 Asset & Revision Management

- Project-based asset organization with hierarchical spaces
- Assets represented as **Items** with full **Revision history**
- Compare iterations without relying on filenames or folders
- Author, timestamp, and metadata preserved per revision

---

### 🧬 Lineage & Dependency Tracking

- Interactive lineage graph visualization
- Clear dependency relationships between:
    - Outputs
    - Models
    - LoRAs
    - Workflows
- Designed for reproducibility and long-term traceability

---

## 🎬 Media Viewing & Playback

### Images

- High-performance image viewer
- Zoom and pan gesture support
- Revision-by-revision comparison workflow

### Video

- Embedded video player with thumbnail generation
- Fullscreen playback overlay
- Playlist support with persistent state

---

## 🎨 User Experience

- Native **Dark & Light theme** support
- Fluent Design System for Windows
- Responsive grid and list views
- Detail panel with revision and metadata inspection
- Lineage graph viewer for advanced users

---

## 🚀 Productivity & Sharing

- Keyboard shortcuts for power users
- Auto-refresh for near real-time updates
- Advanced search and filtering (prompt, model, seed, filename)
- Built-in asset sharing dialog
- Social sharing integrations (X available, others coming)

---

## 🔄 In-App Auto Updates

- Built-in automatic update system
- Seamless update delivery without reinstalling
- Ensures users are always on the latest stable version

---

## 🔐 Authentication & Security

- Secure Firebase-based authentication
- OAuth support for desktop environments
- Encrypted local token storage

---

## 🌐 Platform & Environment Support

### Supported Platforms

- Windows 10 / 11 ✅ (Primary Beta Platform)
- macOS ✅ (Tested)
- Linux ✅ (Tested)

### Environments

- Development
- Staging
- Production
    
    Switchable via `--dart-define` flags
    

---

## 📦 Installation

Download the latest installer for your platform

or build locally:

```bash
git clone https://github.com/kumihoclouds/kumiho-asset-browser.git
cd kumiho-asset-browser
flutter pub get
flutter run -d windows

```

---

## 🔧 Requirements

- Flutter SDK ≥ 3.5.0
- Kumiho Cloud account

---

## 📚 Documentation

- Getting Started: [https://docs.kumiho.io](https://docs.kumiho.io/)
- API Reference: [https://kumiho.cloud](https://kumiho.cloud/)

---

## 🧪 Beta Notes

- Windows is the primary supported platform during beta
- macOS and Linux builds are tested but will be formally supported post-beta
- Additional plugins (video editing, automation, n8n) are under active development

---

## 🙏 Acknowledgements

Built from real production pipeline experience and refined through hands-on iteration.

---

**Full Changelog**

https://github.com/kumihoclouds/kumiho-asset-browser/commits/v1.0.0