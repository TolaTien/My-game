"""Optimize PNG game assets in-place to drastically reduce APK size and memory footprint
while preserving exact sprite-sheet cell dimensions and transparency.
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image


def optimize_png(path: Path, *, max_dim: int | None = None, quantize_colors: int = 256) -> tuple[int, int]:
    before = path.stat().st_size
    img = Image.open(path)

    # Optionally downscale oversized non-spritesheet backgrounds (maps / UI wallpapers)
    if max_dim is not None and max(img.size) > max_dim:
        ratio = max_dim / max(img.size)
        new_size = (max(1, int(round(img.width * ratio))), max(1, int(round(img.height * ratio))))
        img = img.resize(new_size, Image.Resampling.LANCZOS)

    # Convert to palette PNG (P mode) preserving full alpha via FASTOCTREE
    rgba = img.convert("RGBA")
    quantized = rgba.quantize(colors=quantize_colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)

    tmp = path.with_suffix(".opt.png")
    quantized.save(tmp, format="PNG", optimize=True)
    after = tmp.stat().st_size

    if after < before:
        tmp.replace(path)
        return before, after
    else:
        tmp.unlink(missing_ok=True)
        return before, before


def main() -> None:
    root = Path("assets/images")
    total_before = 0
    total_after = 0
    changed = 0

    for png in sorted(root.rglob("*.png")):
        rel = png.relative_to(root).as_posix()
        # Maps and UI wallpapers can safely be capped at 1280px wide (drawn stretched to viewport)
        if rel.startswith("maps/") or rel.startswith("ui/"):
            b, a = optimize_png(png, max_dim=1280, quantize_colors=256)
        else:
            # Sprite sheets & icons: NEVER change dimensions, only lossless/palette optimize
            b, a = optimize_png(png, max_dim=None, quantize_colors=256)
        total_before += b
        total_after += a
        if a < b:
            changed += 1

    print(
        f"Optimized {changed} PNGs: "
        f"{total_before / 1024 / 1024:.2f} MB -> {total_after / 1024 / 1024:.2f} MB "
        f"(saved {(total_before - total_after) / 1024 / 1024:.2f} MB)"
    )


if __name__ == "__main__":
    main()
