"""Export real mínimo de PCK para Windows com os bytes de voz de produção; não é o export do jogo todo.

Reaproveita o projeto isolado de test_export_mountain_dialogue.ps1.
Nenhuma tomada gerada é fabricada, e nenhum asset do projeto é apagado ou movido.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path("D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe")
MANIFEST = "audio/mission_voices/directed/runtime.json"
REQUIRED_JSON = [MANIFEST, "data/dialogue/voice-cast.json", "data/dialogue/voice-line-direction.json"]
FERRY_KEY = "5ff7c2828a346aed46fb557885139678bbb4a53d42a58ba53045385c88ec1a7b"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="first")
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain only letters, numbers, hyphens or underscores")
    manifest = json.loads((ROOT / MANIFEST).read_text(encoding="utf-8"))
    entries = [manifest["lines"][language][FERRY_KEY] for language in ("pt_BR", "en")]
    output = ROOT / "evidence/voice-integration-20261012" / ("export-smoke-" + args.label)
    output.mkdir(parents=True, exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix="geteco-directed-export-"))
    run_root = fixture / "run-empty"
    run_root.mkdir()
    copied: list[str] = []

    def copy(relative: str) -> None:
        target = fixture / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
        copied.append(relative)

    for relative in REQUIRED_JSON + ["audio/mission_voices/en/catalog.json", "audio/DirectedVoiceBank.gd", "audio/ExpressiveVoice.gd"]:
        copy(relative)
    for entry in entries:
        copy(entry["path"].removeprefix("res://"))
    excluded = ["audio/mission_voices/directed/anchors.json", "audio/mission_voices/directed/cloned-production.json"]
    for folder in ("anchors", "benchmarks"):
        excluded.append(next((ROOT / "audio/mission_voices/directed" / folder).rglob("*.wav")).relative_to(ROOT).as_posix())
    for relative in excluded:
        copy(relative)
    copy("export_presets.cfg")
    shutil.copyfile(fixture / "export_presets.cfg", output / "export_presets.snapshot.cfg")
    expected = {"res://" + relative: hashlib.sha256((fixture / relative).read_bytes()).hexdigest() for relative in REQUIRED_JSON}
    config = configparser.ConfigParser(interpolation=None)
    config.read(fixture / "export_presets.cfg", encoding="utf-8")
    policy = {}
    for section in ("preset.0", "preset.1"):
        includes = {part.strip() for part in config[section]["include_filter"].strip('"').split(",")}
        assert set(REQUIRED_JSON) <= includes, section
        policy[section] = {"name": config[section]["name"].strip('"'), "required_json_explicit": True}
    (fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Directed voice export probe"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    probe = '''extends SceneTree
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const EXPECTED = __EXPECTED__
const ENTRIES = __ENTRIES__
const EXCLUDED = __EXCLUDED__
func _initialize() -> void:
    var checks := 0
    var failures: Array[String] = []
    for path in EXPECTED:
        checks += 1
        if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != EXPECTED[path]: failures.append("Missing/changed JSON: " + path)
    for path in EXCLUDED:
        checks += 1
        if FileAccess.file_exists(path) or ResourceLoader.exists(path): failures.append("Production input leaked into pack: " + path)
    for expected in ENTRIES:
        var row := BANK.canonical(str(expected.source), str(expected.persona))
        var take := BANK.resolve(row, str(expected.language), str(expected.character_id))
        checks += 1
        if take.is_empty(): failures.append("Pack take metadata rejected: " + str(expected.language)); continue
        checks += 1
        if not ResourceLoader.exists(str(take.path), "AudioStream"): failures.append("Imported audio missing from pack: " + str(take.path))
        var shown := VOICE.presentation(str(expected.source), str(expected.persona), str(expected.language), "en", str(expected.character_id))
        checks += 1
        if not shown.directed or shown.stream == null: failures.append("Packed take did not load: " + str(take.path)); continue
        checks += 1
        if absf(shown.stream.get_length() - float(take.duration_seconds)) > .03 or shown.message != str(row.spoken_en): failures.append("Packed take duration/caption mismatch")
    print("DIRECTED_VOICE_EXPORT checks=%d failures=%s" % [checks, failures])
    quit(0 if failures.is_empty() else 1)
'''
    # O JSON aqui só tem valores primitivos string/dicionário/array, que também são literais GDScript válidos.
    selected = [{k: e[k] for k in ("source", "persona", "language", "character_id")} for e in entries]
    probe = probe.replace("__EXPECTED__", json.dumps(expected, ensure_ascii=False)).replace("__ENTRIES__", json.dumps(selected, ensure_ascii=False)).replace("__EXCLUDED__", json.dumps(["res://" + path for path in excluded]))
    (fixture / "probe.gd").write_text(probe, encoding="utf-8")
    env = {**os.environ, "APPDATA": str(fixture / "appdata"), "GETECO_DIRECTED_VOICES": "1"}
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

    def run(arguments: list[str], log: str, timeout: int) -> int:
        with (output / log).open("w", encoding="utf-8") as stream:
            result = subprocess.run([str(ENGINE), *arguments], cwd=run_root, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, creationflags=flags, check=False)
        print(log, "exit", result.returncode)
        return result.returncode

    pack = output / "directed-voice.pck"
    export_code = run(["--headless", "--path", str(fixture), "--export-pack", "Geteco V2 Windows", str(pack)], "export.log", 60)
    probe_code = None
    if export_code == 0:
        probe_code = run(["--headless", "--path", str(run_root), "--main-pack", str(pack), "--script", "res://probe.gd"], "probe.log", 20)
    report = {"scope": "Minimal real Windows PCK export; Android policy inspected only; no full game export or C# gameplay assertion",
              "production_manifest_sha256": expected["res://" + MANIFEST], "fixtures": "Isolated project containing unchanged actual production bytes; no fake take or approval",
              "policy": policy, "fixture_path": str(fixture), "pack_path": str(pack), "copied_files": copied,
              "export_exit": export_code, "probe_exit": probe_code, "production_pairs_loaded": 2 if probe_code == 0 else 0}
    (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if probe_code is not None: print((output / "probe.log").read_text(encoding="utf-8"))
    print("Report:", output / "report.json")
    return 0 if export_code == 0 and probe_code == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
