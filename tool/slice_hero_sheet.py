"""Slice and chroma-clean Gemini-generated hero sprite sheets into game-ready strips.

Usage:
    python tool/slice_hero_sheet.py <input_image> <output_dir> [--rows 3] [--cols 4] [--attack-row 2] [--chroma green|magenta]

Outputs:
    <output_dir>/idle.png      (1024x256 RGBA, 4 frames)
    <output_dir>/run.png       (1024x256 RGBA, 4 frames)
    <output_dir>/attack.png    (1024x256 RGBA, 4 frames)
    <output_dir>/portrait.png  (256x256 RGBA, frame 0 of idle)
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
from PIL import Image


def is_chroma(r: int, g: int, b: int, mode: str, strict: bool = False) -> bool:
    if mode == "green":
        if strict:
            return g > 150 and (g - max(r, b)) > 70
        return g > 110 and (g - max(r, b)) > 40
    else:  # magenta
        if strict:
            return r > 150 and b > 150 and (min(r, b) - g) > 70
        return r > 110 and b > 110 and (min(r, b) - g) > 40


def remove_chroma_background(img: Image.Image, mode: str = "green") -> Image.Image:
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    visited = [[False] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()

    # Seed flood fill from all 4 borders
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, a = px[x, y]
            if is_chroma(r, g, b, mode, strict=False):
                visited[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x]:
                r, g, b, a = px[x, y]
                if is_chroma(r, g, b, mode, strict=False):
                    visited[y][x] = True
                    q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, a = px[nx, ny]
                if is_chroma(r, g, b, mode, strict=False):
                    visited[ny][nx] = True
                    q.append((nx, ny))

    # Remove enclosed chroma pockets (between legs, cape, weapon handles)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and is_chroma(r, g, b, mode, strict=True):
                px[x, y] = (0, 0, 0, 0)

    # Despill / fringe cleanup on pixels adjacent to transparent pixels
    to_clear: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            has_trans_neighbor = False
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0:
                    has_trans_neighbor = True
                    break
            if has_trans_neighbor:
                if mode == "green":
                    spill = g - max(r, b)
                    if spill > 25:
                        to_clear.append((x, y))
                    elif spill > 5:
                        px[x, y] = (r, max(r, b), b, a)
                else:
                    spill = min(r, b) - g
                    if spill > 25:
                        to_clear.append((x, y))
                    elif spill > 5:
                        px[x, y] = (min(r, g + 5), g, min(b, g + 5), a)

    for x, y in to_clear:
        px[x, y] = (0, 0, 0, 0)

    # Remove small neighbor-sprite slivers clipped along the left/right borders
    comp_visited = [[False] * w for _ in range(h)]
    components: list[tuple[list[tuple[int, int]], bool]] = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0 and not comp_visited[y][x]:
                comp_q: deque[tuple[int, int]] = deque([(x, y)])
                comp_visited[y][x] = True
                pts: list[tuple[int, int]] = []
                touches_lr_edge = False
                while comp_q:
                    cx, cy = comp_q.popleft()
                    pts.append((cx, cy))
                    if cx <= 2 or cx >= w - 3:
                        touches_lr_edge = True
                    for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                        if 0 <= nx < w and 0 <= ny < h and not comp_visited[ny][nx] and px[nx, ny][3] > 0:
                            comp_visited[ny][nx] = True
                            comp_q.append((nx, ny))
                components.append((pts, touches_lr_edge))

    if components:
        max_area = max(len(c[0]) for c in components)
        for pts, touches_lr_edge in components:
            if touches_lr_edge and len(pts) < max_area * 0.12:
                for cx, cy in pts:
                    px[cx, cy] = (0, 0, 0, 0)

    return rgba


def normalize_cell(
    cell: Image.Image,
    target_size: int = 256,
    scale_factor: float | None = None,
    foot_y: int = 236,
) -> tuple[Image.Image, float]:
    bbox = cell.getbbox()
    if bbox is None:
        return Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0)), 1.0

    cropped = cell.crop(bbox)
    cw, ch = cropped.size

    if scale_factor is None:
        max_dim = max(cw, ch)
        scale_factor = (target_size * 0.78) / max_dim

    nw = max(1, int(round(cw * scale_factor)))
    nh = max(1, int(round(ch * scale_factor)))

    # Clamp so even wide attack arcs fit cleanly inside 256x256
    if nw > target_size - 8 or nh > target_size - 8:
        clamp_s = min((target_size - 8) / cw, (target_size - 8) / ch)
        nw = max(1, int(round(cw * clamp_s)))
        nh = max(1, int(round(ch * clamp_s)))

    resized = cropped.resize((nw, nh), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    paste_x = (target_size - nw) // 2
    paste_y = max(4, min(target_size - nh - 2, foot_y - nh))
    canvas.paste(resized, (paste_x, paste_y), resized)
    return canvas, scale_factor


def process_sheet(
    input_path: Path,
    output_dir: Path,
    rows: int = 3,
    cols: int = 4,
    idle_row: int = 0,
    run_row: int = 1,
    attack_row: int = 2,
    chroma: str = "green",
) -> None:
    img = Image.open(input_path)
    w, h = img.size
    cell_w = w / cols
    cell_h = h / rows

    output_dir.mkdir(parents=True, exist_ok=True)

    # First clean idle frames to compute a consistent base scale
    idle_raw = []
    for c in range(cols):
        box = (
            int(round(c * cell_w)),
            int(round(idle_row * cell_h)),
            int(round((c + 1) * cell_w)),
            int(round((idle_row + 1) * cell_h)),
        )
        idle_raw.append(remove_chroma_background(img.crop(box), chroma))

    idle_heights = [
        (fr.getbbox()[3] - fr.getbbox()[1]) for fr in idle_raw if fr.getbbox()
    ]
    base_h = max(idle_heights) if idle_heights else 200
    base_scale = (256 * 0.76) / base_h

    def build_strip(row_idx: int, precleaned: list[Image.Image] | None = None) -> list[Image.Image]:
        frames: list[Image.Image] = []
        for c in range(cols):
            if precleaned is not None:
                cleaned = precleaned[c]
            else:
                box = (
                    int(round(c * cell_w)),
                    int(round(row_idx * cell_h)),
                    int(round((c + 1) * cell_w)),
                    int(round((row_idx + 1) * cell_h)),
                )
                cleaned = remove_chroma_background(img.crop(box), chroma)
            norm, _ = normalize_cell(cleaned, target_size=256, scale_factor=base_scale)
            frames.append(norm)
        return frames

    def save_strip(frames: list[Image.Image], path: Path) -> None:
        strip = Image.new("RGBA", (256 * len(frames), 256), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * 256, 0), fr)
        strip.save(path, "PNG")

    idle_frames = build_strip(idle_row, precleaned=idle_raw)
    run_frames = build_strip(run_row)
    attack_frames = build_strip(attack_row)

    save_strip(idle_frames, output_dir / "idle.png")
    save_strip(run_frames, output_dir / "run.png")
    save_strip(attack_frames, output_dir / "attack.png")
    idle_frames[0].save(output_dir / "portrait.png", "PNG")
    print(f"Saved strips to {output_dir} (base_scale={base_scale:.3f})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--rows", type=int, default=3)
    parser.add_argument("--cols", type=int, default=4)
    parser.add_argument("--idle-row", type=int, default=0)
    parser.add_argument("--run-row", type=int, default=1)
    parser.add_argument("--attack-row", type=int, default=2)
    parser.add_argument("--chroma", choices=["green", "magenta"], default="green")
    args = parser.parse_args()

    process_sheet(
        args.input,
        args.output_dir,
        rows=args.rows,
        cols=args.cols,
        idle_row=args.idle_row,
        run_row=args.run_row,
        attack_row=args.attack_row,
        chroma=args.chroma,
    )


if __name__ == "__main__":
    main()
