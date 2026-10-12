"""Reviewable source inventory, not a claim that every rendered pixel was inspected.

Catalog/format/export correctness is checked by verify_localization_catalogs.py.
This inventory finds natural-language literals, including scenes and source data,
and keeps unmatched candidates visible rather than treating heuristics as proof.
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ("ui", "runtime", "gameplay", "activities", "systems", "data/campaign",
         "data/catalogs", "world", "audio", "cutscenes")
QUOTED = re.compile(r'"(?:[^"\\]|\\.)*"')
FORMAT = re.compile(r"(?<!%)%(?!%)[-+0-9.#]*[sdif]")


def catalog():
    pairs = {}
    for path in sorted((ROOT / "data/localization").glob("*.en.json")):
        pairs.update(json.loads(path.read_text(encoding="utf-8-sig")))
    speech = json.loads((ROOT / "data/dialogue/english-voice-translations.json").read_text(encoding="utf-8-sig"))
    pairs.update({a: b for a, b in speech.items() if isinstance(b, str)})
    return pairs


def inventory():
    result = defaultdict(list)
    for folder in ROOTS:
        for path in (ROOT / folder).rglob("*"):
            if path.suffix not in (".gd", ".tscn", ".tres"):
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
                if line.lstrip().startswith(("#", ";")):
                    continue
                for match in QUOTED.finditer(line):
                    try:
                        source = json.loads(match[0])
                    except ValueError:
                        continue
                    if not re.search(r"[A-Za-zÀ-ÿ]", source) or any(x in source for x in ("res://", "user://", "http://", "https://")):
                        continue
                    if not (re.search(r"[À-ÿ]", source) or " " in source or (source.isupper() and len(source) > 3)):
                        continue
                    result[source].append({"file": path.relative_to(ROOT).as_posix(), "line": number,
                                           "diagnostic": bool(re.search(r"\b(print|print_debug|push_error|push_warning|assert|check)\s*\(", line))})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="output/localization/source-inventory.json")
    args = parser.parse_args()
    pairs = catalog()
    targets = set(pairs.values())
    categories = defaultdict(list)
    for source, locations in inventory().items():
        if source in pairs:
            category = "catalog_source"
        elif source in targets:
            category = "catalog_target"
        elif all(row["diagnostic"] or re.search(r"(?:Validation|Capture|Review|Fixture|Contract|Test|Probe)\.gd$|/(?:test_|validate_|capture_)", row["file"]) for row in locations):
            category = "diagnostic_or_fixture"
        elif re.fullmatch(r"[Mm][0-9 .,+\-A-Za-z]+", source) and re.search(r"[0-9]", source):
            category = "vector_path"
        elif not re.search(r"[A-Za-zÀ-ÿ]{3}", FORMAT.sub("", source).replace("FPS", "").replace("RPM", "").replace("RAGE", "").replace("km/h", "")):
            category = "format_or_symbol"
        else:
            # Includes proper names and composed strings: preserve them for review.
            # Never silently classify an unknown sentence as translated.
            category = "review_candidate"
        categories[category].append({"source": source, "locations": locations})
    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {"scope": list(ROOTS),
              "limits": "Literal inventory; composed strings, identifiers, proper names and existing bilingual branches require review. JSON dialogue pairs are covered by catalog validation. Does not inspect rasterized text, footage or exported builds.",
              "counts": {key: len(rows) for key, rows in categories.items()},
              "entries": dict(categories)}
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["counts"]))
    print(output)


if __name__ == "__main__":
    main()
