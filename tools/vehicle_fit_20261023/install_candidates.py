"""Install reviewed candidates only while the captured production sources match."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/vehicle-fit-20261023"
GROUPS = {
    "motorcycles": ["bike_sport", "bike_cruiser", "bike_urban"],
    "passenger": ["porto_rosso", "beach_cabriolet", "orbita_micro", "vale_crossover"],
    "utility": ["ranch_pickup", "ranch_single", "boxrunner", "toco_minitruck"],
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    update_installed = "--update-installed" in sys.argv[1:]
    manifest_path = OUT / "installed-manifest.json"
    previous = {row["id"]: row for row in json.loads(manifest_path.read_text(encoding="utf-8"))} if update_installed else {}
    rows = []
    for group, ids in GROUPS.items():
        for ident in ids:
            source = ROOT / "assets/fleet/redesigned" / f"{ident}.scn"
            baseline = OUT / "baseline/assets" / f"{ident}.scn"
            candidate = OUT / group / ("" if group == "motorcycles" else "candidates") / f"{ident}.scn"
            if not candidate.is_file():
                raise RuntimeError(f"Missing reviewed candidate: {candidate}")
            expected = previous[ident]["installed_sha256"] if update_installed else digest(baseline)
            if digest(source) != expected:
                raise RuntimeError(f"Concurrent production change: {source}. Nothing installed.")
            rows.append({"id": ident, "group": group, "source": str(source),
                         "candidate": str(candidate), "baseline_sha256": digest(baseline),
                         "installed_sha256": digest(candidate)})
    # Preflight every file before the first mutation. No source is reset or restored.
    registry = ROOT / "runtime/RedesignedFleet.gd"
    text = registry.read_text(encoding="utf-8")
    for ident in GROUPS["motorcycles"]:
        old = f'"{ident}":{7 if update_installed else 8},'
        if text.count(old) != 1:
            raise RuntimeError(f"Unexpected/concurrent registry value for {ident}; nothing installed.")
        text = text.replace(old, f'"{ident}":7,')
    for row in rows:
        shutil.copyfile(row["candidate"], row["source"])
    registry.write_text(text, encoding="utf-8")
    manifest_path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Installed {len(rows)} reviewed vehicle scenes; all expected source hashes matched.")


if __name__ == "__main__":
    main()
