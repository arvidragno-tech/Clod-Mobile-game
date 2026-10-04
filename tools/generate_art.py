#!/usr/bin/env python3
"""Regenerates every pixel-art asset of UNDERCITY: RIPPER.

    python3 tools/generate_art.py            # everything
    python3 tools/generate_art.py chars ui   # only some groups

Groups: palette, chars, cyberware, tools, regions, env, ui.
Art spec: docs/ART_BIBLE.md. Requires Pillow.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.art import palette, characters2, cyberware_art, tools_art, regions, environments, ui_art  # noqa: E402
from tools.art.lib import ROOT  # noqa: E402

GROUPS = {
    "palette": lambda: palette.export_json(os.path.join(ROOT, "data", "palettes.json")),
    "chars": characters2.generate,
    "cyberware": cyberware_art.generate,
    "tools": tools_art.generate,
    "regions": regions.generate,
    "env": environments.generate,
    "ui": ui_art.generate,
}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(GROUPS)
    for g in wanted:
        GROUPS[g]()
