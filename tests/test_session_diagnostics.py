"""Integration: real Godot .NET, recoverable GDScript/C# errors, restart and remote debugger.
Build Harbor.csproj first. Run: python tests/test_session_diagnostics.py --godot PATH
"""
import argparse
import os
import json
import pathlib
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]


def verify(output, debugger):
    marker = "DIAGNOSTICS_TEST_PATH "
    folder = pathlib.Path(next(line.split(marker, 1)[1] for line in output.splitlines() if marker in line))
    rows = [json.loads(line) for file in sorted(folder.glob("session-*.jsonl")) for line in file.read_text(encoding="utf-8-sig").splitlines()]
    data = [row["data"] for row in rows if "data" in row]
    assert data[0]["type"] == "session_start"
    assert data[0]["debugger"] == debugger
    assert data[-1]["type"] == "session_end"
    assert not any(row.get("type") == "records_dropped" for row in rows)
    errors = [row for row in data if row["type"] == "error"]
    assert {0, 1, 2} <= {row["error_type"] for row in errors}
    assert any(row["file"].endswith("test_session_diagnostics.gd") and row["line"] > 0 and row["backtraces"] for row in errors)
    assert any("managed exception marker" in json.dumps(row) for row in data)
    for marker in ("continued after script error", "managed callback recovered", "worker marker"):
        assert any(marker in row.get("message", "") for row in data), marker
    metrics = [row for row in data if row["type"] == "metrics"]
    assert len(metrics) >= 3
    assert any(row["context"]["paused"] for row in metrics)
    for row in metrics:
        assert row["frames"] == len(row["frame_ms"])
        assert abs(row["fps"] - row["frames"] * 1000 / sum(row["frame_ms"])) < 1e-6
        assert row["context"]["working_set_bytes"] > 0
        assert 0 <= row["context"]["cpu_percent"] <= 105
    print("PASS", "remote debugger" if debugger else "standalone", folder)
    return folder


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    os.environ['HARBOR_SESSION_LOG'] = '1'
    os.environ['HARBOR_SESSION_PROFILE'] = '1'
    command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/test_session_diagnostics.gd"]
    first = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45)
    assert first.returncode == 0, first.stdout + first.stderr
    folder = verify(first.stdout, False)
    fixture = ROOT / "evidence" / ("session-debugger-" + uuid.uuid4().hex[:8])
    fixture.mkdir(parents=True)
    (fixture / ".gdignore").write_text("")
    (fixture / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Session debugger test"\nrun/main_scene="res://Main.tscn"\n[editor]\nrun/main_run_args="--ignore-error-breaks"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/probe/plugin.cfg")\n')
    (fixture / "Main.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://Main.gd" id="1"]\n[node name="Probe" type="Node"]\nscript=ExtResource("1")\n')
    (fixture / "Main.gd").write_text('extends Node\nfunc broken():\n\tvar missing: Variant = null\n\tmissing.intentional_failure()\nfunc _ready():\n\tbroken.call_deferred()\n\tawait get_tree().create_timer(2).timeout\n\tvar f = FileAccess.open("res://continued.json", FileAccess.WRITE)\n\tf.store_string(JSON.stringify({"debugger":EngineDebugger.is_active(),"args":OS.get_cmdline_args()}))\n\tf.close()\n\tget_tree().quit()\n')
    addon = fixture / "addons" / "probe"
    addon.mkdir(parents=True)
    (addon / "plugin.cfg").write_text('[plugin]\nname="Probe"\ndescription="Test only"\nauthor="Geteco"\nversion="1"\nscript="plugin.gd"\n')
    (addon / "plugin.gd").write_text('@tool\nextends EditorPlugin\nfunc _enter_tree():\n\tstart.call_deferred()\nfunc start():\n\tawait get_tree().create_timer(2).timeout\n\tEditorInterface.play_main_scene()\n')
    with (fixture / "editor.log").open("w", encoding="utf-8") as output:
        editor = subprocess.Popen([args.godot.replace("_console.exe", ".exe"), "--headless", "--editor", "--path", str(fixture)], stdout=output, stderr=subprocess.STDOUT)
        try:
            for _ in range(150):
                if editor.poll() is not None:
                    raise AssertionError("Fixture editor exited")
                if (fixture / "continued.json").exists():
                    break
                time.sleep(.2)
            result = json.loads((fixture / "continued.json").read_text())
            # Godot consumes built-in switches; OS.get_cmdline_args omits them.
            # A connected debugger plus the marker written AFTER the error is the contract.
            assert result["debugger"], result
            print("PASS: real editor Play continued after script error", fixture)
        finally:
            subprocess.run(["taskkill", "/PID", str(editor.pid), "/T", "/F"], capture_output=True)
            editor.wait(timeout=10)
    second = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45)
    assert second.returncode == 0, second.stdout + second.stderr
    assert verify(second.stdout, False) != folder
    print("PASS: separate sessions, errors retained, process continued, CPU/frame metrics and normal closure")


if __name__ == "__main__":
    main()
