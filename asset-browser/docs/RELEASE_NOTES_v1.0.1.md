# 🦊 Kumiho Asset Browser v1.0.1

**Performance + Stability Update** · January 7, 2026

This release focuses on **Windows responsiveness** when browsing large grids (items with 100+ revisions) and when using **viewer “playback mode”** (Space + arrow navigation).

---

## ⚡ Highlights

- Viewer mode (Space) stays responsive even while the grid is expanding large items.
- Reduced main-isolate stalls during artifact expansion for high-revision items.
- Fixed a crash caused by deferred background expansion after a tile was disposed.

---

## 🖼️ Viewer (Playback Mode)

- Prevented background “details expansion” work from running while the fullscreen viewer is open.
- Keeps Space-to-viewer open fast and avoids multi-second UI lock-ups during navigation.

---

## 🧱 Grid & Artifact Expansion

- Kept behavior: the grid still expands and shows **all artifacts**.
- Reduced synchronous work during page expansion to avoid long stalls when adding the next batch of clips.
- Avoided unnecessary list copies during incremental updates when no filters/search are active.

---

## 🛠️ Fixes

- Fixed: `Bad state: Cannot use "ref" after the widget was disposed.`
- Reduced incidental work from bundle items in the main browsing list.

---

**Full Changelog**

(Attach the GitHub compare link for this tag/version here.)
