#!/usr/bin/env python3
"""
Generate Apple macOS .icns icon for Mobius IDE.
Complies with Apple Human Interface Guidelines for free-form icons on macOS:
- 1024x1024 master canvas with 100% transparent background (no solid squircle/background box)
- Centered Mobius infinity ribbon logo with crisp proportions
- Soft silhouette drop shadow adhering to macOS native lighting (offset +12px, blur 14px, low opacity)
- High-quality multi-resolution mipmaps (16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024)
"""

import io
import os
import struct
import sys
from PIL import Image, ImageFilter
import numpy as np


def generate_mac_icns(logo_path: str, output_icns_path: str) -> bool:
    if not os.path.exists(logo_path):
        print(f"[ERROR] Source logo not found: {logo_path}", file=sys.stderr)
        return False

    logo = Image.open(logo_path).convert('RGBA')

    # Trim any empty transparent margins in the source logo for accurate centering
    bbox = logo.getbbox()
    if bbox:
        logo = logo.crop(bbox)

    canvas_size = 1024
    # Standard macOS icon width for wide horizontal shapes (matches VS Code 864px)
    target_w = 864
    ratio = target_w / float(logo.width)
    target_h = int(round(logo.height * ratio))
    logo_resized = logo.resize((target_w, target_h), Image.Resampling.LANCZOS)

    pos_x = (canvas_size - target_w) // 2
    pos_y = (canvas_size - target_h) // 2

    # 1. Base canvas with 100% transparent background
    canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))

    # 2. Subtle silhouette contact shadow following Apple HIG for free-form icons
    # Offset y +12px, blur 14px, max opacity ~22% (56/255)
    logo_alpha = logo_resized.getchannel('A')
    shadow_alpha_canvas = Image.new('L', (canvas_size, canvas_size), 0)
    shadow_alpha_canvas.paste(logo_alpha, (pos_x, pos_y + 12))
    shadow_blurred = shadow_alpha_canvas.filter(ImageFilter.GaussianBlur(14))

    s_arr = (np.array(shadow_blurred, dtype=np.float32) * (56.0 / 255.0)).astype(np.uint8)
    shadow_layer = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    shadow_layer.putalpha(Image.fromarray(s_arr, mode='L'))

    canvas.paste(shadow_layer, (0, 0), shadow_layer)

    # 3. Paste Mobius infinity ribbon logo directly on top
    canvas.paste(logo_resized, (pos_x, pos_y), logo_resized)

    # 4. Generate multi-resolution mipmaps with Lanczos resampling
    mip_sizes = [512, 256, 128, 64, 32, 16]
    append_images = []
    for s in mip_sizes:
        mip = canvas.resize((s, s), Image.Resampling.LANCZOS)
        append_images.append(mip)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(os.path.abspath(output_icns_path)), exist_ok=True)

    # Save as macOS .icns with bundled multi-resolution mipmaps
    canvas.save(output_icns_path, format='ICNS', append_images=append_images)
    print(f"[OK] Generated transparent macOS icon: {output_icns_path} ({os.path.getsize(output_icns_path)} bytes)")
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
