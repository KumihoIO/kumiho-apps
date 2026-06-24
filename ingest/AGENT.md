# AGENT.md — Kumiho Ingest Studio (Tauri Desktop) + Storyboard Studio (Local Python SDK)

## Mission
Build a locally launched desktop application for **Kumiho Ingest Studio** with an optional **Storyboard Studio** module.

Key properties:
- Desktop shell: **Tauri**. v2
- UI: **Next.js** (or equivalent web UI) packaged inside Tauri.
- Users authenticate via **Firebase Authentication**.
- The app runs **Kumiho operations locally via the `kumiho` Python SDK** (installed from PyPI using `pip install kumiho`).
- The app communicates directly with Kumiho services through the Python SDK (no FastAPI BFF).

## Non-Goals
- Do not use or expand the FastAPI BFF.
- Do not implement server-side image slicing (client-side slicing is the default).
- Do not embed privileged backend credentials in the app binary.
- Do not require users to manually install the Python SDK (the app must install it itself).

---

## High-Level Architecture

### Runtime Components
- **Tauri (Rust)**: Desktop container, secure IPC bridge, file system access.
- **UI (Web)**: Local UI rendered within Tauri (Next.js exported build or a static SPA).
- **Python Runtime (Local)**: A local Python environment (venv) managed by the app.
- **Python Worker**: A long-running Python process launched by Tauri that:
  - imports the `kumiho` SDK
  - performs Kumiho entity operations (projects/spaces/items/revisions/bundles)
  - registers local files as Kumiho **artifacts** (BYO storage; no file uploads)
  - returns results to the UI via Tauri commands/events

### SDK Reality Check (Current `kumiho-python`)
- **BYO storage**: `revision.create_artifact(name, location)` stores a file reference only; it does not upload bytes to Kumiho.
- **Discovery bootstrap**: `kumiho.auto_configure_from_discovery()` assumes CLI-cached credentials; for this desktop app, use `kumiho.connect(token=<firebase_id_token>, use_discovery=True, enable_auto_login=False)`.
- **Bundles**: `bundle` is a reserved kind; create via `project.create_bundle()` / `space.create_bundle()`. Bundle membership changes create bundle revisions for audit, while bundle *item metadata* can be updated independently.

### Why Local Python Worker
- Minimizes infra usage (no BFF).
- Keeps heavy I/O and SDK logic local.
- Enables simple evolution of ingest flows by updating Python worker code and `kumiho` SDK version.

---

## Authentication

### Firebase Auth (Client)
1. User signs in using Firebase Auth in the desktop UI.
2. UI obtains Firebase **ID token** (JWT).
3. UI passes the ID token to the Python worker for use with the `kumiho` SDK (Kumiho expects an `Authorization: Bearer <JWT>` token).

### Token Handling Rules
- Do not store tokens in plain text on disk.
- Keep tokens in memory where possible.
- If persistence is required, store only refresh/session material through Firebase’s supported persistence and/or OS keychain mechanisms available to Tauri (prefer keychain).

### Token Refresh
- UI is responsible for getting a fresh ID token from Firebase (`getIdToken()`).
- Python worker should accept token updates and use the latest token for API calls.

### Worker Bootstrap (No CLI Credentials)
The current Python SDK’s `auto_configure_from_discovery()` flow is designed around CLI-cached credentials (`~/.kumiho/kumiho_authentication.json`). This desktop app should **not** rely on that file.

Recommended worker behavior after `set_auth_token(token)`:
- Call `kumiho.connect(token=token, use_discovery=True, enable_auto_login=False)`.
- Optionally pass `tenant_hint` if your UI has a tenant selector.
- Avoid writing token files; keep the token in memory.

---

## Python Environment Management (Required)

### Requirement
The app must install the Kumiho SDK from PyPI:
- `pip install kumiho`

### Strategy (Recommended)
On first launch (or when missing), create and manage an app-local virtual environment:

- App data directory:
  - macOS: `~/Library/Application Support/<AppName>/`
  - Windows: `%APPDATA%\<AppName>\`
  - Linux: `~/.local/share/<AppName>/`

- Create venv:
- Create venv:
  - `python -m venv <app_data>/pyenv`

- Install SDK (cross-platform):
  - `<venv_python> -m pip install --upgrade pip`
  - `<venv_python> -m pip install kumiho`

Where `<venv_python>` is:
- macOS/Linux: `<app_data>/pyenv/bin/python`
- Windows: `%APPDATA%\<AppName>\pyenv\Scripts\python.exe`

### SDK Config Isolation (Recommended)
By default the SDK uses `~/.kumiho/` for discovery cache and CLI credentials. For a desktop app, keep SDK state inside app data:

- Set `KUMIHO_CONFIG_DIR=<app_data>/kumiho` for the worker process.
- Set `KUMIHO_DISCOVERY_CACHE_FILE=<app_data>/kumiho/discovery-cache.json`.

This keeps discovery routing cache out of the user’s home dir and makes “reset app” behavior predictable.

### Python Distribution Options
The agent must implement **one** of the following (choose the most practical for the repo constraints):

**Option A — Bundle Python with the app (preferred for UX)**
- Ship a minimal Python distribution with Tauri (platform-specific).
- Use it to create the venv and install `kumiho`.
- Pros: no external dependency.
- Cons: increases binary size; requires packaging work.

**Option B — Use system Python if available (fallback)**
- Detect `python3`/`python` on PATH.
- If unavailable, show a guided installer prompt or fail gracefully.
- Pros: smallest app footprint.
- Cons: less reliable across users.

### Versioning and Upgrades
- Keep a file in app data: `<app_data>/pyenv/manifest.json` including:
  - installed `kumiho` version
  - last update timestamp
- Add a UI control: “Update SDK” which runs:
  - `pip install --upgrade kumiho`

---

## Storyboard Studio (Contact-Sheet) — Core Workflow

### User Experience
1. Upload a single storyboard **contact-sheet** image (PNG/JPG) containing a grid.
2. Select grid size: **3×3 / 4×4 / 5×5**.
3. Adjust slicing parameters (MVP):
   - outer margin (px)
   - gutter (px)
   - optional x/y offset nudge
4. Preview all slices (thumbnails + bounding rectangles).
5. Click **Cut & Ingest**:
   - client slices locally (Canvas)
  - client sends panel file paths to Python worker (preferred)
  - Python worker creates items/revisions and registers panel files as Kumiho artifacts (`revision.create_artifact(...)`)
6. Reorder panels freely (drag/drop).
7. Save:
  - Python worker updates/creates a **Bundle** representing the storyboard sequence.

### Slicing (Client-side, Deterministic)
- Compute bounding boxes by:
  - image dimensions
  - rows/cols
  - margin/gutter
- Provide a live preview and allow tuning.

---

## Kumiho Data Contract (Bundle Sequence Metadata)

Store ordering and optional shot metadata as **bundle item metadata**.

Important SDK constraint: in `kumiho-python`, metadata is a `Dict[str, str]` (string → string). If you want structured data, store it as a JSON string value.

Recommended shape:
- `kumiho_storyboard_sequence_version`: string (e.g. `"1"`)
- `kumiho_storyboard_sequence_v1`: JSON string containing the versioned structure below

```json
{
  "sequence_version": 1,
  "source": {
    "type": "contact_sheet",
    "rows": 4,
    "cols": 4,
    "margin_px": 16,
    "gutter_px": 8,
    "image_width": 4096,
    "image_height": 4096
  },
  "sequence": [
    {
      "index": 0,
      "panel_ref": "kref://project/space/panel.image?r=1",
      "shot_meta": {
        "angle": null,
        "lens": null,
        "motion": null,
        "duration_ms": null,
        "transition": null,
        "notes": null
      }
    }
  ]
}
```

MVP may omit `shot_meta`. The schema must remain forward-compatible by versioning.

---

## IPC Between UI and Python Worker

### Tauri Command Surface (Rust)

Expose a minimal command set from Tauri to UI:

* `ensure_python_env()`

  * creates venv if missing
  * runs `pip install kumiho` if missing
* `start_python_worker()`

  * launches worker process (kept alive)
* `set_auth_token(token: string)`

  * updates token in worker
* `ingest_files(payload)`

  * general ingest operations
* `storyboard_ingest(payload)`

  * contact-sheet slicing results (panel blobs/files + metadata) → ingest
* `bundle_update_sequence(payload)`

  * reorder/save bundle item metadata (string-only map; store JSON as a string)

### Worker Transport

Use one of:

* stdin/stdout JSON-RPC (simple, robust)
* local loopback HTTP server (avoid unless necessary)
* Tauri plugin process communication (acceptable if available)

Prefer JSON-RPC over stdio to keep dependencies minimal.

---

## Implementation Plan

### Phase 0 — Repo Setup

* Add Tauri app under `/apps/desktop-tauri` (or similar).
* Add web UI under `/apps/ingest-studio-ui`.
* Ensure dev mode runs both and packages the UI into Tauri.

Deliverables:

* `pnpm dev` runs UI
* `cargo tauri dev` runs desktop shell with UI loaded

### Phase 1 — Python Environment Bootstrap

* Implement `ensure_python_env()`:

  * locate Python (bundled preferred; system fallback)
  * create venv in app data
  * run `pip install kumiho` from PyPI
* Implement `start_python_worker()` and health check.

Deliverables:

* First launch installs SDK automatically.
* Worker can import `kumiho` successfully.

### Phase 2 — Firebase Auth Gate

* Implement login screen using Firebase client SDK.
* After login, call `set_auth_token()` with ID token.
* Add token refresh strategy (refresh and update worker).

Deliverables:

* User can login and reach `/ingest`.
* Worker receives updated tokens without restart.

### Phase 3 — General Ingest MVP (via Python SDK)

* UI: drag/drop file list, previews
* UI → worker: send local file paths or file bytes (prefer paths)
* Worker: create items/revisions and register file paths as artifacts using `kumiho` SDK (BYO storage)
* UI: show ingest results, created refs, errors

Deliverables:

* Register 1+ images successfully using SDK only.

### Phase 4 — Storyboard Studio (Contact-Sheet)

* UI: contact-sheet upload + slicing preview + adjustable margin/gutter
* UI: produce N×N blobs (and thumbnails) or save temporary panel files to app temp dir
* UI → worker: provide panel files + storyboard metadata
* Worker:

  * create panel items + revisions, then create artifacts pointing at the saved panel files
  * create/update bundle via `project.create_bundle(...)` / `space.create_bundle(...)`
  * store ordering under bundle item metadata (JSON string as described above)
* UI: reorder panels, save updates bundle sequence

Deliverables:

* 3×3 / 4×4 / 5×5 supported
* Bundle created with stable sequence schema
* Reorder updates bundle metadata (no re-upload)

### Phase 5 — Hardening

* Tauri security defaults:

  * strict allowlist
  * no remote navigation unless explicitly needed
* Robust error handling:

  * retries for pip install
  * partial ingest recovery
  * clear user messages (auth expired, network issues)
* Performance:

  * generate thumbnails efficiently
  * avoid copying large bytes through IPC when paths suffice

---

## Acceptance Criteria

* Desktop app launches locally with Tauri.
* Login required via Firebase Auth.
* App automatically installs Python SDK from PyPI:

  * `pip install kumiho`
* No FastAPI BFF is used.
* General ingest works through Python worker + `kumiho` SDK.
* Storyboard Studio:

  * supports 3×3 / 4×4 / 5×5 contact-sheet
  * slicing preview with adjustable margin/gutter
  * registers panels into Kumiho via SDK (artifacts are file references; no uploads)
  * creates/updates a bundle with versioned `sequence[]` metadata
  * drag/drop reorder updates bundle metadata on save
* No privileged backend secrets are embedded in the app.

---

## Coding Standards

* TypeScript for UI.
* Rust for Tauri commands kept minimal and auditable.
* Python worker code structured as:

  * `worker/main.py` (entry)
  * `worker/kumiho_client.py` (SDK adapter)
  * `worker/storyboard.py` (ingest + bundle sequencing)
* Centralize schema types in one place (UI + worker must match).

---

## Testing

* Unit tests (UI): slicing math and bounding boxes.
* Unit tests (Python): bundle metadata generation and ordering.
* Integration smoke test:

  * login → ensure SDK installed → ingest file → storyboard ingest → reorder → save bundle update

---

## Dev Commands (Fill in to Match Repo)

* Install deps: `pnpm i`
* Run UI: `pnpm -C apps/ingest-studio-ui dev`
* Run Tauri: `cargo tauri dev` (from `/apps/desktop-tauri`)
* Package: `cargo tauri build`

---

## Notes / Constraints

* The agent must choose a Python distribution strategy (bundled preferred, system fallback acceptable).
* Keep all network operations through the `kumiho` SDK; do not reintroduce BFF dependencies.
* Keep bundle metadata schema versioned to allow future shot metadata expansion.

