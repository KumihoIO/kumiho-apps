# Kumiho Ingest Studio

This folder contains the scaffolding for the Tauri desktop shell, web UI, and
local Python worker described in `kumiho-ingest/AGENT.md`.

## Install

Prebuilt installers for Windows, macOS, and Linux are published on the
[Releases](https://github.com/KumihoIO/kumiho-apps/releases) page. To grab the
latest with one line:

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.ps1 | iex
```

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.sh | sh
```

The script downloads the right artifact for your OS (NSIS `.exe`/`.msi` on
Windows, `.dmg` on macOS, `.AppImage`/`.deb` on Linux) from the latest release.

## Connecting to a self-hosted server (Community Edition)

Ingest Studio can connect directly to a self-hosted [Kumiho Server Community
Edition (CE)](https://github.com/KumihoIO/kumiho-server-community) instead of
Kumiho Cloud — no Firebase sign-in or control-plane discovery required.

In the app, open **Settings → Server**, tick **Use local server (CE)**, set the
address (defaults to `127.0.0.1:9190`), and click **Apply & restart worker**.
The Python worker then connects to the local CE endpoint over plaintext gRPC
with no auth token. Untick it to return to Kumiho Cloud.

## Structure

- `apps/ingest-studio-ui`: Vite + React UI.
- `apps/desktop-tauri`: Tauri shell with Rust command surface.
- `worker`: Local Python worker (stdio JSON-RPC scaffold).

## Dev Commands

- Install UI deps: `pnpm -C apps/ingest-studio-ui install`
- Run UI: `pnpm -C apps/ingest-studio-ui dev`
- Run UI tests: `pnpm -C apps/ingest-studio-ui test`
- Run Tauri: `cargo tauri dev` (from `apps/desktop-tauri`)
- Run worker tests: `python -m unittest discover -s worker/tests`

## SDK Updates

Use the "Update SDK" button in the desktop UI to run `pip install --upgrade kumiho`
inside the app-managed venv.

## Bundled Python Runtime

Drop the embedded Python distribution into `kumiho-ingest/python` as described
in `kumiho-ingest/python/README.md`. The app prefers the bundled runtime but
still upgrades the SDK from PyPI.

On macOS/Linux, you can run:

```
./scripts/fetch-python-standalone.sh
```

Set `PY_VERSION=3.13.11` or another version as needed.

## Smoke Test

The smoke test uses a Firebase ID token and real file paths:

```
set KUMIHO_FIREBASE_ID_TOKEN=your_token
python worker/smoke_test.py --project demo --space assets --file C:\path\to\file.png --panel C:\path\to\panel.png
```

## Firebase Config (UI)

Set these environment variables for the ingest studio UI (Vite):

- `VITE_FIREBASE_API_KEY`
- `VITE_FIREBASE_AUTH_DOMAIN`
- `VITE_FIREBASE_PROJECT_ID`
- `VITE_FIREBASE_APP_ID`
- `VITE_FIREBASE_STORAGE_BUCKET` (optional)
- `VITE_FIREBASE_MESSAGING_SENDER_ID` (optional)

## Auth Storage

The desktop app stores the most recent Firebase ID token in the OS keychain to
rehydrate the Python worker between launches. The UI still relies on Firebase
Auth for live sessions.

## Ingest Payload Notes

The worker only registers file paths as artifacts (BYO storage). If you want to
move files into a structured location, set:

- `move_files: true`
- `move_root: "<base directory>"`

The target path is composed from project/space/sub-space names and the original
file name.

## Storyboard Studio Notes

Storyboard ingest slices a contact-sheet image into panels, writes them to the
app cache, registers each panel path as an artifact, and updates bundle metadata
with the sequence order. Bundle metadata is stored as string keys:

- `kumiho_storyboard_sequence_version`
- `kumiho_storyboard_sequence_v1`
