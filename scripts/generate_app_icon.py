#!/usr/bin/env python3
"""Generate clean 1024x1024 iOS AppIcon PNG + Assets.xcassets JSON files."""
import json
from pathlib import Path
from PIL import Image, ImageDraw


def draw_icon(size: int = 1024) -> Image.Image:
    # Render at 4x supersampling for crisp anti-aliased curves
    scale = 4
    w = size * scale
    img = Image.new("RGB", (w, w), (11, 79, 74))
    draw = ImageDraw.Draw(img)

    # Subtle vertical oceanic teal gradient (#0B4F4A -> #136F63)
    top = (11, 74, 72)
    bottom = (18, 118, 106)
    for y in range(w):
        t = y / (w - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

    # Subtle warm radial highlight near top-center (soft luminous depth, no neon halo)
    cx, cy = int(w * 0.50), int(w * 0.26)
    max_r = int(w * 0.52)
    overlay = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(overlay)
    for step in range(40, 0, -1):
        rad = int(max_r * (step / 40.0))
        alpha = int(3 * (1.0 - step / 40.0))
        odraw.ellipse(
            [(cx - rad, cy - rad), (cx + rad, cy + rad)],
            fill=(94, 234, 212, alpha),
        )
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    draw = ImageDraw.Draw(img)

    # Geometric rounded frame (represents organized schedule + wallet)
    pad = int(w * 0.21)
    radius = int(w * 0.12)
    stroke = int(w * 0.044)
    draw.rounded_rectangle(
        [(pad, pad), (w - pad, w - pad)],
        radius=radius,
        outline=(248, 250, 252),
        width=stroke,
    )

    # Clean mint accent bar at top of frame (calendar/ledger header motif)
    bar_pad_x = int(w * 0.30)
    bar_y = int(w * 0.325)
    bar_h = int(w * 0.032)
    draw.rounded_rectangle(
        [(bar_pad_x, bar_y), (w - bar_pad_x, bar_y + bar_h)],
        radius=bar_h // 2,
        fill=(94, 234, 212),
    )

    # Bold crisp checkmark centered below bar (completion + financial clarity)
    p1 = (int(w * 0.345), int(w * 0.565))
    p2 = (int(w * 0.460), int(w * 0.675))
    p3 = (int(w * 0.675), int(w * 0.455))
    check_w = int(w * 0.056)
    draw.line([p1, p2, p3], fill=(248, 250, 252), width=check_w, joint="curve")
    # Round line caps manually for geometric precision
    cap_r = check_w // 2
    for pt in (p1, p2, p3):
        draw.ellipse(
            [(pt[0] - cap_r, pt[1] - cap_r), (pt[0] + cap_r, pt[1] + cap_r)],
            fill=(248, 250, 252),
        )

    return img.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    assets_root = Path("App/PLAApp/Resources/Assets.xcassets")
    appicon_dir = assets_root / "AppIcon.appiconset"
    accent_dir = assets_root / "AccentColor.colorset"
    appicon_dir.mkdir(parents=True, exist_ok=True)
    accent_dir.mkdir(parents=True, exist_ok=True)

    icon = draw_icon(1024)
    icon.save(appicon_dir / "AppIcon-1024.png", format="PNG", optimize=True)
    icon.resize((512, 512), Image.Resampling.LANCZOS).save(
        Path("docs/app-icon.png"), format="PNG", optimize=True
    )

    (assets_root / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )

    (appicon_dir / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "filename": "AppIcon-1024.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    # Teal brand tint: #0F766E in Light Mode (5.4:1 contrast on white), #2DD4BF in Dark Mode
    (accent_dir / "Contents.json").write_text(
        json.dumps(
            {
                "colors": [
                    {
                        "color": {
                            "color-space": "srgb",
                            "components": {
                                "alpha": "1.000",
                                "blue": "0.431",
                                "green": "0.463",
                                "red": "0.059",
                            },
                        },
                        "idiom": "universal",
                    },
                    {
                        "appearances": [
                            {"appearance": "luminosity", "value": "dark"}
                        ],
                        "color": {
                            "color-space": "srgb",
                            "components": {
                                "alpha": "1.000",
                                "blue": "0.749",
                                "green": "0.831",
                                "red": "0.176",
                            },
                        },
                        "idiom": "universal",
                    },
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("Generated AppIcon-1024.png, docs/app-icon.png, and Assets.xcassets manifests.")


if __name__ == "__main__":
    main()
