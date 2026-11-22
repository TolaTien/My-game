"""Generate crisp 16-bit chibi pixel-art 4-direction sprite sheets for the 6 core heroes.

Produces for each hero (george, ranger, tanker, ninja, valeria, garrick):
  - assets/images/heroes/<hero>/idle.png      (1024x256 RGBA: 4 frames facing right)
  - assets/images/heroes/<hero>/run.png       (1024x1024 RGBA: 4 rows x 4 cols)
        Row 0: Down  (Front view, 4 frames)
        Row 1: Up    (Back view, 4 frames)
        Row 2: Left  (Left side view, 4 frames)
        Row 3: Right (Right side view, 4 frames)
  - assets/images/heroes/<hero>/attack.png    (1024x256 RGBA: 4 dynamic attack frames)
  - assets/images/heroes/<hero>/portrait.png  (256x256 RGBA: front-facing chibi portrait)
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from PIL import Image, ImageDraw

OUTLINE = (18, 16, 32, 255)
SKIN = (255, 224, 189, 255)
SKIN_SHADE = (232, 182, 140, 255)
WHITE = (255, 255, 255, 255)


@dataclass
class HeroPalette:
    hero_id: str
    armor: tuple[int, int, int, int]
    armor_dark: tuple[int, int, int, int]
    armor_light: tuple[int, int, int, int]
    trim: tuple[int, int, int, int]
    helmet: tuple[int, int, int, int]
    helmet_dark: tuple[int, int, int, int]
    crest: tuple[int, int, int, int]
    cape: tuple[int, int, int, int]
    cape_dark: tuple[int, int, int, int]
    boots: tuple[int, int, int, int]
    eye: tuple[int, int, int, int]
    vfx_primary: tuple[int, int, int, int]
    vfx_secondary: tuple[int, int, int, int]
    weapon: str  # hammer, bow, shield, katana, staff, greatsword
    head_style: str  # horned_helm, hood, visor_helm, ninja_mask, tiara_hair, dwarf_helm


HEROES: list[HeroPalette] = [
    HeroPalette(
        hero_id="george",
        armor=(198, 40, 40, 255),
        armor_dark=(132, 20, 24, 255),
        armor_light=(239, 83, 80, 255),
        trim=(255, 213, 79, 255),
        helmet=(120, 144, 156, 255),
        helmet_dark=(69, 90, 100, 255),
        crest=(229, 57, 53, 255),
        cape=(183, 28, 28, 255),
        cape_dark=(120, 14, 18, 255),
        boots=(62, 74, 82, 255),
        eye=(28, 36, 56, 255),
        vfx_primary=(255, 215, 0, 255),
        vfx_secondary=(255, 111, 0, 255),
        weapon="hammer",
        head_style="horned_helm",
    ),
    HeroPalette(
        hero_id="ranger",
        armor=(46, 125, 50, 255),
        armor_dark=(27, 78, 32, 255),
        armor_light=(102, 187, 106, 255),
        trim=(255, 213, 79, 255),
        helmet=(27, 94, 32, 255),
        helmet_dark=(16, 60, 20, 255),
        crest=(255, 235, 130, 255),
        cape=(34, 110, 42, 255),
        cape_dark=(18, 68, 24, 255),
        boots=(93, 64, 55, 255),
        eye=(0, 230, 118, 255),
        vfx_primary=(0, 230, 118, 255),
        vfx_secondary=(238, 255, 65, 255),
        weapon="bow",
        head_style="hood",
    ),
    HeroPalette(
        hero_id="tanker",
        armor=(21, 101, 192, 255),
        armor_dark=(13, 62, 128, 255),
        armor_light=(66, 165, 245, 255),
        trim=(224, 236, 248, 255),
        helmet=(96, 125, 139, 255),
        helmet_dark=(55, 71, 79, 255),
        crest=(0, 176, 255, 255),
        cape=(13, 71, 161, 255),
        cape_dark=(8, 42, 102, 255),
        boots=(52, 68, 78, 255),
        eye=(64, 196, 255, 255),
        vfx_primary=(0, 176, 255, 255),
        vfx_secondary=(255, 215, 0, 255),
        weapon="shield",
        head_style="visor_helm",
    ),
    HeroPalette(
        hero_id="ninja",
        armor=(40, 38, 72, 255),
        armor_dark=(22, 20, 44, 255),
        armor_light=(72, 68, 116, 255),
        trim=(229, 57, 53, 255),
        helmet=(30, 28, 56, 255),
        helmet_dark=(16, 14, 34, 255),
        crest=(211, 47, 47, 255),
        cape=(198, 40, 40, 255),
        cape_dark=(130, 18, 24, 255),
        boots=(28, 28, 44, 255),
        eye=(233, 30, 99, 255),
        vfx_primary=(255, 23, 68, 255),
        vfx_secondary=(224, 64, 251, 255),
        weapon="katana",
        head_style="ninja_mask",
    ),
    HeroPalette(
        hero_id="valeria",
        armor=(2, 136, 209, 255),
        armor_dark=(1, 87, 155, 255),
        armor_light=(79, 195, 247, 255),
        trim=(255, 82, 82, 255),
        helmet=(225, 245, 254, 255),
        helmet_dark=(144, 202, 249, 255),
        crest=(0, 229, 255, 255),
        cape=(21, 101, 192, 255),
        cape_dark=(13, 58, 128, 255),
        boots=(26, 35, 126, 255),
        eye=(0, 229, 255, 255),
        vfx_primary=(0, 229, 255, 255),
        vfx_secondary=(255, 61, 0, 255),
        weapon="staff",
        head_style="tiara_hair",
    ),
    HeroPalette(
        hero_id="garrick",
        armor=(121, 104, 92, 255),
        armor_dark=(78, 64, 56, 255),
        armor_light=(166, 148, 134, 255),
        trim=(255, 179, 0, 255),
        helmet=(141, 110, 99, 255),
        helmet_dark=(93, 64, 55, 255),
        crest=(211, 47, 47, 255),
        cape=(153, 27, 27, 255),
        cape_dark=(96, 16, 16, 255),
        boots=(68, 52, 44, 255),
        eye=(255, 171, 0, 255),
        vfx_primary=(255, 179, 0, 255),
        vfx_secondary=(255, 235, 59, 255),
        weapon="greatsword",
        head_style="dwarf_helm",
    ),
]


def add_pixel_outline(img: Image.Image, outline_color: tuple[int, int, int, int] = OUTLINE) -> Image.Image:
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 200:
                        dst[x, y] = outline_color
                        break
    return out


def draw_weapon_side(
    d: ImageDraw.ImageDraw,
    p: HeroPalette,
    hx: int,
    hy: int,
    action: str,
    frame: int,
) -> None:
    # Attack poses: 0=windup, 1=mid-swing, 2=impact+vfx, 3=recovery
    if p.weapon == "hammer":
        if action == "attack" and frame == 0:
            d.line([(hx - 2, hy + 2), (hx - 6, hy - 14)], fill=(109, 76, 65, 255), width=2)
            d.rectangle([hx - 13, hy - 20, hx - 2, hy - 11], fill=(84, 110, 122, 255))
            d.rectangle([hx - 11, hy - 18, hx - 4, hy - 14], fill=p.trim)
        elif action == "attack" and frame == 1:
            d.line([(hx, hy), (hx + 10, hy - 10)], fill=(109, 76, 65, 255), width=2)
            d.rectangle([hx + 7, hy - 17, hx + 18, hy - 7], fill=(84, 110, 122, 255))
            d.rectangle([hx + 9, hy - 15, hx + 16, hy - 10], fill=p.trim)
        elif action == "attack" and frame == 2:
            d.line([(hx, hy + 1), (hx + 13, hy + 5)], fill=(109, 76, 65, 255), width=2)
            d.rectangle([hx + 10, hy - 1, hx + 20, hy + 10], fill=(84, 110, 122, 255))
            d.rectangle([hx + 12, hy + 2, hx + 18, hy + 7], fill=p.trim)
            d.arc([hx - 4, hy - 18, hx + 24, hy + 14], start=-70, end=65, fill=p.vfx_primary, width=4)
            d.arc([hx - 2, hy - 16, hx + 21, hy + 12], start=-60, end=55, fill=WHITE, width=2)
        else:
            dy = -1 if frame % 2 == 1 else 0
            d.line([(hx - 1, hy + 4 + dy), (hx + 8, hy - 7 + dy)], fill=(109, 76, 65, 255), width=2)
            d.rectangle([hx + 5, hy - 14 + dy, hx + 14, hy - 5 + dy], fill=(84, 110, 122, 255))
            d.rectangle([hx + 7, hy - 12 + dy, hx + 12, hy - 8 + dy], fill=p.trim)

    elif p.weapon == "bow":
        pull = 3 if (action == "attack" and frame in (1, 2)) else 0
        d.arc([hx + 1, hy - 11, hx + 12, hy + 9], start=-85, end=85, fill=(141, 110, 99, 255), width=2)
        d.line([(hx + 6, hy - 10), (hx + 5 - pull, hy - 1), (hx + 6, hy + 8)], fill=(200, 255, 210, 255), width=1)
        if action == "attack":
            if frame in (0, 1):
                d.line([(hx + 2 - pull, hy - 1), (hx + 15, hy - 1)], fill=p.vfx_secondary, width=2)
                d.polygon([(hx + 14, hy - 3), (hx + 18, hy - 1), (hx + 14, hy + 1)], fill=WHITE)
            elif frame == 2:
                d.line([(hx + 8, hy - 1), (hx + 24, hy - 1)], fill=p.vfx_primary, width=3)
                d.line([(hx + 10, hy - 1), (hx + 22, hy - 1)], fill=WHITE, width=1)
                d.ellipse([hx + 8, hy - 6, hx + 16, hy + 4], outline=p.vfx_primary, width=2)

    elif p.weapon == "shield":
        thrust = 5 if (action == "attack" and frame in (1, 2)) else 0
        sx = hx + 2 + thrust
        sy = hy - 9
        d.rounded_rectangle([sx, sy, sx + 11, sy + 18], radius=3, fill=p.armor, outline=p.trim, width=2)
        d.line([(sx + 5, sy + 3), (sx + 5, sy + 15)], fill=(255, 213, 79, 255), width=2)
        d.line([(sx + 2, sy + 8), (sx + 8, sy + 8)], fill=(255, 213, 79, 255), width=2)
        if action == "attack" and frame == 2:
            d.arc([sx + 3, sy - 6, sx + 18, sy + 22], start=-75, end=75, fill=p.vfx_primary, width=3)
            d.arc([sx + 5, sy - 4, sx + 16, sy + 20], start=-65, end=65, fill=WHITE, width=1)

    elif p.weapon == "katana":
        if action == "attack" and frame == 0:
            d.line([(hx - 3, hy - 1), (hx - 12, hy - 13)], fill=(224, 232, 244, 255), width=2)
            d.line([(hx + 1, hy + 1), (hx - 8, hy - 11)], fill=(224, 64, 251, 255), width=2)
        elif action == "attack" and frame == 1:
            d.line([(hx, hy), (hx + 15, hy - 9)], fill=(224, 232, 244, 255), width=2)
            d.line([(hx, hy + 2), (hx + 15, hy + 6)], fill=(224, 64, 251, 255), width=2)
        elif action == "attack" and frame == 2:
            d.line([(hx + 2, hy - 12), (hx + 20, hy + 8)], fill=p.vfx_primary, width=4)
            d.line([(hx + 20, hy - 12), (hx + 2, hy + 8)], fill=p.vfx_secondary, width=4)
            d.line([(hx + 4, hy - 10), (hx + 18, hy + 6)], fill=WHITE, width=2)
            d.line([(hx + 18, hy - 10), (hx + 4, hy + 6)], fill=WHITE, width=2)
        else:
            d.line([(hx - 1, hy + 2), (hx + 11, hy - 8)], fill=(224, 232, 244, 255), width=2)
            d.line([(hx - 2, hy + 3), (hx + 1, hy)], fill=p.trim, width=2)

    elif p.weapon == "staff":
        raise_y = -4 if (action == "attack" and frame in (0, 1)) else 0
        thrust_x = 4 if (action == "attack" and frame == 2) else 0
        sx = hx + 5 + thrust_x
        d.line([(sx, hy + 10), (sx, hy - 13 + raise_y)], fill=(176, 212, 244, 255), width=2)
        d.ellipse([sx - 3, hy - 18 + raise_y, sx + 3, hy - 12 + raise_y], fill=p.vfx_primary)
        d.ellipse([sx - 1, hy - 16 + raise_y, sx + 1, hy - 14 + raise_y], fill=WHITE)
        # Orbiting fire ember
        ox = hx - 8 + int(round(math.cos(frame * 1.5) * 2))
        oy = hy - 8 + int(round(math.sin(frame * 1.5) * 2))
        d.ellipse([ox - 2, oy - 2, ox + 2, oy + 2], fill=p.vfx_secondary)
        if action == "attack" and frame == 2:
            d.ellipse([sx + 3, hy - 14, sx + 15, hy - 2], fill=p.vfx_primary)
            d.ellipse([sx + 6, hy - 11, sx + 12, hy - 5], fill=WHITE)
            d.arc([sx, hy - 17, sx + 18, hy + 1], start=-90, end=90, fill=p.vfx_secondary, width=2)

    elif p.weapon == "greatsword":
        if action == "attack" and frame == 0:
            d.polygon([(hx - 4, hy - 2), (hx - 12, hy - 18), (hx - 7, hy - 21), (hx, hy - 5)], fill=(150, 142, 134, 255))
            d.line([(hx - 9, hy - 17), (hx - 3, hy - 5)], fill=p.trim, width=2)
        elif action == "attack" and frame == 1:
            d.polygon([(hx, hy - 2), (hx + 14, hy - 16), (hx + 18, hy - 12), (hx + 4, hy + 2)], fill=(150, 142, 134, 255))
            d.line([(hx + 2, hy - 2), (hx + 14, hy - 13)], fill=p.trim, width=2)
        elif action == "attack" and frame == 2:
            d.polygon([(hx + 2, hy + 1), (hx + 19, hy + 3), (hx + 22, hy + 7), (hx + 16, hy + 10), (hx + 1, hy + 6)], fill=(150, 142, 134, 255))
            d.arc([hx - 4, hy - 19, hx + 25, hy + 15], start=-75, end=70, fill=p.vfx_primary, width=4)
            d.arc([hx - 1, hy - 16, hx + 22, hy + 12], start=-65, end=60, fill=WHITE, width=2)
        else:
            d.polygon([(hx + 2, hy + 3), (hx + 11, hy - 16), (hx + 15, hy - 14), (hx + 6, hy + 5)], fill=(150, 142, 134, 255))
            d.line([(hx + 5, hy + 1), (hx + 12, hy - 13)], fill=p.trim, width=2)


def draw_head(d: ImageDraw.ImageDraw, p: HeroPalette, cx: int, cy: int, direction: str) -> None:
    # Base chibi head (16x14)
    if direction == "up":
        # Back of head: helmet/hood/hair covers all of it
        d.rounded_rectangle([cx - 8, cy - 8, cx + 8, cy + 5], radius=5, fill=p.helmet)
        d.rectangle([cx - 7, cy - 2, cx + 7, cy + 4], fill=p.helmet_dark)
        if p.head_style == "horned_helm":
            d.polygon([(cx - 8, cy - 3), (cx - 12, cy - 8), (cx - 7, cy - 6)], fill=(235, 224, 196, 255))
            d.polygon([(cx + 8, cy - 3), (cx + 12, cy - 8), (cx + 7, cy - 6)], fill=(235, 224, 196, 255))
            d.ellipse([cx - 3, cy - 12, cx + 3, cy - 5], fill=p.crest)
        elif p.head_style == "hood":
            d.polygon([(cx - 5, cy - 6), (cx, cy - 11), (cx + 5, cy - 6)], fill=p.helmet)
            d.rectangle([cx - 7, cy + 2, cx + 7, cy + 5], fill=p.trim)
        elif p.head_style == "visor_helm":
            d.rectangle([cx - 2, cy - 11, cx + 2, cy - 4], fill=p.crest)
            d.line([(cx - 6, cy - 4), (cx + 6, cy - 4)], fill=p.trim, width=2)
        elif p.head_style == "ninja_mask":
            # Spiky dark shinobi hair + red scarf knot at back
            d.polygon([(cx - 8, cy - 5), (cx - 10, cy - 10), (cx - 3, cy - 8)], fill=p.helmet)
            d.polygon([(cx + 8, cy - 5), (cx + 10, cy - 10), (cx + 3, cy - 8)], fill=p.helmet)
            d.polygon([(cx - 3, cy - 7), (cx, cy - 12), (cx + 3, cy - 7)], fill=p.helmet)
            d.rectangle([cx - 6, cy + 3, cx + 6, cy + 6], fill=p.crest)
        elif p.head_style == "tiara_hair":
            # Long flowing silver-ice hair from back
            d.rounded_rectangle([cx - 8, cy - 8, cx + 8, cy + 10], radius=4, fill=p.helmet)
            d.rectangle([cx - 6, cy + 3, cx + 6, cy + 10], fill=p.helmet_dark)
            d.polygon([(cx - 4, cy - 8), (cx, cy - 12), (cx + 4, cy - 8)], fill=p.crest)
        elif p.head_style == "dwarf_helm":
            d.polygon([(cx - 8, cy - 4), (cx - 12, cy - 9), (cx - 6, cy - 6)], fill=p.trim)
            d.polygon([(cx + 8, cy - 4), (cx + 12, cy - 9), (cx + 6, cy - 6)], fill=p.trim)
            d.rectangle([cx - 2, cy - 11, cx + 2, cy - 5], fill=p.crest)
        return

    # Down (Front) or Right (Side)
    d.rounded_rectangle([cx - 7, cy - 6, cx + 7, cy + 5], radius=4, fill=SKIN)
    d.rectangle([cx - 6, cy + 3, cx + 6, cy + 5], fill=SKIN_SHADE)

    if direction == "down":
        # Two expressive chibi eyes
        for ex in (cx - 4, cx + 2):
            d.rectangle([ex, cy - 1, ex + 2, cy + 2], fill=p.eye)
            d.point((ex, cy - 1), fill=WHITE)
    else:
        # Side-facing (right): 2 eyes shifted right
        d.rectangle([cx, cy - 1, cx + 2, cy + 2], fill=p.eye)
        d.point((cx, cy - 1), fill=WHITE)
        d.rectangle([cx + 4, cy - 1, cx + 6, cy + 2], fill=p.eye)
        d.point((cx + 4, cy - 1), fill=WHITE)

    # Headgear / Hair
    if p.head_style == "horned_helm":
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 2], radius=4, fill=p.helmet)
        d.rectangle([cx - 7, cy - 4, cx + 7, cy - 2], fill=p.helmet_dark)
        d.polygon([(cx - 8, cy - 5), (cx - 12, cy - 10), (cx - 6, cy - 7)], fill=(235, 224, 196, 255))
        d.polygon([(cx + 8, cy - 5), (cx + 12, cy - 10), (cx + 6, cy - 7)], fill=(235, 224, 196, 255))
        d.ellipse([cx - 4, cy - 13, cx + 3, cy - 7], fill=p.crest)
    elif p.head_style == "hood":
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 2], radius=4, fill=p.helmet)
        d.polygon([(cx - 8, cy - 6), (cx - 11, cy - 3), (cx - 6, cy + 4)], fill=p.helmet_dark)
        d.rectangle([cx - 6, cy - 3, cx + 6, cy - 2], fill=p.crest)  # blonde bangs
        d.line([(cx - 7, cy - 3), (cx + 7, cy - 3)], fill=p.trim, width=1)
    elif p.head_style == "visor_helm":
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 1], radius=3, fill=p.helmet)
        d.rectangle([cx - 6, cy - 3, cx + 6, cy - 1], fill=p.helmet_dark)
        d.rectangle([cx - 2, cy - 12, cx + 2, cy - 6], fill=p.crest)
        d.line([(cx - 7, cy - 5), (cx + 7, cy - 5)], fill=p.trim, width=1)
    elif p.head_style == "ninja_mask":
        # Full mask over lower face + spiky dark hair
        d.rectangle([cx - 7, cy + 1, cx + 7, cy + 5], fill=p.helmet_dark)
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 2], radius=3, fill=p.helmet)
        d.polygon([(cx - 8, cy - 6), (cx - 11, cy - 10), (cx - 4, cy - 8)], fill=p.helmet)
        d.polygon([(cx - 2, cy - 8), (cx + 1, cy - 13), (cx + 4, cy - 8)], fill=p.helmet)
        d.polygon([(cx + 4, cy - 7), (cx + 10, cy - 10), (cx + 7, cy - 4)], fill=p.helmet)
        d.rectangle([cx - 7, cy + 4, cx + 7, cy + 7], fill=p.crest)  # crimson scarf
    elif p.head_style == "tiara_hair":
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 2], radius=4, fill=p.helmet)
        d.rectangle([cx - 8, cy - 4, cx - 5, cy + 5], fill=p.helmet_dark)
        if direction == "down":
            d.rectangle([cx + 5, cy - 4, cx + 8, cy + 5], fill=p.helmet_dark)
        d.polygon([(cx - 4, cy - 8), (cx, cy - 12), (cx + 4, cy - 8)], fill=p.crest)
        d.point((cx, cy - 10), fill=WHITE)
    elif p.head_style == "dwarf_helm":
        d.rounded_rectangle([cx - 8, cy - 9, cx + 8, cy - 2], radius=3, fill=p.helmet)
        d.polygon([(cx - 8, cy - 5), (cx - 12, cy - 9), (cx - 6, cy - 7)], fill=p.trim)
        d.polygon([(cx + 8, cy - 5), (cx + 12, cy - 9), (cx + 6, cy - 7)], fill=p.trim)
        # Fiery red braided beard
        d.polygon([(cx - 5, cy + 3), (cx + 6, cy + 3), (cx + 1, cy + 10)], fill=p.crest)


def render_frame(p: HeroPalette, direction: str, action: str, frame: int) -> Image.Image:
    # Draw on 48x48 pixel-art canvas, then scale 4x -> 192 -> place on 256x256 with feet aligned
    # For "left", we render "right" and flip horizontally!
    if direction == "left":
        right_img = render_frame(p, "right", action, frame)
        return right_img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    grid = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)

    cx = 28 if action == "attack" else 31
    base_y = 56

    # Animation offsets
    if action == "idle":
        bob = -1 if frame in (1, 2) else 0
        stride = 0
        l_lift = 0
        r_lift = 0
        cape_sway = 1 if frame in (1, 2) else 0
    elif action == "run":
        bobs = [0, -2, 0, -2]
        strides = [-3, 0, 3, 0]
        l_lifts = [0, 2, 0, 0]
        r_lifts = [0, 0, 0, 2]
        bob = bobs[frame % 4]
        stride = strides[frame % 4]
        l_lift = l_lifts[frame % 4]
        r_lift = r_lifts[frame % 4]
        cape_sway = 2 if frame % 2 == 0 else 4
    else:  # attack
        bob = -1 if frame == 1 else (1 if frame == 2 else 0)
        stride = 2 if frame == 2 else 0
        l_lift = 0
        r_lift = 0
        cape_sway = 4 if frame == 2 else 2

    lean = 2 if (action == "run" and direction == "right") or (action == "attack" and frame == 2) else 0
    body_cx = cx + lean
    torso_y = base_y - 16 + bob
    head_y = torso_y - 9

    # 1. Cape / Scarf behind body (visible on side & down; drawn in front on up)
    if direction == "right":
        d.polygon(
            [
                (body_cx - 4, torso_y + 1),
                (body_cx - 12 - cape_sway, torso_y + 12),
                (body_cx - 6 - cape_sway // 2, torso_y + 15),
                (body_cx + 1, torso_y + 8),
            ],
            fill=p.cape,
        )
        d.line(
            [(body_cx - 5, torso_y + 3), (body_cx - 11 - cape_sway, torso_y + 12)],
            fill=p.cape_dark,
            width=2,
        )
    elif direction == "down":
        d.polygon(
            [
                (body_cx - 8, torso_y + 1),
                (body_cx + 8, torso_y + 1),
                (body_cx + 10 + cape_sway // 2, torso_y + 14),
                (body_cx - 10 - cape_sway // 2, torso_y + 14),
            ],
            fill=p.cape_dark,
        )

    # 2. Legs / Boots
    if direction in ("down", "up"):
        d.rounded_rectangle([body_cx - 6, base_y - 7 - l_lift, body_cx - 1, base_y - l_lift], radius=1, fill=p.boots)
        d.rounded_rectangle([body_cx + 1, base_y - 7 - r_lift, body_cx + 6, base_y - r_lift], radius=1, fill=p.boots)
        d.rectangle([body_cx - 6, base_y - 4 - l_lift, body_cx - 1, base_y - 3 - l_lift], fill=p.trim)
        d.rectangle([body_cx + 1, base_y - 4 - r_lift, body_cx + 6, base_y - 3 - r_lift], fill=p.trim)
    else:
        # Side stride
        d.rounded_rectangle([body_cx - 5 - stride, base_y - 7 - l_lift, body_cx - stride, base_y - l_lift], radius=1, fill=p.boots)
        d.rounded_rectangle([body_cx + stride, base_y - 7 - r_lift, body_cx + 5 + stride, base_y - r_lift], radius=1, fill=p.boots)
        d.rectangle([body_cx + stride, base_y - 4 - r_lift, body_cx + 5 + stride, base_y - 3 - r_lift], fill=p.trim)

    # 3. Torso / Armor
    d.rounded_rectangle([body_cx - 7, torso_y, body_cx + 7, torso_y + 11], radius=3, fill=p.armor)
    d.rectangle([body_cx - 6, torso_y + 1, body_cx + 6, torso_y + 3], fill=p.armor_light)
    d.rectangle([body_cx - 7, torso_y + 7, body_cx + 7, torso_y + 10], fill=p.armor_dark)
    d.rectangle([body_cx - 7, torso_y + 6, body_cx + 7, torso_y + 8], fill=p.trim)  # belt

    # Pauldrons (shoulders)
    d.ellipse([body_cx - 9, torso_y - 1, body_cx - 4, torso_y + 5], fill=p.armor_light, outline=p.trim)
    d.ellipse([body_cx + 4, torso_y - 1, body_cx + 9, torso_y + 5], fill=p.armor_light, outline=p.trim)

    # Back cape/quiver when facing UP
    if direction == "up":
        d.polygon(
            [
                (body_cx - 8, torso_y + 1),
                (body_cx + 8, torso_y + 1),
                (body_cx + 9, torso_y + 14 + (cape_sway // 2)),
                (body_cx - 9, torso_y + 14 + (cape_sway // 2)),
            ],
            fill=p.cape,
        )
        d.line([(body_cx - 4, torso_y + 3), (body_cx - 5, torso_y + 13)], fill=p.cape_dark, width=2)
        d.line([(body_cx + 4, torso_y + 3), (body_cx + 5, torso_y + 13)], fill=p.cape_dark, width=2)
        if p.weapon == "bow":
            # Arrow quiver on back
            d.rectangle([body_cx + 2, torso_y - 2, body_cx + 6, torso_y + 8], fill=(121, 85, 72, 255))
            d.line([(body_cx + 3, torso_y - 5), (body_cx + 3, torso_y - 2)], fill=p.vfx_primary, width=1)
            d.line([(body_cx + 5, torso_y - 5), (body_cx + 5, torso_y - 2)], fill=p.vfx_secondary, width=1)

    # 4. Head
    draw_head(d, p, body_cx, head_y, direction)

    # 5. Weapon
    if direction == "right":
        draw_weapon_side(d, p, body_cx + 5, torso_y + 5, action, frame)
    elif direction == "down":
        # Compact side-held weapon visible from front
        wx = body_cx + 9
        wy = torso_y + 5
        if p.weapon == "shield":
            d.rounded_rectangle([wx - 3, wy - 5, wx + 4, wy + 7], radius=2, fill=p.armor, outline=p.trim)
        elif p.weapon == "staff":
            d.line([(wx, wy + 7), (wx, wy - 10)], fill=(176, 212, 244, 255), width=2)
            d.ellipse([wx - 2, wy - 13, wx + 2, wy - 9], fill=p.vfx_primary)
        elif p.weapon == "bow":
            d.arc([wx - 2, wy - 8, wx + 5, wy + 6], start=-80, end=80, fill=(141, 110, 99, 255), width=2)
        elif p.weapon == "hammer":
            d.line([(wx, wy + 6), (wx, wy - 7)], fill=(109, 76, 65, 255), width=2)
            d.rectangle([wx - 4, wy - 11, wx + 4, wy - 5], fill=(84, 110, 122, 255))
            d.rectangle([wx - 2, wy - 9, wx + 2, wy - 7], fill=p.trim)
        elif p.weapon == "greatsword":
            d.rectangle([wx - 2, wy - 12, wx + 2, wy + 3], fill=(150, 142, 134, 255))
            d.line([(wx, wy - 11), (wx, wy + 1)], fill=p.trim, width=1)
        elif p.weapon == "katana":
            d.line([(wx - 1, wy + 4), (wx + 4, wy - 8)], fill=(224, 232, 244, 255), width=2)
            d.line([(body_cx - 9, wy + 4), (body_cx - 13, wy - 7)], fill=(224, 64, 251, 255), width=2)

    outlined = add_pixel_outline(grid)

    # Upscale 4x nearest-neighbor (64x64 -> 256x256) with feet aligned at y=224..236
    cell = outlined.resize((256, 256), Image.Resampling.NEAREST)
    return cell


def generate_all() -> None:
    root = Path("assets/images/heroes")
    for hero in HEROES:
        out_dir = root / hero.hero_id
        out_dir.mkdir(parents=True, exist_ok=True)

        # 1. Idle strip (4x1, 1024x256, facing right)
        idle_strip = Image.new("RGBA", (1024, 256), (0, 0, 0, 0))
        for c in range(4):
            fr = render_frame(hero, "right", "idle", c)
            idle_strip.paste(fr, (c * 256, 0), fr)
        idle_strip.save(out_dir / "idle.png", "PNG")

        # 2. 4-Direction Run sheet (4x4, 1024x1024: Row 0=Down, 1=Up, 2=Left, 3=Right)
        run_sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        directions = ["down", "up", "left", "right"]
        for r, direction in enumerate(directions):
            for c in range(4):
                fr = render_frame(hero, direction, "run", c)
                run_sheet.paste(fr, (c * 256, r * 256), fr)
        run_sheet.save(out_dir / "run.png", "PNG")

        # 3. Attack strip (4x1, 1024x256, facing right)
        attack_strip = Image.new("RGBA", (1024, 256), (0, 0, 0, 0))
        for c in range(4):
            fr = render_frame(hero, "right", "attack", c)
            attack_strip.paste(fr, (c * 256, 0), fr)
        attack_strip.save(out_dir / "attack.png", "PNG")

        # 4. Portrait (256x256, front-facing Down idle frame 0)
        portrait = render_frame(hero, "down", "idle", 0)
        portrait.save(out_dir / "portrait.png", "PNG")

        print(f"Generated 4-dir sprites for {hero.hero_id} -> {out_dir}")


if __name__ == "__main__":
    generate_all()
