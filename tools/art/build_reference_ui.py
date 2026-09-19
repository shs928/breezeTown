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
# Drawn at 2x then downscaled for clean edges; shared warm ink outline keeps the row coherent.
INK = "#4d4337"


def start_icon():
    image = Image.new("RGBA", (272, 256))
    return image, ImageDraw.Draw(image)


def finish_icon(image):
    return image.resize((68, 64), Image.Resampling.LANCZOS)


for name in ("sword", "hand", "pickaxe", "sapling", "fence", "ration", "rod"):
    image, draw = start_icon()
    if name == "rod":
        # 钓鱼竿（LIFE-01）：斜置竹竿 + 线轮 + 垂线与鱼钩。
        draw.line([(52, 214), (232, 44)], fill="#a9834f", width=18)
        draw.line([(70, 216), (226, 58)], fill="#c8a369", width=7)
        draw.ellipse((96, 150, 150, 196), fill="#8a6f4a", outline="#5f4a33", width=7)
        draw.ellipse((114, 162, 132, 180), fill="#c9c2b4")
        draw.line([(226, 50), (218, 96), (224, 150)], fill="#e8e4da", width=5, joint="curve")
        draw.arc((208, 140, 240, 168), 90, 300, fill="#c9c2b4", width=5)
        draw.line([(196, 128), (232, 92)], fill="#a9834f", width=8)
    elif name == "sword":
        # 握柄与缠绳
        draw.line([(108, 214), (152, 166)], fill="#775138", width=32, joint="curve")
        for t in range(3):
            f = 0.25 + t * 0.25
            x = 108 + (152 - 108) * f
            y = 214 + (166 - 214) * f
            draw.line([(x - 12, y + 12), (x + 12, y - 12)], fill="#9c6a3d", width=6)
        draw.ellipse((84, 210, 132, 252), fill="#d5ad51", outline="#67503b", width=7)
        draw.ellipse((96, 222, 110, 234), fill="#f0d68a")
        draw.polygon([(118, 198), (150, 168), (214, 224), (182, 252)], fill="#d5ad51", outline="#67503b", width=7)
        # 剑身：深边 + 亮面 + 高光
        draw.polygon([(148, 192), (184, 224), (236, 60), (206, 32)], fill="#7d9aa7", outline=INK, width=7)
        draw.polygon([(158, 194), (192, 220), (226, 70), (208, 46)], fill="#c4d5d8")
        draw.line([(168, 198), (218, 62)], fill="#eef5f5", width=8)
    elif name == "pickaxe":
        draw.line([(66, 220), (166, 80)], fill="#705039", width=34, joint="curve")
        draw.line([(66, 214), (162, 84)], fill="#c8975a", width=20, joint="curve")
        draw.line([(70, 204), (154, 92)], fill="#e2bc7f", width=7, joint="curve")
        draw.polygon([(54, 74), (122, 48), (164, 48), (212, 78), (244, 124), (192, 96), (156, 88), (106, 88), (38, 120)], fill="#69828c", outline="#485458", width=8)
        draw.line([(60, 80), (130, 58), (164, 58), (206, 84)], fill="#c1d0cf", width=10, joint="curve")
        draw.polygon([(138, 48), (172, 56), (170, 100), (132, 90)], fill="#8d724d", outline="#584733", width=6)
    elif name == "sapling":
        draw.ellipse((56, 186, 222, 230), fill="#aa7542", outline="#775333", width=6)
        draw.ellipse((72, 194, 128, 212), fill="#c28d4e")
        draw.line([(134, 200), (132, 92), (178, 54)], fill="#75834d", width=14, joint="curve")
        draw.line([(138, 192), (136, 100)], fill="#9db06a", width=5, joint="curve")
        draw.ellipse((44, 66, 136, 126), fill="#7eaf54", outline="#557744", width=6)
        draw.line([(56, 88), (122, 108)], fill="#b4d37e", width=5)
        draw.ellipse((136, 38, 226, 90), fill="#8fbd5b", outline="#587b41", width=6)
        draw.line([(148, 60), (208, 46)], fill="#c3dc91", width=5)
        draw.ellipse((152, 18, 194, 54), fill="#a5cd74", outline="#587b41", width=5)
    elif name == "fence":
        for x in (44, 182):
            draw.polygon([(x, 54), (x + 14, 34), (x + 40, 44), (x + 40, 220), (x, 226)], fill="#bb8a51", outline="#755233", width=7)
            draw.line([(x + 10, 58), (x + 10, 204)], fill="#dcb479", width=6)
        for y in (84, 154):
            draw.polygon([(32, y), (234, y - 8), (234, y + 26), (32, y + 34)], fill="#c99a61", outline="#785635", width=7)
            draw.line([(48, y + 6), (216, y - 2)], fill="#e5bf84", width=6)
    elif name == "ration":
        draw.rounded_rectangle((48, 74, 232, 202), radius=52, fill="#c48b45", outline="#78512e", width=8)
        draw.ellipse((52, 56, 226, 172), fill="#deb773", outline="#986c3c", width=6)
        for x in (94, 136, 176):
            draw.line([(x, 90), (x - 16, 132)], fill="#f3d797", width=14, joint="curve")
        draw.arc((74, 72, 150, 128), 200, 300, fill="#f6e3ae", width=8)
    else:
        # 拳头：四指圆段 + 掌 + 侧向拇指 + 绿袖口。
        for i in range(4):
            x0 = 84 + i * 28
            top = 40 + (i % 2) * 12
            draw.rounded_rectangle((x0, top, x0 + 28, 152), radius=13, fill="#f0d6a2", outline="#806147", width=6)
            draw.arc((x0 + 5, top + 4, x0 + 23, top + 22), 180, 330, fill="#f9e7c0", width=4)
        draw.rounded_rectangle((76, 122, 208, 198), radius=24, fill="#e6c78e", outline="#806147", width=7)
        draw.ellipse((48, 140, 104, 204), fill="#f0d6a2", outline="#806147", width=6)
        draw.rounded_rectangle((92, 192, 180, 238), radius=20, fill="#839b6e", outline="#5d684a", width=7)
        draw.line([(102, 204), (166, 204)], fill="#a7bb90", width=6)
    save(name, finish_icon(image))

print(f"UI textures written: {OUT}")
