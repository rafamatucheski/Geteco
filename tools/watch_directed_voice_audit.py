"""Audit completed production snapshots while the local GPU renderer continues."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deadline-seconds", type=int, default=10800)
    parser.add_argument("--expected", type=int, default=1130)
    args = parser.parse_args()
    if not 60 <= args.deadline_seconds <= 14400 or args.expected < 1:
        parser.error("A finite deadline and a positive expected count are required")
    source = ROOT / "audio/mission_voices/directed/cloned-production.json"
    output = ROOT / "evidence/voice-direction-20261012/production-asr.json"
    log = output.with_name("production-asr-watch.log")
    deadline = time.monotonic() + args.deadline_seconds
    while time.monotonic() < deadline:
        snapshot = source.read_bytes()
        manifest = json.loads(snapshot.decode("utf-8-sig"))
        report = json.loads(output.read_text(encoding="utf-8")) if output.exists() else {}
        current_sha = hashlib.sha256(snapshot).hexdigest()
        count = len(manifest.get("takes", []))
        # Retakes remain in the ledger; historical alternatives must not count
        # toward completion of still-missing dialogue/language slots.
        slots = len({(row.get("source_key"), row.get("language"))
                     for row in manifest.get("takes", [])})
        if (report.get("manifest_sha256") == current_sha
                and report.get("asr_checked", 0) == count):
            if slots >= args.expected:
                print(json.dumps({"state": "complete", "audited": count, "unique_slots": slots}), flush=True)
                return 1 if report.get("technical_failures") else 0
            time.sleep(min(15, max(0, deadline - time.monotonic())))
            continue
        remaining = int(deadline - time.monotonic())
        if remaining < 60:
            break
        command = [sys.executable, str(ROOT / "tools/audit_directed_voices.py"),
                   "--manifest", str(source), "--output", str(output),
                   "--asr-max", "2000", "--selection", "all",
                   "--priority-section", "opening_ferry", "--workers", "3",
                   "--deadline-seconds", str(min(900, remaining - 30))]
        with log.open("a", encoding="utf-8") as stream:
            stream.write(f"\nSNAPSHOT {time.time():.3f} recordings={count}\n")
            stream.flush()
            run = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                 timeout=min(960, remaining), check=False)
        report = json.loads(output.read_text(encoding="utf-8"))
        print(json.dumps({"state": "snapshot", "recordings": report.get("waveforms_checked"),
                          "audited": report.get("asr_checked"),
                          "flags": report.get("asr_review_flags"),
                          "technical_failures": report.get("technical_failures"),
                          "exit_code": run.returncode}), flush=True)
        if run.returncode not in (0, 2):
            return run.returncode
    print(json.dumps({"state": "deadline", "report": str(output)}), flush=True)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
