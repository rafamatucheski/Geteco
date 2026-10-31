"""Verifica um APK exportado de verdade: importações, catálogos de runtime, vozes e .NET ARM64."""
import argparse
import configparser
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def validate(apk):
    failures, checks = [], 0
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())

        def check(ok, message):
            nonlocal checks
            checks += 1
            if not ok:
                failures.append(message)

        def resource(path):
            key = "assets/" + path.removeprefix("res://")
            if key in names:
                return True
            for suffix in (".import", ".remap"):
                if key + suffix not in names:
                    continue
                remaps = re.findall(r'^path(?:\.[\w]+)?="(res://[^"\n]+)"',
                                    archive.read(key + suffix).decode("utf-8").rstrip("\0"), re.M)
                return bool(remaps) and all("assets/" + p.removeprefix("res://") in names for p in remaps)
            return False

        check(archive.testzip() is None, "APK contains a corrupt ZIP entry")
        for key in ("AndroidManifest.xml", "lib/arm64-v8a/libgodot_android.so",
                    "lib/arm64-v8a/libmonosgen-2.0.so",
                    "assets/.godot/mono/publish/arm64/Harbor.dll"):
            check(key in names, "Missing runtime: " + key)
        check(not any(n.startswith(("lib/armeabi-v7a/", "lib/x86/", "lib/x86_64/")) for n in names),
              "Unexpected non-ARM64 runtime")
        for n in names:
            if n.startswith("assets/") and n.endswith((".import", ".remap")):
                check(resource("res://" + n.removeprefix("assets/").removesuffix(".import").removesuffix(".remap")),
                      "Unresolved imported resource: " + n)
        presets = configparser.ConfigParser(interpolation=None)
        presets.read(ROOT / "export_presets.cfg", encoding="utf-8")
        import fnmatch
        patterns = [p.strip() for p in presets["preset.1"]["include_filter"].strip('"').split(",")]
        catalogs = sorted({p.relative_to(ROOT).as_posix() for pattern in patterns
                           for p in ROOT.glob(pattern) if p.is_file() and p.suffix == ".json"})
        for relative in catalogs:
            key = "assets/" + relative
            check(key in names and archive.read(key) == (ROOT / relative).read_bytes(),
                  "Missing or stale runtime catalog: " + relative)
        manifest = json.loads((ROOT / "audio/mission_voices/directed/runtime.json").read_text(encoding="utf-8"))
        takes = [entry for language in manifest["lines"].values() for entry in language.values()]
        for entry in takes:
            check(resource(entry["path"]), "Missing directed voice: " + entry["path"])
        for manifest_name in ("recordings.json", "maciota_baritone/recordings.json", "en/recordings.json"):
            recordings = json.loads((ROOT / "audio/mission_voices" / manifest_name).read_text(encoding="utf-8"))
            for path in recordings.values():
                if isinstance(path, str) and path.startswith("res://"):
                    check(resource(path), "Missing legacy voice: " + path)
        fleet = json.loads((ROOT / "assets/fleet/catalog.json").read_text(encoding="utf-8"))
        for vehicle in fleet["vehicles"].values():
            check(resource(vehicle["scene"]), "Missing vehicle scene: " + vehicle["scene"])
        for path in ("res://ui/AndroidControls.gd", "res://gameplay/PlayerAirMovement.gd",
                     "res://gameplay/urban_v1/PortFreightDelivery.gd", "res://runtime/transit/BusDriverShift.gd",
                     "res://activities/desert_drag/DragOpenMeet.gd"):
            check(resource(path), "Missing gameplay script: " + path)
        for prefix in ("assets/tests/", "assets/tools/", "assets/output/", "assets/tmp/", "assets/evidence/",
                       "assets/audio/mission_voices/directed/anchors/", "assets/audio/mission_voices/directed/benchmarks/"):
            check(not any(n.startswith(prefix) for n in names), "Development resources leaked: " + prefix)
        deps = "assets/.godot/mono/publish/arm64/Harbor.deps.json"
        check(deps in names and "Version=v9.0" in archive.read(deps).decode("utf-8"), "Android assembly does not target .NET 9")
    return {"apk": str(apk.resolve()), "bytes": apk.stat().st_size,
            "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(), "checks": checks,
            "runtime_catalogs": len(catalogs), "directed_takes": len(takes), "failures": failures,
            "scope": "Actual APK bytes and dependency presence; not on-device gameplay or artistic audio approval."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.apk)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ANDROID_PACKAGE checks={result['checks']} catalogs={result['runtime_catalogs']} directed_takes={result['directed_takes']} failures={len(result['failures'])}")
    for failure in result["failures"]:
        print(failure)
    raise SystemExit(bool(result["failures"]))
