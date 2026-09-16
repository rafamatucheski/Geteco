import os
import subprocess
import shutil
import sys

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(BASE_DIR, "../.."))

FILES = [
    "MountainPass.gd",
    "MountainPassRoad.gd",
    "MountainSceneryBuilder.gd",
    "MountainSkiArea.gd"
]

PATCH_DIR = os.path.join(BASE_DIR, "patch_03b_files")
BASELINE_DIR = os.path.join(BASE_DIR, "baseline_03a_files")
TARGET_DIR = os.path.join(PROJECT_ROOT, "world", "mountain_pass")

def setup():
    os.makedirs(PATCH_DIR, exist_ok=True)
    os.makedirs(BASELINE_DIR, exist_ok=True)
    for f in FILES:
        src = os.path.join(TARGET_DIR, f)
        dst_patch = os.path.join(PATCH_DIR, f)
        shutil.copy2(src, dst_patch)
        
        git_path = f"HEAD:world/mountain_pass/{f}"
        dst_baseline = os.path.join(BASELINE_DIR, f)
        raw = subprocess.check_output(["git", "show", git_path], cwd=PROJECT_ROOT)
        with open(dst_baseline, "wb") as bf:
            bf.write(raw)
    print("Setup completed successfully.")

def apply_baseline():
    for f in FILES:
        src = os.path.join(BASELINE_DIR, f)
        dst = os.path.join(TARGET_DIR, f)
        shutil.copy2(src, dst)
    print("Baseline (03A) applied to world/mountain_pass/.")

def apply_patch():
    for f in FILES:
        src = os.path.join(PATCH_DIR, f)
        dst = os.path.join(TARGET_DIR, f)
        shutil.copy2(src, dst)
    print("Patch (03B) applied to world/mountain_pass/.")

def status():
    for f in FILES:
        git_path = f"world/mountain_pass/{f}"
        diff = subprocess.check_output(["git", "diff", "--stat", git_path], cwd=PROJECT_ROOT).decode("utf-8")
        print(f"{f}: {diff.strip() if diff.strip() else 'clean (matches HEAD)'}")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "setup":
        setup()
    elif cmd == "apply_baseline":
        apply_baseline()
    elif cmd == "apply_patch":
        apply_patch()
    elif cmd == "status":
        status()
    else:
        print("Unknown command:", cmd)
