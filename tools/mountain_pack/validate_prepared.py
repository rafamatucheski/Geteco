"""Lightweight syntax/reference checks; never starts Godot, dotnet or a game test."""
from __future__ import annotations

import ast
import hashlib
import json
import re
from pathlib import Path

from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    sources: list[Path] = []
    for folder in ("activities/mountain_story", "activities/mountain_downhill",
                   "activities/mountain_jeep", "world/mountain_jeep"):
        sources.extend((ROOT / folder).glob("*.gd"))
    sources.extend((ROOT / "systems/campaign").glob("Mountain*Progress.gd"))
    sources.extend((ROOT / "tests").glob("test_mountain_*progress.gd"))
    sources.extend((ROOT / "tests").glob("test_mountain_*runtime.gd"))
    sources.append(ROOT / "tests/test_mountain_jeep_integration.gd")
    sources.extend(ROOT / name for name in (
        "runtime/MountainActivities.gd", "systems/campaign/MountainPackState.gd",
        "tests/test_mountain_pack_state.gd", "tests/test_mountain_jeep_course.gd"))
    sources = sorted(set(sources))
    integration = ROOT / "evidence/mountain-pack-20261005/integration"
    manifest = json.loads((integration / "manifest.json").read_text(encoding="utf-8"))
    previews: list[Path] = []
    for entry in manifest["files"]:
        source = ROOT / entry["path"]
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual != entry["source_sha256"]:
            raise ValueError(f"Shared source changed; rebuild preview: {entry['path']}")
        preview = integration / "preview" / (entry["path"] + ".txt")
        if hashlib.sha256(preview.read_bytes()).hexdigest() != entry["preview_sha256"]:
            raise ValueError(f"Preview differs from manifest: {entry['path']}")
        previews.append(preview)
    references = 0
    for source in sources + previews:
        content = source.read_text(encoding="utf-8-sig")
        parser.parse(content, gather_metadata=True)
        for path in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', content):
            if not (ROOT / path).is_file():
                raise ValueError(f"Missing resource {path} referenced by {source.relative_to(ROOT)}")
            references += 1
    for script in Path(__file__).parent.glob("*.py"):
        ast.parse(script.read_text(encoding="utf-8"), filename=str(script))
    dialogues = json.loads((ROOT / "data/campaign/mountain-story-dialogue.json").read_text(encoding="utf-8-sig"))
    json.loads((Path(__file__).parent / "integration_edits.json").read_text(encoding="utf-8-sig"))
    print(json.dumps({"new_gd_scripts_parsed": len(sources),
                      "shared_previews_parsed": len(previews),
                      "resource_references_found": references,
                      "dialogue_events": len(dialogues),
                      "shared_source_hashes_unchanged": True,
                      "godot_executed": False, "software_tests_executed": False,
                      "runtime_visual_performance_validated": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
