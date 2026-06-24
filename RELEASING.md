# Releasing the Kumiho apps

The monorepo builds and releases each desktop app independently via GitHub
Actions. A release is cut by pushing a per-app version tag; the workflow builds
Windows / macOS / Linux installers and publishes them as a GitHub Release on
this repository.

| App | Workflow | Tag pattern | Platforms |
|-----|----------|-------------|-----------|
| Kumiho Browser (`asset-browser`) | `.github/workflows/asset-browser-release.yml` | `asset-browser-v1.2.3` | Windows `.exe`, macOS `.dmg`/`.zip`, Linux `.deb`/`.rpm` |
| Kumiho Ingest Studio (`ingest-studio`) | `.github/workflows/ingest-studio-release.yml` | `ingest-studio-v0.1.0` | Windows NSIS `.exe`/`.msi`, macOS `.dmg`, Linux `.AppImage`/`.deb` |

## Cut a release

```bash
# Kumiho Browser  (version comes from the tag)
git tag asset-browser-v1.2.3 && git push origin asset-browser-v1.2.3

# Ingest Studio   (keep src-tauri/tauri.conf.json + Cargo.toml version in sync)
git tag ingest-studio-v0.1.0 && git push origin ingest-studio-v0.1.0
```

You can also run either workflow manually from the Actions tab
(`workflow_dispatch`) to produce unsigned artifacts without creating a release.

## One-line install

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.ps1 | iex
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.ps1 | iex
```

macOS / Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.sh | sh
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.sh | sh
```

Each script finds the latest release whose tag matches the app prefix and
downloads the right asset for the OS.

## Signing & auto-update (optional, via repo secrets)

Builds work **unsigned** out of the box; the signing/notarization steps activate
only when the matching secret is present.

### Windows code signing (both apps)
Add `WINDOWS_CERT_BASE64` (base64 of your `.pfx`) and `WINDOWS_CERT_PASSWORD`.
Installers are then Authenticode-signed (removes the SmartScreen "unknown
publisher" warning).

### macOS signing + notarization (asset-browser)
Add `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`,
`APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` (see `asset-browser/docs/apple_certificate.md`).

### asset-browser auto-update
- **Windows / Linux:** the app checks this repo's GitHub Releases at runtime
  (`UpdateService`, owner `KumihoIO`, repo `kumiho-apps`). No setup needed.
- **macOS (Sparkle):** generate a key with Sparkle's `generate_keys`, put the
  public key in `asset-browser/macos/Runner/Configs/AppInfo.xcconfig`
  (`SPARKLE_PUBLIC_ED25519_KEY`), and add `SPARKLE_ED25519_PRIVATE_KEY` as a
  secret. The feed is served from `releases/latest/download/appcast.xml`.

### ingest-studio auto-update (Tauri updater)
Wired but dormant. To enable:
1. `npx @tauri-apps/cli signer generate` (do this locally; keep the private key safe).
2. Put the **public** key in `ingest/apps/desktop-tauri/src-tauri/tauri.conf.json`
   (`plugins.updater.pubkey`) and set `bundle.createUpdaterArtifacts` to `true`.
3. Add `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` secrets.

The workflow then signs the update artifacts and publishes `latest.json`; the app
checks `releases/latest/download/latest.json` on startup.

### ingest-studio Firebase config
The UI reads public `VITE_FIREBASE_*` values at build time. Add them as secrets
(`VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_PROJECT_ID`,
`VITE_FIREBASE_APP_ID`, and optionally `VITE_FIREBASE_STORAGE_BUCKET`,
`VITE_FIREBASE_MESSAGING_SENDER_ID`) so the released build can authenticate.
