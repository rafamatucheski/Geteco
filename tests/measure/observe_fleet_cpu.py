"""Finite Windows CPU observer for one known game PID; never enumerates processes.

Example: python tests/measure/observe_fleet_cpu.py --pid 1234 --seconds 240 --out run/cpu.json
Counters are buffered in memory; the exclusive output file is created at completion.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
import time


class FileTime(ctypes.Structure):
    _fields_ = [("low", wintypes.DWORD), ("high", wintypes.DWORD)]

    def ticks(self):
        return (self.high << 32) | self.low


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


class NativeCpu:
    def __init__(self, pid):
        self.dll = ctypes.WinDLL("kernel32", use_last_error=True)
        self.handles = {}
        self.births = {}
        self.pid = pid
        self.own_pid = os.getpid()
        ft = ctypes.POINTER(FileTime)
        signatures = {
            "GetSystemTimes": ([ft, ft, ft], wintypes.BOOL),
            "OpenProcess": ([wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            "GetProcessTimes": ([wintypes.HANDLE, ft, ft, ft, ft], wintypes.BOOL),
            "GetProcessId": ([wintypes.HANDLE], wintypes.DWORD),
            "CloseHandle": ([wintypes.HANDLE], wintypes.BOOL),
            "WaitForSingleObject": ([wintypes.HANDLE, wintypes.DWORD], wintypes.DWORD),
            "QueryPerformanceCounter": ([ctypes.POINTER(ctypes.c_longlong)], wintypes.BOOL),
            "QueryPerformanceFrequency": ([ctypes.POINTER(ctypes.c_longlong)], wintypes.BOOL),
            "GetSystemTimePreciseAsFileTime": ([ft], None),
            "GetActiveProcessorCount": ([wintypes.WORD], wintypes.DWORD),
        }
        for name, (args, result) in signatures.items():
            function = getattr(self.dll, name)
            function.argtypes = args
            function.restype = result
        self.frequency = self.query("QueryPerformanceFrequency")
        self.logical_processors = int(self.dll.GetActiveProcessorCount(0xFFFF))
        try:
            for role, process_id in (("godot", pid), ("observer", self.own_pid)):
                handle = self.dll.OpenProcess(0x1000 | 0x100000, False, process_id)
                if not handle:
                    raise ctypes.WinError(ctypes.get_last_error())
                self.handles[role] = handle
                if int(self.dll.GetProcessId(handle)) != process_id:
                    raise RuntimeError(f"Unexpected process identity for {role}")
                row = self.process_times(role)
                if row["exited"]:
                    raise RuntimeError(f"{role} PID {process_id} already exited")
                self.births[role] = row["birth_filetime_100ns"]
        except BaseException:
            self.close()
            raise

    def query(self, name):
        value = ctypes.c_longlong()
        if not getattr(self.dll, name)(ctypes.byref(value)):
            raise ctypes.WinError(ctypes.get_last_error())
        return value.value

    def process_times(self, role):
        birth, end, kernel, user = (FileTime() for _ in range(4))
        handle = self.handles[role]
        if not self.dll.GetProcessTimes(handle, ctypes.byref(birth), ctypes.byref(end),
                                        ctypes.byref(kernel), ctypes.byref(user)):
            raise ctypes.WinError(ctypes.get_last_error())
        wait = self.dll.WaitForSingleObject(handle, 0)
        if wait not in (0, 258):
            raise ctypes.WinError(ctypes.get_last_error())
        return {"birth_filetime_100ns": birth.ticks(), "exit_filetime_100ns": end.ticks(),
                "kernel_100ns": kernel.ticks(), "user_100ns": user.ticks(), "exited": wait == 0}

    def sample(self):
        before = self.query("QueryPerformanceCounter")
        utc = FileTime()
        self.dll.GetSystemTimePreciseAsFileTime(ctypes.byref(utc))
        utc_after = self.query("QueryPerformanceCounter")
        idle, kernel, user = (FileTime() for _ in range(3))
        if not self.dll.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user)):
            raise ctypes.WinError(ctypes.get_last_error())
        processes = {role: self.process_times(role) for role in self.handles}
        for role, row in processes.items():
            if row["birth_filetime_100ns"] != self.births[role]:
                raise RuntimeError(f"Process birth time changed: {role}")
        after = self.query("QueryPerformanceCounter")
        return {"qpc_before": before, "qpc_utc_after": utc_after, "qpc_after": after,
                "utc_filetime_100ns": utc.ticks(), "idle_100ns": idle.ticks(),
                "kernel_including_idle_100ns": kernel.ticks(), "user_100ns": user.ticks(),
                "native_sample_ms": (after - before) * 1000 / self.frequency,
                "processes": processes}

    def close(self):
        for handle in self.handles.values():
            self.dll.CloseHandle(handle)
        self.handles.clear()


def interval(previous, current, frequency):
    wall = (current["qpc_before"] - previous["qpc_before"]) / frequency
    total = (current["kernel_including_idle_100ns"] - previous["kernel_including_idle_100ns"]
             + current["user_100ns"] - previous["user_100ns"])
    idle = current["idle_100ns"] - previous["idle_100ns"]
    cpu = {}
    valid = wall > 0 and total > 0 and 0 <= idle <= total
    for role in current["processes"]:
        a, b = previous["processes"][role], current["processes"][role]
        delta = b["kernel_100ns"] + b["user_100ns"] - a["kernel_100ns"] - a["user_100ns"]
        valid = valid and delta >= 0 and a["birth_filetime_100ns"] == b["birth_filetime_100ns"]
        cpu[role] = delta
    result = {"seconds": wall, "valid": valid, "system_total_100ns": total,
              "system_idle_100ns": idle, "process_cpu_100ns": cpu}
    if valid:
        external = total - idle - cpu["godot"] - cpu["observer"]
        result.update(machine_busy_percent=100 * (total - idle) / total,
                      godot_machine_percent=100 * cpu["godot"] / total,
                      observer_machine_percent=100 * cpu["observer"] / total,
                      external_machine_percent=100 * external / total,
                      godot_one_core_percent=100 * cpu["godot"] / (wall * 1e7),
                      observer_one_core_percent=100 * cpu["observer"] / (wall * 1e7))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=240)
    parser.add_argument("--interval-ms", type=float, default=200)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("Windows native counters required")
    if args.pid <= 0 or not 0.2 <= args.seconds <= 360 or not 100 <= args.interval_ms <= 2000:
        parser.error("Require positive PID, 0.2..360 seconds, interval 100..2000 ms")
    if args.pid == os.getpid():
        parser.error("Target must differ from observer PID")
    if args.out.exists():
        parser.error("Output already exists; choose a new path")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "started_utc": utc_now(), "target_pid": args.pid,
              "observer_pid": os.getpid(), "requested_seconds": args.seconds,
              "interval_ms": args.interval_ms,
              "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "samples": [], "failure": "", "termination": "duration_complete",
              "scope": "Fixed QUERY_LIMITED_INFORMATION/SYNCHRONIZE handles; birth identity checked each sample. No process enumeration, WMI, suspension, focus, priority, affinity or power changes. CPU is all process threads, not just main. External residual includes all other processes/kernel work and is not causal attribution. Counters sampled sequentially; quantization can make residual slightly negative, retained without clipping. No GC, GPU, clocks or temperature measured. Buffered output written only after collection."}
    probe = None
    exit_code = 0
    try:
        probe = NativeCpu(args.pid)
        if probe.logical_processors > 64:
            raise RuntimeError("GetSystemTimes processor-group coverage is not supported above 64 logical processors")
        report.update(qpc_frequency=probe.frequency, logical_processors=probe.logical_processors,
                      process_birth_filetime_100ns=probe.births.copy())
        probe.sample()  # Resolve Python/ctypes paths before the retained baseline.
        started = probe.query("QueryPerformanceCounter")
        deadline = started + round(args.seconds * probe.frequency)
        step = round(args.interval_ms * probe.frequency / 1000)
        target = started
        previous = None
        while True:
            remaining = (target - probe.query("QueryPerformanceCounter")) / probe.frequency
            if remaining > 0:
                time.sleep(remaining)
            row = probe.sample()
            row["elapsed_seconds"] = (row["qpc_before"] - started) / probe.frequency
            row["scheduled_qpc"] = target
            row["schedule_lateness_ms"] = (row["qpc_before"] - target) * 1000 / probe.frequency
            if previous is not None:
                row["interval"] = interval(previous, row, probe.frequency)
            report["samples"].append(row)
            previous = row
            row["observer_body_ms"] = (probe.query("QueryPerformanceCounter") - row["qpc_before"]) * 1000 / probe.frequency
            if row["processes"]["godot"]["exited"]:
                report["termination"] = "target_exited"
                break
            if row["qpc_after"] >= deadline:
                break
            # Do not catch up with bursts if scheduling skipped an interval.
            elapsed_slots = max(1, (row["qpc_after"] - started) // step + 1)
            target = min(started + elapsed_slots * step, deadline)
    except KeyboardInterrupt:
        report["termination"] = "interrupted"
        exit_code = 130
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
        report["termination"] = "error"
        exit_code = 1
    finally:
        if probe:
            probe.close()
        report["ended_utc"] = utc_now()
        report["valid_intervals"] = sum(bool(r.get("interval", {}).get("valid")) for r in report["samples"])
        report["max_observer_body_ms"] = max((r.get("observer_body_ms", 0) for r in report["samples"]), default=0)
        with args.out.open("x", encoding="utf-8") as output:
            json.dump(report, output, ensure_ascii=False, separators=(",", ":"))
    print(json.dumps({"output": str(args.out.resolve()), "samples": len(report["samples"]),
                      "termination": report["termination"], "failure": report["failure"]}))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
