"""Generate original, seamless painted architecture textures.

No photographic source is used. Low-frequency brush marks, irregular carved grain,
slate flecks and worn plaster are drawn deterministically; albedo and shallow normal
maps stay reusable across all building meshes. Requires Pillow and NumPy.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/resources/architecture"
OUT.mkdir(parents=True, exist_ok=True)
N = 512
RNG = np.random.default_rng(902616)
y, x = np.mgrid[0:N, 0:N] / N


def cloud(seed, scales=(2, 4, 9, 19), weights=(1.0, 0.48, 0.22, 0.09)):
    rng = np.random.default_rng(seed)
    field = np.zeros((N, N))
    for scale, weight in zip(scales, weights):
        for _ in range(8):
            fx = int(rng.integers(-scale, scale + 1))
            fy = int(rng.integers(-scale, scale + 1))
            field += np.sin((x * fx + y * fy) * math.tau + rng.random() * math.tau) * weight
    return field / max(np.std(field), 0.001)


def save(name, brightness, height, normal_strength=3.0):
    rgb = np.clip(brightness, 0.0, 1.0)
    if rgb.ndim == 2:
        rgb = np.repeat(rgb[..., None], 3, axis=2)
    Image.fromarray(np.uint8(rgb * 255), "RGB").save(OUT / f"{name}.png")
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * normal_strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * normal_strength
    normal = np.stack((-dx, dy, np.ones_like(dx)), axis=2)
    normal /= np.linalg.norm(normal, axis=2)[..., None]
    Image.fromarray(np.uint8((normal * 0.5 + 0.5) * 255), "RGB").save(OUT / f"{name}_normal.png")


# Carved timber: broad brush ribbons and drifting grain, with rings around knots.
warp = x + 0.012 * np.sin(y * math.tau * 2) + 0.006 * np.sin(y * math.tau * 5 + x * 4)
knots = [(0.26, 0.29), (0.76, 0.73)]
for kx, ky in knots:
    dx = (x - kx + 0.5) % 1.0 - 0.5
    dy = (y - ky + 0.5) % 1.0 - 0.5
    warp += 0.028 * np.sign(dx) * np.exp(-((dx / 0.095) ** 2 + (dy / 0.22) ** 2))
grains = np.sin(warp * math.tau * 31 + 0.8 * np.sin(y * math.tau))
broad = np.sin(warp * math.tau * 8 + 0.3 * np.cos(y * math.tau * 3))
wood = 0.88 + cloud(14) * 0.029 + broad * 0.040 - np.maximum(grains - 0.55, 0) * 0.105
height = broad * 0.12 + grains * 0.04
for kx, ky in knots:
    dx = (x - kx + 0.5) % 1.0 - 0.5
    dy = (y - ky + 0.5) % 1.0 - 0.5
    radius = np.sqrt((dx / 0.067) ** 2 + (dy / 0.15) ** 2)
    rings = np.exp(-radius * 1.4) * np.cos(radius * 15)
    wood += rings * 0.070 - np.exp(-radius * radius * 8) * 0.19
    height += rings * 0.2
save("painted_oak", wood, height, 3.4)

# Lime wash: irregular wide brush patches over fine porous lime grains.
plaster_cloud = cloud(29, (2, 5, 12, 37), (1.0, 0.5, 0.3, 0.12))
pores = np.maximum(cloud(129, (29, 47, 69, 99), (1.0, 0.7, 0.4, 0.2)) - 1.45, 0)
plaster = 0.932 + plaster_cloud * 0.022 - pores * 0.034
save("painted_limewash", plaster, plaster_cloud * 0.11 - pores * 0.09, 1.2)

# Handcut stone: weathered broad facets, tiny pitting and faint warm mineral bands.
stone_cloud = cloud(47, (2, 6, 17, 41), (1.0, 0.64, 0.28, 0.10))
veins = np.maximum(np.sin((x * 3 + y * 2) * math.tau + stone_cloud * 0.35) - 0.72, 0)
stone = 0.895 + stone_cloud * 0.039 - veins * 0.040
save("painted_stone", stone, stone_cloud * 0.24 - veins * 0.12, 2.1)

# Slate: overlapping painted broad streaks with little chips, avoiding noisy grain.
slate_cloud = cloud(70, (2, 6, 15, 43), (1.0, 0.54, 0.16, 0.08))
slate_streak = np.sin((x * 9 + y * 2) * math.tau + np.sin(y * math.tau * 4) * 0.6)
slate = 0.914 + slate_cloud * 0.036 + slate_streak * 0.012
save("painted_slate", slate, slate_cloud * 0.20 + slate_streak * 0.035, 1.6)
print(f"Wrote 8 original architecture texture maps to {OUT}")
