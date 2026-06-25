# Changelog

All notable changes to **Kumiho Browser** are documented here. Releases are cut
by pushing an `asset-browser-v<version>` tag (see [RELEASING.md](../RELEASING.md)).

## [1.0.5] — 2026-06-25

### Fixed
- **OTIO playlist export now imports correctly in DaVinci Resolve** (and other
  NLEs). Three issues are corrected:
  - Use the `Clip.1` schema (single `media_reference`) instead of `Clip.2`.
    `Clip.2` moved the media to `media_references` + `active_media_reference_key`,
    so a `Clip.2` carrying a lone `media_reference` was parsed with **no media**
    and importers showed an empty timeline.
  - Emit each clip's `target_url` as a **plain native filesystem path** instead
    of a `file://` URI — Resolve resolves plain paths but treats `file://`
    literally, so the media couldn't be linked.
  - Add an `available_range` to each media reference (required to place still
    images) and a `global_start_time` to the timeline.

## [1.0.4] — 2026-06-25

### Added
- **Save a playlist to Kumiho** (playlist sidebar → right-click → *Save to
  Kumiho*): records the playlist as an `item(kind='playlist')` + revision, with
  a `PLAYLIST_MEMBER` edge pinning each member revision in order. (Bundles
  aggregate items, not revisions, so edges are used to pin exact revisions.)
- **Export a playlist as OpenTimelineIO** (*Export OTIO*): writes a `.otio`
  timeline and attaches it to the playlist revision as a `timeline.otio`
  artifact.

### Changed
- Renamed the app's folder `asset-browser/` → `kumiho-browser/`. The release tag
  prefix (`asset-browser-v*`) and the one-line install scripts are unchanged.

## [1.0.3] — 2026-06-25

### Added
- **Markdown/text artifact editor + viewer** — open an artifact by file type
  (markdown rendered, text/code editable, image preview, binary fallback). Edits
  write back to the local file on mutable (unpublished) revisions.
- **CREATE dialogs** for project / space / item / revision / artifact, with
  optional metadata (JSON or `key: value` lines).
- **Add a `thumbnail` artifact** to a mutable revision (list + grid), shown as
  the item preview.

### Fixed
- **Restored the dependency (lineage) graph in CE / self-hosted mode.** Its
  triggers were gated behind Firebase auth, so the graph was hidden when signed
  in to a self-hosted server. It now opens framed (auto-fit).

## [1.0.2] — 2026-06-24

### Fixed
- **Community Edition (self-hosted) mode now loads projects.** Resolved
  Riverpod build-phase errors that left the project list empty when connecting
  to a self-hosted server over plaintext loopback gRPC (no Firebase sign-in).
