"""Pré-checagem finita de pontos de espera nativos só num filho sintético deste processo.

Nunca procura nem se anexa ao Godot. O wrapper de produção mantém a lista de imagens
permitidas do Godot; só o objeto de módulo carregado neste fixture troca pela nossa
imagem Python, para exercitar posse/contexto/decodificação no nosso próprio filho.
"""
import ctypes as C
from ctypes import wintypes as W
import datetime
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]


def qpc():
    value = C.c_longlong()
    C.windll.kernel32.QueryPerformanceCounter(C.byref(value))
    return value.value


def child(folder):
    label = "synthetic-owned-wait"
    frequency = C.c_longlong()
    C.windll.kernel32.QueryPerformanceFrequency(C.byref(frequency))
    started = qpc()
    anchor = [started, 1000000, time.time_ns()//100+116444736000000000,
              qpc(), frequency.value, C.windll.kernel32.GetCurrentThreadId()]
    logfile = folder / "child.log"
    logfile.write_text("STALL_CAPTURE_READY "+label+" "+json.dumps({"details":{"pid":os.getpid(),"clock_anchor":anchor}})+"\n",encoding="utf-8")
    frames = []
    for cycle in range(8):
        for phase, seconds in (("busy",.23),("waiting",.13)):
            begin = qpc()
            if phase == "waiting":
                time.sleep(seconds)
            else:
                until = time.perf_counter()+seconds
                while time.perf_counter()<until:
                    pass
            end = qpc()
            frames.append({"frame":len(frames),"phase":phase,"focused":True,"physics_steps":0,
                           "start_usec":1000000+(begin-started)*1e6/frequency.value,
                           "end_usec":1000000+(end-started)*1e6/frequency.value,
                           "ms":(end-begin)*1000/frequency.value})
    (folder/"child.json").write_text(json.dumps({"label":label,"validity":"synthetic_only","frames":frames}),encoding="utf-8")
    with logfile.open("a",encoding="utf-8") as output:
        output.write("STALL_CAPTURE_FINISHED "+label+"\n")


def run(periodic=False):
    prefix = "wait-helper-periodic-preflight-" if periodic else "wait-helper-preflight-"
    folder = ROOT/"evidence/harbor-regression-20261009"/(prefix+datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    folder.mkdir()
    spec = importlib.util.spec_from_file_location("wait_wrapper_fixture",ROOT/"tests/measure/capture_owned_wait_points.py")
    wrapper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wrapper)
    native = wrapper.load_native()
    core = native.load_core()
    api = native.Api(core)
    own = api.identity(core.current_process())
    native.ENGINE = Path(sys.executable).resolve()
    native.CONSOLE = native.ENGINE
    # Nenhum módulo/arquivo de produção é alterado; a instância deste fixture é privada.
    wrapper.load_native = lambda: native
    if periodic:
        # Encurta só a janela deste fixture importado em privado. As fronteiras de produção
        # 30..60s/120 janelas são cobertas por test_owned_wait_schedule.py.
        wrapper.PERIODIC_START = .30
        wrapper.PERIODIC_END = 2.55
        wrapper.PERIODIC_MAX_POINTS = 9
    launch = {"pid":os.getpid(),"utc":datetime.datetime.fromtimestamp((own["birth_filetime"]-116444736000000000)/1e7,datetime.timezone.utc).isoformat(),"engine":sys.executable}
    (folder/"launch.json").write_text(json.dumps(launch),encoding="utf-8")
    args = [sys.executable,str(Path(__file__).resolve()),"--child",str(folder)]
    process = subprocess.Popen(args,creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        # Rejeita um TID errado com o filho ainda vivo, para isto exercitar
        # especificamente a posse da thread e não a guarda de vida anterior.
        probe_args = SimpleNamespace(label="synthetic-owned-wait",logfile=folder/"child.log",launch_json=folder/"launch.json")
        target = wrapper.resolve_target(native,api,probe_args,time.perf_counter()+3)
        bad_target = dict(target,tid=api.current_tid())
        try:
            handles = native.open_owned(api,bad_target)
        except RuntimeError as error:
            wrong_tid_rejected = "different process" in str(error)
        else:
            wrong_tid_rejected = False
            for handle in handles[:3]:
                core.close(handle)
        sys.argv = ["capture_owned_wait_points.py","--label","synthetic-owned-wait",
                    "--logfile",str(folder/"child.log"),"--launch-json",str(folder/"launch.json"),
                    "--capture-json",str(folder/"child.json"),"--out",str(folder/"result.json"),"--seconds","6"]
        if periodic:
            sys.argv.append("--periodic-return")
        code = wrapper.main()
        child_exit = process.wait(timeout=10)
        report = json.loads((folder/"result.json").read_text())
        points = report.get("result",{}).get("points",[])
        checks = {
            "wrapper_success":code==0,
            "child_resumed_and_finished":child_exit==0 and (folder/"child.json").exists(),
            "target_is_exact_own_child":report.get("target",{}).get("pid")==process.pid,
            "positive_bounded_capture_count":0<len(points)<=wrapper.MAX_POINTS,
            "only_unheld_thread_suspended":bool(points) and all(p.get("prior_suspend_count")==0 for p in points),
            "own_increment_resumed":bool(points) and all(p.get("resume_previous_count")==1 for p in points),
            "native_points_valid":bool(points) and all(not p.get("error") and not p.get("api_error") for p in points),
            "trigger_at_least20ms":bool(points) and all(p.get("unchanged_cycles_ms",0)>=20 for p in points),
            "samples_correlate_with_synthetic_wait":bool(points) and all(p.get("matching_frames") and all(r["phase"]=="waiting" for r in p["matching_frames"]) for p in points),
            "worker_stopped":report.get("result",{}).get("context_worker_stopped")==True,
            "native_frames_produced":bool(points) and all(p.get("frames") for p in points),
            "raw_bytes_not_exported":all("context" not in p and "stack" not in p for p in points),
            "wrong_tid_rejected":wrong_tid_rejected,
        }
        if periodic:
            checks.pop("trigger_at_least20ms")
            checks.pop("samples_correlate_with_synthetic_wait")
            seconds = [p.get("start_ready_seconds", -1) for p in points]
            phases = {row["phase"] for p in points for row in p.get("matching_frames", [])}
            slots = [p.get("scheduled_slot", -1) for p in points]
            checks.update(
                positive_bounded_capture_count=0<len(points)<=wrapper.PERIODIC_MAX_POINTS,
                periodic_trigger=bool(points) and all(p.get("trigger")=="periodic_main_thread_return" for p in points),
                every_point_within_fixture_window=bool(seconds) and all(wrapper.PERIODIC_START<=s<wrapper.PERIODIC_END for s in seconds),
                at_least250ms_between_points=all(b-a>=.250 for a,b in zip(seconds,seconds[1:])),
                no_duplicate_or_replayed_slots=slots==sorted(set(slots)),
                samples_capture_both_cpu_and_wait=phases=={"busy","waiting"},
                decode_only_after_finished=report.get("result",{}).get("decode_deferred_until") in {"measurement_finished","owned_game_exited"},
            )
        summary = {"checks":checks,"passed":all(checks.values()),"folder":str(folder),"points":len(points),
                   "max_suspend_request_to_resume_ms":max((p.get("suspend_request_to_resume_ms",0) for p in points),default=0),
                   "collector_cpu_ms":report.get("result",{}).get("collection_cpu_ms"),
                   "scope":"Own synthetic Python child only; proves helper mechanics here, not Godot performance or stall cause."}
        if periodic:
            summary.update(mode="periodic_return",fixture_window_seconds=[wrapper.PERIODIC_START,wrapper.PERIODIC_END],
                           production_schedule_unchanged=True)
        (folder/"summary.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
        print(json.dumps(summary))
        return 0 if summary["passed"] else 1
    finally:
        if process.poll() is None:
            # Só o filho iniciado e retido por este fixture é afetado.
            process.terminate()
            process.wait(timeout=5)


if __name__ == "__main__":
    if len(sys.argv)==3 and sys.argv[1]=="--child":
        child(Path(sys.argv[2]))
    else:
        raise SystemExit(run(periodic="--periodic-return-test" in sys.argv))
