#!/usr/bin/env python3
"""Generate launcher icons for the Makhzan store app from a 512px master."""
import base64, io, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'app', 'assets', 'icon-512.b64')
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

def main(res_dir):
    with open(SRC, 'rb') as f:
        master = Image.open(io.BytesIO(base64.b64decode(f.read()))).convert('RGBA')
    for dens, px in SIZES.items():
        d = os.path.join(res_dir, 'mipmap-' + dens)
        os.makedirs(d, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))
    print('icons written to', res_dir)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'android/app/src/main/res')
