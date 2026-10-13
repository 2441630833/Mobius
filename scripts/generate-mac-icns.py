#!/usr/bin/env python3
"""
Generate Apple macOS .icns icon for Mobius IDE.
Complies with Apple Human Interface Guidelines for macOS Big Sur, Monterey, Ventura, Sonoma, Sequoia:
- 1024x1024 master canvas
- 824x824 squircle body with continuous 185px corner radius
- Native macOS drop shadow with subtle blur & offset
- Sleek dark slate gradient (#242630 -> #14151b) matching developer IDE aesthetic
- Subtle top-edge inner light refraction highlight
- High-contrast, vibrant 3D Mobius infinity strip centered perfectly
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

def generate_mac_icns(logo_path: str, output_icns_path: str):
    if not os.path.exists(logo_path):
        print(f"[ERROR] Source logo not found: {logo_path}", file=sys.stderr)
        return False

    logo = Image.open(logo_path).convert('RGBA')

    canvas_size = 1024
    tile_w, tile_h = 824, 824
    radius = 185
    margin_x = (canvas_size - tile_w) // 2
    margin_y = (canvas_size - tile_h) // 2

    canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))

    # 1. Native macOS drop shadow (y offset +20, blur 28, opacity ~40%)
    shadow_mask = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.rounded_rectangle(
        [margin_x, margin_y + 20, margin_x + tile_w, margin_y + tile_h + 20],
        radius=radius,
        fill=(0, 0, 0, 100)
    )
    shadow = shadow_mask.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(shadow, (0, 0), shadow)

    # 2. Squircle tile with dark slate gradient (#242630 -> #14151b)
    mask = Image.new('L', (tile_w, tile_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, tile_w, tile_h], radius=radius, fill=255)

    arr = np.zeros((tile_h, tile_w, 4), dtype=np.uint8)
    top_color = np.array([36, 38, 48], dtype=np.float32)
    bot_color = np.array([20, 21, 27], dtype=np.float32)
    for y in range(tile_h):
        factor = y / float(tile_h)
        col = top_color * (1.0 - factor) + bot_color * factor
        arr[y, :, 0] = int(col[0])
        arr[y, :, 1] = int(col[1])
        arr[y, :, 2] = int(col[2])
        arr[y, :, 3] = 255

    grad_img = Image.fromarray(arr, 'RGBA')
    tile_masked = Image.new('RGBA', (tile_w, tile_h), (0, 0, 0, 0))
    tile_masked.paste(grad_img, (0, 0), mask)

    # 3. Inner border highlight
    border_draw = ImageDraw.Draw(tile_masked)
    border_draw.rounded_rectangle(
        [0, 0, tile_w - 1, tile_h - 1],
        radius=radius,
        outline=(255, 255, 255, 28),
        width=2
    )

    canvas.paste(tile_masked, (margin_x, margin_y), tile_masked)

    # 4. Mobius infinity logo centered
    logo_w = 660
    ratio = logo_w / float(logo.width)
    logo_h = int(logo.height * ratio)
    logo_resized = logo.resize((logo_w, logo_h), Image.LANCZOS)

    pos_x = (canvas_size - logo_w) // 2
    pos_y = (canvas_size - logo_h) // 2
    canvas.paste(logo_resized, (pos_x, pos_y), logo_resized)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(os.path.abspath(output_icns_path)), exist_ok=True)

    # Save as macOS .icns
    canvas.save(output_icns_path, format='ICNS')
    print(f"[OK] Generated macOS icon: {output_icns_path} ({os.path.getsize(output_icns_path)} bytes)")
    return True

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, '..'))
    default_logo = os.path.join(root_dir, 'static', 'images', 'logo.png')
    default_icns = os.path.join(root_dir, 'vscode', 'resources', 'darwin', 'code.icns')

    logo_arg = sys.argv[1] if len(sys.argv) > 1 else default_logo
    icns_arg = sys.argv[2] if len(sys.argv) > 2 else default_icns

    success = generate_mac_icns(logo_arg, icns_arg)
    sys.exit(0 if success else 1)
