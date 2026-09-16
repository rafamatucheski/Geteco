import os
import sys
import json
import time
import subprocess
import shutil

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(BASE_DIR, "../.."))
RESULTS_DIR = os.path.join(BASE_DIR, "results")
CONFIG_PATH = os.path.join(BASE_DIR, "session_config.json")
RUNNER_PATH = os.path.join(PROJECT_ROOT, "tests", "perf_audit_claude", "Invoke-GodotTestLocked.ps1")

RUNS = [
    {"id": "A1", "type": "baseline", "drive_s": 60.0, "extended": False},
    {"id": "B1", "type": "patch",    "drive_s": 60.0, "extended": False},
    {"id": "A2", "type": "baseline", "drive_s": 60.0, "extended": False},
    {"id": "B2", "type": "patch",    "drive_s": 60.0, "extended": False},
    {"id": "A3", "type": "baseline", "drive_s": 60.0, "extended": False},
    {"id": "B3", "type": "patch",    "drive_s": 90.0, "extended": True},
]

def apply_state(state_type):
    patch_manager = os.path.join(BASE_DIR, "manage_ab_patch.py")
    cmd = "apply_baseline" if state_type == "baseline" else "apply_patch"
    subprocess.check_call([sys.executable, patch_manager, cmd], cwd=PROJECT_ROOT)

def run_session(run_cfg):
    session_id = run_cfg["id"]
    state_type = run_cfg["type"]
    drive_s = run_cfg["drive_s"]
    extended = run_cfg["extended"]
    session_out_dir = os.path.join(RESULTS_DIR, f"session_{session_id}")
    os.makedirs(session_out_dir, exist_ok=True)

    print(f"\n========================================================")
    print(f"=== EXECUTANDO SESSAO {session_id} ({state_type.upper()}) ===")
    print(f"========================================================")

    apply_state(state_type)

    cfg_payload = {
        "session_id": session_id,
        "active_drive_seconds": drive_s,
        "extended": extended,
        "out_dir": f"tests/perf_audit_antigravity/results/session_{session_id}"
    }
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg_payload, f, indent=2)

    ps_cmd = [
        "powershell",
        "-ExecutionPolicy", "Bypass",
        "-File", RUNNER_PATH,
        "-ScriptPath", "res://tests/perf_audit_antigravity/benchmark_session.gd",
        "-Path", "d:/geteco/game",
        "-Run", f"session_{session_id}",
        "-OutDir", f"tests/perf_audit_antigravity/results/session_{session_id}",
        "-TimeoutSec", "360"
    ]
    print(f"Comando: {' '.join(ps_cmd)}")
    t0 = time.time()
    res = subprocess.run(ps_cmd, cwd=PROJECT_ROOT)
    elapsed = time.time() - t0
    print(f"Sessao {session_id} encerrada com exit_code={res.returncode} em {elapsed:.1f}s")
    return res.returncode

def main():
    os.makedirs(RESULTS_DIR, exist_ok=True)
    all_results = {}

    target_runs = RUNS
    if len(sys.argv) > 1:
        wanted_ids = sys.argv[1].split(",")
        target_runs = [r for r in RUNS if r["id"] in wanted_ids]

    try:
        for r in target_runs:
            ret = run_session(r)
            rep_path = os.path.join(RESULTS_DIR, f"session_{r['id']}", "report.json")
            if os.path.exists(rep_path):
                with open(rep_path, "r") as rf:
                    all_results[r["id"]] = json.load(rf)
            else:
                all_results[r["id"]] = {"error": f"Report missing, exit_code={ret}"}
    finally:
        # Guarantee we leave repository in patch state (03B)
        print("\nRestaurando estado do repositorio para PATCH 03B...")
        apply_state("patch")

    # Summarize and save consolidated results
    summary_path = os.path.join(RESULTS_DIR, "consolidated_benchmark_summary.json")
    with open(summary_path, "w") as sf:
        json.dump(all_results, sf, indent=2)
    print(f"\nResumo consolidado salvo em {summary_path}")

if __name__ == "__main__":
    main()
