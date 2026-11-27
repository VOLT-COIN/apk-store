#!/usr/bin/env python3
"""Generate NOVA launcher icons procedurally (no binary assets in the repo).

Geometry: 6-point sparkle, waist 0.40, exponent 2.2, tip pointing up.
Rendered at 4x and downsampled with LANCZOS so edges stay crisp at every size.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

WAIST = 0.40
EXP = 2.2
PHI = -120.0
C1 = (20, 224, 210)
C2 = (11, 92, 255)
C3 = (18, 168, 232)
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
SS = 4


def _radius(theta):
    u = 3.0 * (theta - math.radians(PHI))
    return WAIST + (1.0 - WAIST) * abs(math.sin(u)) ** EXP


def _points(cx, cy, r, steps=720):
    out = []
    for i in range(steps):
        th = 2.0 * math.pi * i / steps
        rr = r * _radius(th)
        out.append((cx + rr * math.cos(th), cy + rr * math.sin(th)))
    return out


def _gradient(size):
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126.0
            if t < 0.52:
                k = t / 0.52
                col = [int(C1[i] + (C3[i] - C1[i]) * k) for i in range(3)]
            else:
                k = (t - 0.52) / 0.48
                col = [int(C3[i] + (C2[i] - C3[i]) * k) for i in range(3)]
            px[x, y] = tuple(col)
    return small.resize((size, size), Image.BICUBIC)


def icon(px):
    s = px * SS
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.225), fill=255)
    base = _gradient(px).resize((s, s), Image.BICUBIC)
    light = Image.new("L", (s, s), 0)
    ImageDraw.Draw(light).ellipse([-s * 0.35, -s * 0.60, s * 0.85, s * 0.45], fill=16)
    light = light.filter(ImageFilter.GaussianBlur(s * 0.12)).point(lambda v: int(v * 0.45))
    base = Image.composite(Image.new("RGB", (s, s), (255, 255, 255)), base, light)
    mark = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mark).polygon(_points(s / 2.0, s / 2.0, s * 0.30), fill=255)
    out = Image.new("RGB", (s, s), (9, 13, 22))
    out.paste(base, (0, 0), mask)
    out.paste(Image.new("RGB", (s, s), (255, 255, 255)), (0, 0), mark)
    return out.resize((px, px), Image.LANCZOS)


def main(res_dir):
    for dens, px in SIZES.items():
        d = os.path.join(res_dir, "mipmap-" + dens)
        os.makedirs(d, exist_ok=True)
        icon(px).save(os.path.join(d, "ic_launcher.png"), "PNG")
    print("NOVA icons written to", res_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/res")
