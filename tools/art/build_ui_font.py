"""Build the bundled OFL town font from Google Fonts' NotoSansSC[wght].ttf.

Usage: python tools/art/build_ui_font.py /path/to/NotoSansSC.ttf
Requires fonttools==4.60.1. The resulting font is committed; Godot needs no Python.
"""

import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    characters = set(chr(i) for i in range(32, 256))
    # GB2312 includes the 6,763 common simplified Chinese characters. Also keep
    # all characters currently used by the game, arrows, punctuation and icons.
    for first in range(0xA1, 0xF8):
        for second in range(0xA1, 0xFF):
            try:
                characters.update(bytes((first, second)).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    for start, stop in [(0x2000, 0x2070), (0x2190, 0x2200), (0x2500, 0x2700), (0x3000, 0x3040), (0xFF00, 0xFFF0)]:
        characters.update(chr(i) for i in range(start, stop))
    for script in (root / "game/scripts").rglob("*.gd"):
        characters.update(script.read_text(encoding="utf-8"))
    font = TTFont(args.source)
    instantiateVariableFont(font, {"wght": 400}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes={ord(character) for character in characters})
    subsetter.subset(font)
    names = {1: "Breeze Town UI", 2: "Regular", 3: "BreezeTownUI-Regular-1.0", 4: "Breeze Town UI Regular", 6: "BreezeTownUI-Regular", 16: "Breeze Town UI", 17: "Regular"}
    for record in list(font["name"].names):
        if record.nameID in names:
            font["name"].setName(names[record.nameID], record.nameID, record.platformID, record.platEncID, record.langID)
    destination = root / "game/resources/fonts/breeze_town_ui.ttf"
    destination.parent.mkdir(parents=True, exist_ok=True)
    font.save(destination)
    print(f"Saved {destination}: {destination.stat().st_size:,} bytes, {len(font.getBestCmap())} characters")


if __name__ == "__main__":
    main()
