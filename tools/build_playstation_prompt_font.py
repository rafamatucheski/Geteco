"""Build the four inline PlayStation icons from Kenney Input Prompts 1.5A (CC0).

Usage: python tools/build_playstation_prompt_font.py PATH_TO_UNPACKED_PACK
Requires fonttools. Source: https://kenney.nl/assets/input-prompts
Only the four existing prompt characters are mapped; ordinary text is untouched.
"""

import argparse
import shutil
from pathlib import Path

from fontTools import subset
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    args = parser.parse_args()
    destination = Path(__file__).resolve().parents[1] / "assets/fonts/input_prompts"
    destination.mkdir(parents=True, exist_ok=True)
    source = args.pack / "PlayStation Series/Fonts/kenney_input_playstation_series.ttf"
    font = TTFont(source, recalcTimestamp=False)
    # Kenney's outlined circular button artwork, indexed by the pack's map.txt.
    mapping = {0x2715: 0xE04C, 0x25CB: 0xE042, 0x25A1: 0xE052, 0x25B3: 0xE054}
    original_cmap = font.getBestCmap()
    glyphs = {codepoint: original_cmap[original] for codepoint, original in mapping.items()}
    options = subset.Options()
    options.hinting = False
    options.recalc_timestamp = False
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=mapping.values())
    subsetter.subset(font)
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap = glyphs.copy()
    # Normalize the pack's half-em icons to readable inline buttons. Align with
    # Barlow's cap height without increasing the surrounding text's line height.
    glyph_set = font.getGlyphSet()
    replacements = {}
    for name in glyphs.values():
        pen = TTGlyphPen(None)
        glyph_set[name].draw(TransformPen(pen, (0.86, 0, 0, 0.86, 25, -70)))
        replacements[name] = pen.glyph()
    for name, glyph in replacements.items():
        font["glyf"][name] = glyph
        font["hmtx"][name] = (930, 42)
    font["head"].unitsPerEm = 1000
    font["hhea"].ascent = 1000
    font["hhea"].descent = -200
    font["hhea"].lineGap = 0
    font["OS/2"].sTypoAscender = 1000
    font["OS/2"].sTypoDescender = -200
    font["OS/2"].sTypoLineGap = 0
    font["OS/2"].usWinAscent = 1000
    font["OS/2"].usWinDescent = 200
    for name_id, value in {1: "Kenney PlayStation Prompts", 2: "Regular", 4: "Kenney PlayStation Prompts", 6: "KenneyPlayStationPrompts"}.items():
        font["name"].setName(value, name_id, 3, 1, 0x409)
    font.save(destination / "KenneyPlayStation.ttf")
    shutil.copyfile(args.pack / "License.txt", destination / "License.txt")
    print("Created", destination / "KenneyPlayStation.ttf")


if __name__ == "__main__":
    main()
