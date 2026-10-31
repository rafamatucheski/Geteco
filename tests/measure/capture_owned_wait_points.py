"""Pontos de espera limitados na thread principal do próprio Godot, sem elevação nem depurador.

Inicie separado do jogo não elevado; nunca inicia/encerra um jogo.
Exige um recibo de lançamento novo da mesma rodada e o ClockAnchor STALL_CAPTURE_READY.
Exemplo: --label run1 --logfile evidence/.../run1.log
  --launch-json evidence/.../run1-launch.json --out evidence/.../run1-waits.json
  --capture-json evidence/.../run1.json

Recibo de lançamento: {"pid": console_wrapper_pid, "utc": ISO8601_launch_UTC,
                 "engine": absolute_Godot_4.7.2_mono_console_exe_path}.
native_pid/main_tid opcionais precisam bater com o READY quando fornecidos. Todos os handles
são conferidos contra imagem, pai, nascimento e posse da thread pelo auxiliar congelado.
Isto é interferência de diagnóstico, nunca um benchmark limpo de FPS.
O --periodic-return opcional troca o gatilho de espera por no máximo 120 pontos na thread
principal, um por janela de 250 ms entre READY+30s e READY+60s. Nunca recupera janelas
perdidas numa rajada. Amostra CPU além das esperas; não é um profiler de cada callback
de script, e o desenrolar nativo pode ser parcial.
"""
from __future__ import annotations

import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import time

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "evidence"
DEPENDENCY = EVIDENCE / "intermittent-stalls-20261004/continuation-native/native_main_thread_points_initial_frame.py"
DEPENDENCY_SHA = "FD3120E9C92FAE8701070AAB993B6F802B590C0363E2433609D79D3A4C19683C"
POLL_SECONDS = .005
QUIET_SECONDS = .020
COOLDOWN_SECONDS = .250
MAX_POINTS = 12
MAX_SECONDS = 150
PERIODIC_START = 30.0
PERIODIC_END = 60.0
PERIODIC_INTERVAL = .250
PERIODIC_MAX_POINTS = 120


def periodic_slot(ready_seconds, previous_slot):
    """Devolve só a janela elegível atual; janelas perdidas nunca são repetidas."""
    if not PERIODIC_START <= ready_seconds < PERIODIC_END:
        return None
    slot = int((ready_seconds-PERIODIC_START)/PERIODIC_INTERVAL)
    return slot if slot > previous_slot else None


def load_native():
    if hashlib.sha256(DEPENDENCY.read_bytes()).hexdigest().upper() != DEPENDENCY_SHA:
        raise RuntimeError("Reviewed native helper changed; refusing attachment")
    spec = importlib.util.spec_from_file_location("owned_wait_native", DEPENDENCY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def log_text(path):
    return path.read_text(encoding="utf-8-sig", errors="replace") if path.exists() else ""


def finished(text, label):
    return bool(re.search(r"(?m)^STALL_CAPTURE_FINISHED " + re.escape(label) + r"(?:\s|$)", text))


def resolve_target(native, api, args, deadline):
    while time.perf_counter() < deadline:
        text = log_text(args.logfile)
        if finished(text, args.label):
            raise RuntimeError("Selected run already finished; no attachment")
        matches = re.findall(r"(?m)^STALL_CAPTURE_READY " + re.escape(args.label) + r" (\{[^\r\n]+\})\s*$", text)
        if len(matches) > 1:
            raise RuntimeError("Ambiguous same-label READY records")
        if matches and args.launch_json.exists():
            launch_bytes = args.launch_json.read_bytes()
            launch = json.loads(launch_bytes.decode("utf-8-sig"))
            ready = json.loads(matches[0])
            anchor = ready["details"]["clock_anchor"]
            if len(anchor) != 6 or anchor[4] != api.frequency or anchor[0] > anchor[3]:
                raise RuntimeError("Incompatible same-run ClockAnchor")
            if Path(launch["engine"]).resolve() != native.CONSOLE.resolve():
                raise RuntimeError("Receipt must identify Godot 4.7.2 .NET console")
            pid, tid = int(ready["details"]["pid"]), int(anchor[5])
            if int(launch.get("native_pid", pid)) != pid or int(launch.get("main_tid", tid)) != tid:
                raise RuntimeError("Explicit target PID/TID differs from READY")
            return {"label": args.label, "pid": pid, "tid": tid,
                    "parent_pid": int(launch["pid"]), "launch_utc": launch["utc"],
                    "expected_image": str(native.ENGINE), "wrapper_image": str(native.CONSOLE),
                    "ready_anchor": anchor, "launch_sha256": hashlib.sha256(launch_bytes).hexdigest()}
        time.sleep(.05)
    raise TimeoutError("READY/launch deadline expired; no attachment")


def collect(native, api, core, target, process, wrapper, thread, args, deadline):
    query_cycles = core.bind(core.K, "QueryThreadCycleTime", W.BOOL, [W.HANDLE, C.POINTER(C.c_ulonglong)])

    def cycles():
        value = C.c_ulonglong()
        if not query_cycles(thread, C.byref(value)):
            raise OSError(C.get_last_error(), "QueryThreadCycleTime(owned main)")
        return value.value

    result = {"points": [], "module_snapshots": [api.modules(process)],
              "polls": 0, "episodes_rechecked_busy": 0, "stop_reason": None}
    worker = native.ContextWorker(api, process, thread)
    origin = (target["ready_anchor"][0] + target["ready_anchor"][3]) / 2
    cpu_began, began = time.process_time(), api.qpc()
    last_cycles, quiet_since = cycles(), time.perf_counter()
    last_capture = -float("inf")
    captured_episode = False
    next_log_check = 0.0
    try:
        while time.perf_counter() < deadline:
            now = time.perf_counter()
            if core.wait(process, 0) != 258 or core.wait(wrapper, 0) != 258:
                result["stop_reason"] = "owned_game_or_wrapper_exited"
                break
            if now >= next_log_check:
                next_log_check = now + .25
                if finished(log_text(args.logfile), args.label):
                    result["stop_reason"] = "measurement_finished"
                    break
            current = cycles()
            result["polls"] += 1
            if current != last_cycles:
                quiet_since, captured_episode = now, False
            elif not captured_episode and now - quiet_since >= QUIET_SECONDS and now - last_capture >= COOLDOWN_SECONDS:
                # Os handles retidos não podem apontar em silêncio para PIDs/TIDs reutilizados.
                # Reconfere posse/vida e ciclos logo antes de suspender.
                guard_began = api.qpc()
                if api.pid_of_thread(thread) != target["pid"] or not api.identity(process)["alive"]:
                    result["stop_reason"] = "owned_identity_no_longer_valid"
                    break
                if hashlib.sha256(args.launch_json.read_bytes()).hexdigest() != target["launch_sha256"]:
                    raise RuntimeError("Same-run launch receipt changed")
                confirmed = cycles()
                if confirmed != current:
                    result["episodes_rechecked_busy"] += 1
                    last_cycles, quiet_since = confirmed, time.perf_counter()
                    continue
                cpu_before = core.cpu_ms(thread)
                point = worker.point(None, target["pid"], target["tid"])
                # Guarda a amostra retomada mesmo se o jogo sair durante a próxima consulta.
                result["points"].append(point)
                point.update(trigger="unchanged_main_thread_cycles", unchanged_cycles_ms=(now-quiet_since)*1000,
                             cycles_before=confirmed, cycles_after=cycles(), thread_cpu_ms_before=cpu_before,
                             thread_cpu_ms_after=core.cpu_ms(thread), guard_begin_qpc=guard_began,
                             start_ready_seconds=(point["qpc_before"]-origin)/api.frequency)
                # Só os metadados de módulo do nosso processo, depois do Resume. Sem workers nem
                # varreduras globais de estado de thread; todo StackWalk/símbolo fica para depois.
                result["module_snapshots"].append(api.modules(process))
                last_capture, captured_episode = time.perf_counter(), True
                # Descarta o progresso do tempo suspenso da próxima linha de base ociosa.
                last_cycles = point["cycles_after"]
                quiet_since = last_capture
                if point.get("error") or point.get("api_error") or point.get("resume_previous_count") != 1:
                    result["stop_reason"] = "native_point_error"
                    break
                if len(result["points"]) >= MAX_POINTS:
                    result["stop_reason"] = "point_limit"
                    break
                time.sleep(POLL_SECONDS)
                continue
            last_cycles = current
            time.sleep(POLL_SECONDS)
        if result["stop_reason"] is None:
            result["stop_reason"] = "finite_collection_deadline"
    except Exception as error:
        result["stop_reason"] = "collection_error"
        result["error"] = {"type":type(error).__name__,"message":str(error)}
    finally:
        result["context_worker_stopped"] = worker.stop()
        result.update(collection_cpu_ms=(time.process_time()-cpu_began)*1000,
                      collection_wall_ms=(api.qpc()-began)/api.frequency*1000)
    return result


def collect_periodic_return(native, api, core, target, process, wrapper, thread, args, deadline):
    """Mesma primitiva de contexto de thread própria, com agenda READY fixa e finita."""
    query_cycles = core.bind(core.K, "QueryThreadCycleTime", W.BOOL, [W.HANDLE, C.POINTER(C.c_ulonglong)])

    def cycles():
        value = C.c_ulonglong()
        if not query_cycles(thread, C.byref(value)):
            raise OSError(C.get_last_error(), "QueryThreadCycleTime(owned main)")
        return value.value

    result = {"points": [], "module_snapshots": [api.modules(process)],
              "polls": 0, "stop_reason": None, "mode":"periodic_return",
              "ready_window_seconds":[PERIODIC_START, PERIODIC_END]}
    origin = (target["ready_anchor"][0]+target["ready_anchor"][3])/2
    worker = native.ContextWorker(api, process, thread)
    cpu_began, began = time.process_time(), api.qpc()
    previous_slot = -1
    next_log_check = 0.0
    last_capture = -float("inf")
    try:
        while time.perf_counter() < deadline:
            now = time.perf_counter()
            if core.wait(process, 0) != 258 or core.wait(wrapper, 0) != 258:
                result["stop_reason"] = "owned_game_or_wrapper_exited"
                break
            if now >= next_log_check:
                next_log_check = now + .25
                if finished(log_text(args.logfile), args.label):
                    result["stop_reason"] = "measurement_finished"
                    break
            elapsed = (api.qpc()-origin)/api.frequency
            result["polls"] += 1
            if elapsed >= PERIODIC_END:
                result["stop_reason"] = "periodic_window_complete"
                break
            slot = periodic_slot(elapsed, previous_slot)
            if slot is None or now-last_capture < PERIODIC_INTERVAL:
                time.sleep(.005 if elapsed >= PERIODIC_START else .05)
                continue
            guard_began = api.qpc()
            if api.pid_of_thread(thread) != target["pid"] or not api.identity(process)["alive"]:
                result["stop_reason"] = "owned_identity_no_longer_valid"
                break
            if hashlib.sha256(args.launch_json.read_bytes()).hexdigest() != target["launch_sha256"]:
                raise RuntimeError("Same-run launch receipt changed")
            # O custo da guarda/API não pode autorizar um ponto fora da janela.
            elapsed = (api.qpc()-origin)/api.frequency
            slot = periodic_slot(elapsed, previous_slot)
            if slot is None:
                continue
            cpu_before, cycles_before = core.cpu_ms(thread), cycles()
            point = worker.point(None, target["pid"], target["tid"])
            result["points"].append(point)
            point.update(trigger="periodic_main_thread_return", scheduled_slot=slot,
                         scheduled_ready_seconds=PERIODIC_START+slot*PERIODIC_INTERVAL,
                         cycles_before=cycles_before, cycles_after=cycles(),
                         thread_cpu_ms_before=cpu_before, thread_cpu_ms_after=core.cpu_ms(thread),
                         guard_begin_qpc=guard_began,
                         start_ready_seconds=(point["qpc_before"]-origin)/api.frequency)
            previous_slot, last_capture = slot, time.perf_counter()
            # Toda enumeração acontece depois do Resume; o retrato final também
            # pega módulos carregados depois do início da coleta. Nada de símbolos aqui.
            if point.get("error") or point.get("api_error") or point.get("resume_previous_count") != 1:
                result["stop_reason"] = "native_point_error"
                break
            if len(result["points"]) >= PERIODIC_MAX_POINTS:
                result["stop_reason"] = "point_limit"
                break
        if result["stop_reason"] is None:
            result["stop_reason"] = "finite_collection_deadline"
        if core.wait(process, 0) == 258:
            result["module_snapshots"].append(api.modules(process))
        if not result["points"]:
            result["error"] = {"type":"NoPeriodicPoints", "message":"No point admitted inside READY+30..60s"}
    except Exception as error:
        result["stop_reason"] = "collection_error"
        result["error"] = {"type":type(error).__name__, "message":str(error)}
    finally:
        result["context_worker_stopped"] = worker.stop()
        result.update(collection_cpu_ms=(time.process_time()-cpu_began)*1000,
                      collection_wall_ms=(api.qpc()-began)/api.frequency*1000,
                      unfilled_slots=PERIODIC_MAX_POINTS-len(result["points"]))
    return result


def defer_decode(native, api, core, target, process, wrapper, thread, result, args, deadline):
    reason = None
    while time.perf_counter() < deadline:
        if core.wait(process, 0) != 258:
            reason = "owned_game_exited"
            break
        if finished(log_text(args.logfile), args.label):
            reason = "measurement_finished"
            break
        time.sleep(.25)
    if reason:
        # O timeout=0 do decodificador congelado pula a espera por pasta: a conferência
        # do logfile plano acima já fixou a fronteira da medição.
        native.finish_and_decode(api, target, process, wrapper, thread, result, None, 0)
        result["decode_deferred_until"] = reason
    else:
        result["decode_deferred_until"] = "deadline_game_still_running_no_stackwalk"
        modules = [m for snap in result["module_snapshots"] for m in snap["modules"]]
        for point in result["points"]:
            point.pop("context", None)
            point["copied_stack_bytes"] = len(point.pop("stack", b""))
            if "rip" in point:
                point["frames"] = [native.module_address(point["rip"], modules)]
            point["unwind_stop"] = {"reason": "game_still_running_at_deadline"}


def correlate(report, path):
    if path is None or not path.exists():
        return
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if data.get("label") != report["target"]["label"]:
        raise RuntimeError("Capture JSON label differs from guarded run")
    ready = report["target"]["ready_anchor"]
    origin = (ready[0]+ready[3])/2
    for point in report["result"]["points"]:
        engine_usec = ready[1] + (point["qpc_before"]-origin)*1e6/ready[4]
        point["estimated_engine_usec"] = engine_usec
        point["matching_frames"] = [{key: row.get(key) for key in ("frame", "phase", "focused", "ms", "physics_steps", "start_usec", "end_usec")}
                                    for row in data.get("frames", []) if row["start_usec"] <= engine_usec <= row["end_usec"]]
    report["capture_validity"] = data.get("validity")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--logfile", type=Path, required=True)
    parser.add_argument("--launch-json", type=Path, required=True)
    parser.add_argument("--capture-json", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=MAX_SECONDS)
    parser.add_argument("--periodic-return", action="store_true",
                        help="At most120 own-main-thread points, >=250ms apart, only READY+30..60s; replaces wait trigger")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}", args.label) or not 1 <= args.seconds <= MAX_SECONDS:
        parser.error("Safe label and seconds in [1,150] required")
    if args.periodic_return and args.seconds < PERIODIC_END:
        parser.error("Periodic return requires seconds>=60; default150 permits offline decode after route finish")
    destination = args.out.resolve()
    if destination.exists() or not destination.is_relative_to(EVIDENCE.resolve()) or not destination.parent.is_dir():
        parser.error("Use a new output inside an existing project evidence directory")
    native = load_native()
    core = native.load_core()
    api = native.Api(core)
    report = {"label":args.label, "dependency_sha256":DEPENDENCY_SHA,
              "source_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "trigger_clock":"time.perf_counter / QueryPerformanceCounter; avoids Python3.11 GetTickCount64 monotonic quantization",
              "scope":"Diagnostic own-main-thread point samples; suspension perturbs the target. No clean FPS approval. Unchanged cycle counter is a trigger, not proof of Waiting versus Ready. No ETW, other-process control, worker suspension, focus changes, device changes or symbol downloads. Context16KiB copy followed by Resume in finally, before any stack walking. Frozen worker has100ms context deadline; OS calls and scheduling are not hard real-time bounded. RIP/module/RVA primary; partial native unwind and nearest exports do not prove exact caller. Raw stack/context bytes never written.",
              "limits":{"poll_ms":5,"unchanged_cycles_ms":20,"cooldown_ms":250,"max_points":12,"seconds":args.seconds,"ready_timeout_seconds":150},
              "start_anchor":api.anchor()}
    if args.periodic_return:
        report["limits"] = {"mode":"periodic_return", "ready_window_seconds":[30,60],
                            "minimum_interval_ms":250, "max_points":120,
                            "seconds":args.seconds, "ready_timeout_seconds":150}
    process = wrapper = thread = None
    try:
        # A partida tem espera finita própria; o prazo de coleta/fim começa no
        # anexo, para o carregamento inicial não consumir a janela de diagnóstico.
        target = resolve_target(native, api, args, time.perf_counter()+150)
        process, wrapper, thread, identity, wrapper_identity = native.open_owned(api, target)
        report.update(target=target,target_identity=identity,wrapper_identity=wrapper_identity)
        print(f"OWNED_WAIT_READY label={args.label} pid={target['pid']} tid={target['tid']}", flush=True)
        deadline = time.perf_counter()+args.seconds
        collector = collect_periodic_return if args.periodic_return else collect
        result = collector(native, api, core, target, process, wrapper, thread, args, deadline)
        report["result"] = result
        if result.get("error") or result["stop_reason"] == "native_point_error" or not result["context_worker_stopped"]:
            report["error"] = {"type":"NativeCollectionIncomplete","message":result["stop_reason"]}
        defer_decode(native, api, core, target, process, wrapper, thread, result, args, deadline)
        correlate(report, args.capture_json)
    except Exception as error:
        report["error"] = {"type":type(error).__name__,"message":str(error)}
    finally:
        for handle in (thread, wrapper, process):
            if handle:
                core.close(handle)
        # Nem falhas parciais de decodificação podem serializar bytes privados copiados.
        for point in report.get("result",{}).get("points",[]):
            point.pop("context",None)
            point.pop("stack",None)
        report["end_anchor"] = api.anchor()
        with destination.open("x",encoding="utf-8") as output:
            json.dump(report,output,indent=2)
    print(f"OWNED_WAIT_DONE points={len(report.get('result',{}).get('points',[]))} error={'error' in report}", flush=True)
    return 1 if "error" in report else 0


if __name__ == "__main__":
    raise SystemExit(main())
