"""Build reusable HUD textures from the supplied illustration, without baked text.

Run with the bundled Pillow Python runtime. Source figures are isolated from their
sample slots; live counts, hotkeys, dates, health and money belong to the HUD.
"""
from collections import deque
from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/resources/ui"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = Image.open(ROOT / "docs/art/reference/ui-hud.png").convert("RGBA")
RNG = random.Random(1616)


def clear_black(image):
    image = image.copy()
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if max(r, g, b) < 38:
                pixels[x, y] = (r, g, b, 0)
    return image


def texture(size, base, wood=False):
    image = Image.new("RGBA", size)
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            noise = RNG.gauss(0, 0.8) + math.sin(x * .13 + y * .075)
            if wood:
                noise += 2.2 * math.sin(y * .22 + math.sin(x * .023))
            else:
                noise += 1.7 * math.sin(y / size[1] * math.pi)
            pixels[x, y] = tuple(max(0, min(255, round(c + noise))) for c in base) + (255,)
    return image


def heal(image, bounds, base, feather=5, wood=False):
    """Feather only the perimeter so sample text is fully replaced in the middle."""
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle(bounds, radius=feather, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather / 2))
    replacement = texture(image.size, base, wood)
    return Image.composite(replacement, image, mask)


def save(name, image):
    image.save(OUT / f"{name}.png")


status = clear_black(SOURCE.crop((20, 23, 433, 154)))
status = heal(status, (113, 14, 393, 116), (244, 213, 163), 5)
save("status", status)
save("portrait", clear_black(SOURCE.crop((39, 40, 135, 140))))

paper = clear_black(SOURCE.crop((1305, 746, 1653, 833)))
paper = heal(paper, (24, 15, 325, 72), (248, 227, 192), 5)
save("paper", paper)

wood = clear_black(SOURCE.crop((443, 747, 1228, 883)))
wood = heal(wood, (24, 27, 756, 120), (158, 103, 54), 5, wood=True)
save("wood", wood)

# Preserve the hand-painted edge, replacing the entire example tool AND its number.
slot = SOURCE.crop((579, 779, 660, 862))
slot = heal(slot, (6, 7, 75, 78), (237, 210, 163), 3)
save("slot", slot)

# Use the separate coin plaque from the reference instead of stretching a toolbar.
money = clear_black(SOURCE.crop((1375, 113, 1655, 183)))
money = heal(money, (83, 12, 260, 58), (113, 68, 37), 4, wood=True)
save("money", money)
save("coin", clear_black(SOURCE.crop((1390, 121, 1449, 177))))


def isolate_icon(box, silhouette=None, cleanup_can=False):
    """Flood out parchment, then retain the tool, discarding separate sample digits."""
    image = SOURCE.crop(box)
    width, height = image.size
    pixels = image.load()
    background = set()
    queue = deque()

    def is_paper(x, y):
        r, g, b, _ = pixels[x, y]
        return r > 174 and g > 137 and b > 91 and r - g < 73 and g - b < 78

    for y in range(height):
        for x in range(width):
            if (x in (0, width - 1) or y in (0, height - 1)) and is_paper(x, y):
                background.add((x, y))
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in background and is_paper(nx, ny):
                background.add((nx, ny))
                queue.append((nx, ny))
    remaining = {(x, y) for y in range(height) for x in range(width)} - background
    components = []
    while remaining:
        seed = remaining.pop()
        component = {seed}
        queue.append(seed)
        while queue:
            x, y = queue.popleft()
            for neighbour in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    component.add(neighbour)
                    queue.append(neighbour)
        components.append(component)
    subject = max(components, key=len)
    alpha = Image.new("L", image.size)
    a = alpha.load()
    for x, y in subject:
        a[x, y] = 255
    if silhouette:
        alpha = Image.new("L", image.size)
        ImageDraw.Draw(alpha).polygon(silhouette, fill=255)
    if cleanup_can:
        draw = ImageDraw.Draw(alpha)
        draw.rectangle((0, 0, 4, height), fill=0)
        draw.rectangle((0, 0, 22, 12), fill=0)
    image.putalpha(alpha)
    image = image.crop(image.getbbox())
    image.thumbnail((60, 58), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (68, 64))
    canvas.alpha_composite(image, ((68 - image.width) // 2, (64 - image.height) // 2))
    return canvas


for name, box in {
    "can": (493, 789, 573, 851),
    "hoe": (585, 789, 649, 847),
    "axe": (674, 790, 735, 847),
    "seed": (846, 790, 905, 845),
}.items():
    silhouette = [(16, 0), (53, 6), (55, 13), (54, 52), (43, 55), (5, 53), (1, 48), (3, 43), (6, 28), (16, 10)] if name == "seed" else None
    save(name, isolate_icon(box, silhouette, name == "can"))

# Tools absent from the reference get distinct silhouettes; no reused seed bag or hoe.
for name in ("sword", "hand", "pickaxe", "sapling", "fence", "ration"):
    image = Image.new("RGBA", (136, 128))
    draw = ImageDraw.Draw(image)
    if name == "sword":
        draw.polygon([(46, 92), (58, 102), (114, 20), (106, 8), (92, 14)], fill="#7d9aa7", outline="#514d43", width=3)
        draw.polygon([(58, 92), (106, 16), (96, 18), (50, 84)], fill="#c4d5d8")
        draw.line([(34, 74), (72, 104)], fill="#775138", width=14)
        draw.line([(32, 110), (52, 86)], fill="#9c6a3d", width=16)
        draw.ellipse((22, 102, 40, 120), fill="#d5ad51", outline="#67503b", width=3)
    elif name == "pickaxe":
        draw.line([(33, 110), (83, 40)], fill="#705039", width=17)
        draw.line([(33, 107), (80, 43)], fill="#c8975a", width=10)
        draw.polygon([(27, 37), (61, 24), (82, 24), (106, 39), (122, 62), (96, 48), (78, 44), (53, 44), (19, 60)], fill="#69828c", outline="#485458", width=4)
        draw.line([(29, 39), (65, 29), (81, 29), (104, 42)], fill="#c1d0cf", width=5)
        draw.polygon([(69, 24), (86, 28), (85, 50), (66, 45)], fill="#8d724d", outline="#584733", width=3)
    elif name == "sapling":
        draw.ellipse((28, 93, 111, 114), fill="#aa7542", outline="#775333", width=3)
        draw.line([(67, 99), (66, 46), (89, 26)], fill="#75834d", width=7)
        draw.ellipse((22, 33, 68, 63), fill="#7eaf54", outline="#557744", width=3)
        draw.ellipse((68, 19, 113, 45), fill="#8fbd5b", outline="#587b41", width=3)
        draw.line([(31, 43), (64, 55)], fill="#b4d37e", width=3)
        draw.line([(75, 37), (102, 27)], fill="#c3dc91", width=3)
        draw.ellipse((32, 97, 59, 105), fill="#c28d4e")
    elif name == "fence":
        for x in (22, 91):
            draw.polygon([(x, 27), (x + 7, 17), (x + 20, 22), (x + 20, 110), (x, 113)], fill="#bb8a51", outline="#755233", width=3)
            draw.line([(x + 5, 29), (x + 5, 102)], fill="#dcb479", width=3)
        for y in (42, 77):
            draw.polygon([(16, y), (117, y - 4), (117, y + 13), (16, y + 17)], fill="#c99a61", outline="#785635", width=3)
            draw.line([(24, y + 3), (108, y)], fill="#e5bf84", width=3)
    elif name == "ration":
        draw.rounded_rectangle((24, 35, 116, 100), radius=26, fill="#c48b45", outline="#78512e", width=4)
        draw.ellipse((25, 29, 113, 88), fill="#deb773", outline="#986c3c", width=3)
        for x in (47, 68, 88):
            draw.line([(x, 45), (x - 8, 66)], fill="#f3d797", width=7)
    else:
        draw.rounded_rectangle((46, 48, 94, 102), radius=16, fill="#deb780", outline="#806147", width=4)
        for i in range(4):
            draw.rounded_rectangle((42 + i * 14, 20 + (i % 2) * 6, 60 + i * 14, 76), radius=10, fill="#efd3a0", outline="#806147", width=4)
        draw.rounded_rectangle((26, 64, 54, 94), radius=10, fill="#efd3a0", outline="#806147", width=4)
        draw.rounded_rectangle((46, 96, 90, 118), radius=6, fill="#839b6e", outline="#5d684a", width=4)
    save(name, image.resize((68, 64), Image.Resampling.LANCZOS))

print(f"UI textures written: {OUT}")
