#!/usr/bin/env python3
"""Regenerate app icons for Kumiho Asset Browser.

Outputs:
- Common PNG set: assets/icons/common/icon_{size}x{size}.png
- Windows ICO: windows/runner/resources/app_icon.ico
- macOS AppIcon set: macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png

Source:
- assets/images/kumiho_symbol_736.png (preferred)

Usage:
  python scripts/regenerate_icons.py
  python scripts/regenerate_icons.py --src assets/images/kumiho_symbol_736.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def _repo_root_from_script(script_path: Path) -> Path:
    # scripts/regenerate_icons.py -> kumiho-asset-browser/
    return script_path.resolve().parents[1]


def _load_source_image(src_path: Path) -> Image.Image:
    image = Image.open(src_path).convert("RGBA")
    width, height = image.size

    if width != height:
        min_side = min(width, height)
        left = (width - min_side) // 2
        top = (height - min_side) // 2
        image = image.crop((left, top, left + min_side, top + min_side))

    return image


def _resize_square(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def _write_png(image: Image.Image, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_path, format="PNG", optimize=True)


def _write_ico(image: Image.Image, out_path: Path, sizes: list[int]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # PIL writes multi-image ICO when `sizes` is provided.
    max_size = max(sizes)
    base = _resize_square(image, max_size)
    base.save(out_path, format="ICO", sizes=[(s, s) for s in sizes])


def _generate_common_icons(source: Image.Image, repo_root: Path) -> list[Path]:
    out_dir = repo_root / "assets" / "icons" / "common"
    sizes = [16, 24, 32, 48, 64, 128, 256, 512]

    written: list[Path] = []
    for size in sizes:
        out_path = out_dir / f"icon_{size}x{size}.png"
        _write_png(_resize_square(source, size), out_path)
        written.append(out_path)
    return written


def _generate_macos_icons(source: Image.Image, repo_root: Path) -> list[Path]:
    out_dir = (
        repo_root
        / "macos"
        / "Runner"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
    )

    # Matches existing Contents.json mapping.
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    written: list[Path] = []
    for size in sizes:
        out_path = out_dir / f"app_icon_{size}.png"
        _write_png(_resize_square(source, size), out_path)
        written.append(out_path)
    return written


def _generate_windows_icon(source: Image.Image, repo_root: Path) -> list[Path]:
    out_path = repo_root / "windows" / "runner" / "resources" / "app_icon.ico"

    # Common Windows icon sizes. 256 is the important one for modern Windows.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    _write_ico(source, out_path, sizes)
    return [out_path]


def main() -> int:
    script_path = Path(__file__)
    repo_root = _repo_root_from_script(script_path)

    parser = argparse.ArgumentParser(description="Regenerate app icons")
    parser.add_argument(
        "--src",
        type=Path,
        default=repo_root / "assets" / "images" / "kumiho_symbol_736.png",
        help="Source image (square PNG recommended)",
    )
    args = parser.parse_args()

    src_path: Path = args.src
    if not src_path.is_absolute():
        src_path = (repo_root / src_path).resolve()

    if not src_path.exists():
        raise SystemExit(f"Source image not found: {src_path}")

    source = _load_source_image(src_path)

    written: list[Path] = []
    written += _generate_common_icons(source, repo_root)
    written += _generate_macos_icons(source, repo_root)
    written += _generate_windows_icon(source, repo_root)

    rel_written = [str(p.relative_to(repo_root)) for p in written]
    print("Wrote:")
    for p in rel_written:
        print(f"  - {p}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
