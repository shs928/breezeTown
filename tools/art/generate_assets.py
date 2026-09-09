#!/usr/bin/env python3
"""ART-01 素材生成器（原创、程序化）。

用标准库直接编码 PNG，不依赖第三方库。生成的所有像素图均为本项目原创，
色板取自 docs/ui/art-direction.md；生成结果与 generator 脚本一并入库，
许可登记见 docs/art/assets-license.md。

用法：python3 tools/art/generate_assets.py
输出：game/assets/generated/*.png
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets", "generated")

# ---- 色板（docs/ui/art-direction.md） ----
GRASS = (123, 182, 98)
GRASS_DARK = (94, 154, 76)
SOIL = (139, 106, 74)
SOIL_TILLED = (110, 82, 56)
SOIL_WET = (90, 66, 48)
PATH = (201, 183, 154)
WOOD = (176, 130, 79)
ROOF = (160, 82, 63)
OUTLINE = (43, 43, 51)
HILIGHT = (242, 208, 107)
WARN = (217, 101, 75)
OK = (111, 191, 115)
WATER = (95, 168, 199)
WHITE = (245, 239, 227)

AVATARS = [
    ((224, 92, 92), (242, 179, 179)),   # 1 红
    ((78, 127, 209), (169, 194, 234)),  # 2 蓝
    ((78, 168, 107), (169, 216, 183)),  # 3 绿
    ((217, 162, 78), (238, 211, 166)),  # 4 黄
]


def write_png(path, width, height, pixels):
    """pixels: list of rows, each row list of (r,g,b,a)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))
    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def blank(w, h, color=(0, 0, 0, 0)):
    return [[color for _ in range(w)] for _ in range(h)]


def rect(px, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(len(px), y1)):
        for x in range(max(0, x0), min(len(px[0]), x1)):
            px[y][x] = color


def put(px, x, y, color):
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = color


def outline_rect(px, x0, y0, x1, y1, color):
    for x in range(x0, x1):
        put(px, x, y0, color)
        put(px, x, y1 - 1, color)
    for y in range(y0, y1):
        put(px, x0, y, color)
        put(px, x1 - 1, y, color)


def circle(px, cx, cy, radius, color):
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
                put(px, x, y, color)


def _a(color):
    return (color[0], color[1], color[2], 255)


# ---------- 地块 ----------

def gen_tiles():
    size = 32
    for name, base, dark in [
        ("tile_grass", GRASS, GRASS_DARK),
        ("tile_soil", SOIL, SOIL_TILLED),
        ("tile_soil_tilled", SOIL_TILLED, SOIL_WET),
        ("tile_soil_wet", SOIL_WET, (60, 44, 32)),
        ("tile_path", PATH, (176, 158, 132)),
    ]:
        px = blank(size, size)
        rect(px, 0, 0, size, size, _a(base))
        # 原创纹理：交错短划，避免纯色
        for y in range(0, size, 4):
            for x in range((y // 4 % 2) * 4, size, 8):
                rect(px, x, y, x + 2, y + 1, _a(dark))
        write_png(os.path.join(OUT_DIR, name + ".png"), size, size, px)

    # 阻挡格（树篱）
    px = blank(size, size)
    rect(px, 0, 0, size, size, _a(GRASS_DARK))
    circle(px, 10, 12, 7, _a((74, 124, 60)))
    circle(px, 21, 16, 8, _a((74, 124, 60)))
    circle(px, 15, 22, 6, _a((94, 154, 76)))
    write_png(os.path.join(OUT_DIR, "tile_blocked.png"), size, size, px)

    # 设施区（木台）
    px = blank(size, size)
    rect(px, 0, 0, size, size, _a(PATH))
    rect(px, 2, 2, size - 2, size - 2, _a(WOOD))
    outline_rect(px, 2, 2, size - 2, size - 2, _a(OUTLINE))
    write_png(os.path.join(OUT_DIR, "tile_facility.png"), size, size, px)

    # 出生点
    px = blank(size, size)
    rect(px, 0, 0, size, size, _a((153, 184, 128)))
    circle(px, 16, 16, 9, _a(WHITE))
    circle(px, 16, 16, 6, _a(HILIGHT))
    write_png(os.path.join(OUT_DIR, "tile_spawn.png"), size, size, px)


# ---------- 角色（4 色，朝向一致） ----------

def gen_avatars():
    size = 32
    for index, (main, light) in enumerate(AVATARS, start=1):
        px = blank(size, size)
        # 身体
        rect(px, 9, 14, 23, 27, _a(main))
        outline_rect(px, 9, 14, 23, 27, _a(OUTLINE))
        # 头
        rect(px, 10, 5, 22, 15, _a(light))
        outline_rect(px, 10, 5, 22, 15, _a(OUTLINE))
        # 帽子剪影：按槽位不同形状，保证色盲可辨
        if index == 1:
            rect(px, 8, 4, 24, 8, _a(main))          # 宽檐帽
        elif index == 2:
            rect(px, 12, 2, 20, 7, _a(main))         # 高帽
        elif index == 3:
            circle(px, 16, 5, 6, _a(main))           # 圆帽
        else:
            rect(px, 10, 3, 22, 6, _a(main))
            rect(px, 22, 3, 26, 8, _a(main))         # 侧羽
        # 眼睛
        put(px, 13, 10, _a(OUTLINE))
        put(px, 19, 10, _a(OUTLINE))
        # 手
        rect(px, 5, 16, 9, 21, _a(light))
        rect(px, 23, 16, 27, 21, _a(light))
        write_png(os.path.join(OUT_DIR, "avatar_%d.png" % index), size, size, px)


# ---------- 作物阶段 ----------

def gen_crops():
    size = 32
    specs = [
        ("crop_radish", [(0, "sown"), (1, "mature")]),
        ("crop_potato", [(0, "sown"), (1, "seedling"), (2, "mature")]),
        ("crop_wheat", [(0, "sown"), (1, "seedling"), (2, "mature")]),
        ("crop_carrot", [(0, "sown"), (1, "seedling"), (2, "growing"), (3, "mature")]),
        ("crop_strawberry", [(0, "sown"), (1, "seedling"), (2, "growing"), (4, "mature")]),
    ]
    for name, stages in specs:
        for day, stage in stages:
            px = blank(size, size)
            # 土壤底座
            rect(px, 4, 20, 28, 30, _a(SOIL_WET))
            if stage == "sown":
                circle(px, 16, 24, 4, _a((120, 92, 66)))
                put(px, 16, 21, _a(HILIGHT))
            elif stage == "seedling":
                rect(px, 15, 16, 17, 25, _a((78, 138, 68)))
                circle(px, 13, 16, 3, _a(OK))
                circle(px, 19, 16, 3, _a(OK))
            elif stage == "growing":
                rect(px, 15, 12, 17, 25, _a((78, 138, 68)))
                circle(px, 12, 15, 4, _a(OK))
                circle(px, 20, 14, 4, _a(OK))
                circle(px, 16, 10, 3, _a(OK))
            else:  # mature：按作物加不同果实/穗
                if name == "crop_radish":
                    circle(px, 16, 18, 6, _a((214, 84, 84)))
                    rect(px, 14, 8, 18, 16, _a(OK))
                    circle(px, 12, 10, 3, _a(OK))
                    circle(px, 20, 10, 3, _a(OK))
                elif name == "crop_potato":
                    circle(px, 12, 16, 5, _a((176, 132, 92)))
                    circle(px, 20, 17, 5, _a((176, 132, 92)))
                    rect(px, 14, 9, 18, 16, _a(OK))
                    circle(px, 11, 10, 3, _a(OK))
                    circle(px, 21, 10, 3, _a(OK))
                elif name == "crop_wheat":
                    for x in (12, 16, 20):
                        rect(px, x, 8, x + 2, 24, _a((214, 178, 78)))
                        circle(px, x + 1, 9, 3, _a(HILIGHT))
                elif name == "crop_carrot":
                    circle(px, 16, 19, 5, _a((230, 130, 52)))
                    rect(px, 14, 8, 18, 16, _a(OK))
                    circle(px, 11, 11, 3, _a(OK))
                    circle(px, 21, 11, 3, _a(OK))
                else:  # strawberry
                    circle(px, 13, 17, 4, _a((224, 92, 92)))
                    circle(px, 20, 18, 4, _a((224, 92, 92)))
                    rect(px, 14, 9, 18, 16, _a(OK))
                    circle(px, 11, 11, 3, _a(OK))
                    circle(px, 21, 11, 3, _a(OK))
                # 成熟高光轮廓（不只靠颜色区分）
                circle(px, 16, 14, 11, (242, 208, 107, 60))
            write_png(os.path.join(OUT_DIR, "%s_%s.png" % (name, stage)), size, size, px)


# ---------- 工具与图标 ----------

def gen_tools():
    size = 32
    # 锄头
    px = blank(size, size)
    rect(px, 14, 6, 18, 28, _a(WOOD))
    rect(px, 8, 4, 24, 9, _a((150, 150, 158)))
    outline_rect(px, 8, 4, 24, 9, _a(OUTLINE))
    write_png(os.path.join(OUT_DIR, "tool_hoe.png"), size, size, px)
    # 水壶
    px = blank(size, size)
    rect(px, 8, 14, 24, 27, _a(WATER))
    outline_rect(px, 8, 14, 24, 27, _a(OUTLINE))
    rect(px, 20, 8, 24, 14, _a(WATER))
    rect(px, 4, 16, 9, 20, _a(WATER))
    write_png(os.path.join(OUT_DIR, "tool_watering_can.png"), size, size, px)
    # 空手
    px = blank(size, size)
    circle(px, 16, 18, 8, _a((238, 211, 166)))
    outline_rect(px, 9, 11, 23, 26, _a(OUTLINE))
    write_png(os.path.join(OUT_DIR, "tool_hand.png"), size, size, px)
    # 种子包
    px = blank(size, size)
    rect(px, 9, 8, 23, 26, _a((214, 178, 78)))
    outline_rect(px, 9, 8, 23, 26, _a(OUTLINE))
    circle(px, 16, 17, 4, _a((120, 92, 66)))
    write_png(os.path.join(OUT_DIR, "icon_seed.png"), size, size, px)
    # 金币
    px = blank(size, size)
    circle(px, 16, 16, 10, _a(HILIGHT))
    circle(px, 16, 16, 7, _a((214, 178, 78)))
    write_png(os.path.join(OUT_DIR, "icon_coin.png"), size, size, px)
    # 仓库 / 建设板 / 榜单 图标
    for name, color in [("icon_storage", WOOD), ("icon_project", ROOF), ("icon_leaderboard", (150, 150, 158))]:
        px = blank(size, size)
        rect(px, 6, 10, 26, 26, _a(color))
        outline_rect(px, 6, 10, 26, 26, _a(OUTLINE))
        rect(px, 6, 6, 26, 11, _a(ROOF))
        write_png(os.path.join(OUT_DIR, name + ".png"), size, size, px)


# ---------- 建筑（商店 / 仓库 / 纪念碑） ----------

def gen_buildings():
    w, h = 64, 64
    for name, body, roof in [
        ("building_shop", WOOD, ROOF),
        ("building_storage", (150, 120, 88), ROOF),
        ("building_monument", (170, 170, 178), HILIGHT),
    ]:
        px = blank(w, h)
        rect(px, 6, 26, 58, 58, _a(body))
        outline_rect(px, 6, 26, 58, 58, _a(OUTLINE))
        # 屋顶
        for i in range(22):
            rect(px, 6 + i, 26 - i, 58 - i, 27 - i, _a(roof))
        # 门窗
        rect(px, 26, 40, 38, 58, _a(SOIL_WET))
        outline_rect(px, 26, 40, 38, 58, _a(OUTLINE))
        rect(px, 14, 34, 22, 42, _a(WATER))
        rect(px, 42, 34, 50, 42, _a(WATER))
        write_png(os.path.join(OUT_DIR, name + ".png"), w, h, px)


def main():
    gen_tiles()
    gen_avatars()
    gen_crops()
    gen_tools()
    gen_buildings()
    files = sorted(os.listdir(OUT_DIR))
    print("generated %d assets in %s" % (len(files), os.path.relpath(OUT_DIR)))
    for f in files:
        print("  " + f)


if __name__ == "__main__":
    main()
