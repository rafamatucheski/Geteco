"""Alinha contadores nativos concluídos, só de teste, e produz figuras estáticas de diagnóstico."""

import argparse
from collections import Counter
import json
from pathlib import Path
from statistics import fmean


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def summarize(rows):
    if not rows:
        return {}
    wall = sum(row["wall_interval_usec"] for row in rows)
    cpu = sum(row["cpu_delta_usec"] for row in rows)
    cycles = sum(row["cycles_delta"] for row in rows)
    steps = sum(row["physics_steps"] for row in rows)
    return {
        "first_process_frame": rows[0]["process_frame"],
        "last_process_frame": rows[-1]["process_frame"],
        "begin_engine_usec": rows[0]["observer_begin_usec"] - rows[0]["wall_interval_usec"],
        "end_engine_usec": rows[-1]["observer_begin_usec"],
        "frames": len(rows), "wall_usec": wall, "main_thread_cpu_usec": cpu,
        "main_thread_cpu_percent_of_one_thread": 100 * cpu / wall,
        "thread_cycles": cycles,
        "cycles_per_accounted_cpu_usec": cycles / cpu if cpu else None,
        "cycles_per_wall_usec": cycles / wall,
        "physics_steps": steps, "physics_step_histogram": dict(sorted(Counter(row["physics_steps"] for row in rows).items())),
        "all_thread_cycles_per_physics_step": cycles / steps if steps else None,
        "all_thread_cpu_usec_per_physics_step": cpu / steps if steps else None,
        "mean_frame_ms": wall / len(rows) / 1000,
        "gc_pause_delta_usec": sum(row["gc_delta_usec"] for row in rows),
        "gc_collection_deltas": {str(g): sum(row[f"gc_gen{g}_delta"] for row in rows) for g in range(3)},
        "observer_mean_usec": fmean(row["observer_usec"] for row in rows),
        "observer_max_usec": max(row["observer_usec"] for row in rows),
        "nonaccepted_or_unmapped_context_frames": sum(not row["accepted"] for row in rows),
    }


def load_window(path):
    cost = read(path)
    raw = read(path.with_name(path.name.replace("-cost", "")))
    stride = cost["row_stride"]
    rows = [dict(zip(cost["row_fields"], cost["rows"][i:i + stride]))
        for i in range(0, len(cost["rows"]), stride)]
    deltas = []
    lo, hi = cost["accepted_first_process_frame"], cost["accepted_last_process_frame"]
    for previous, current in zip(rows, rows[1:]):
        row = dict(current)
        row["cpu_delta_usec"] = sum(current[key] - previous[key] for key in ("thread_kernel_usec", "thread_user_usec"))
        row["cycles_delta"] = current["thread_cycles"] - previous["thread_cycles"]
        row["gc_delta_usec"] = current["gc_pause_usec"] - previous["gc_pause_usec"]
        for generation in range(3):
            row[f"gc_gen{generation}_delta"] = current[f"gc_gen{generation}"] - previous[f"gc_gen{generation}"]
        row["accepted"] = lo <= current["process_frame"] <= hi
        row["plot_frame_ms"] = row["wall_interval_usec"] / 1000
        deltas.append(row)
    accepted = [row for row in deltas if row["accepted"]]
    alignment = (cost.get("accepted_frame_range_exact", False)
        and len(accepted) == len(raw["frames_ms"]) == hi - lo + 1
        and all(row["process_frame"] == lo + index for index, row in enumerate(accepted)))
    if not alignment:
        # IDs de primeiro/último não identificam as amostras escolhidas pelo pai depois de
        # uma falha de foco. Guarda todas as linhas observadas só como contexto; nunca as
        # emparelha com os quadros aceitos nem deduz seleção pelo foco instantâneo.
        for row in deltas:
            row["accepted"] = False
        accepted = []
    for row, ms in zip(accepted, raw["frames_ms"]):
        row["plot_frame_ms"] = ms
    spike_indices = [i for i, row in enumerate(accepted) if row["plot_frame_ms"] > 33.3]
    groups = []
    for index in spike_indices:
        if not groups or accepted[index]["observer_begin_usec"] - accepted[groups[-1][-1]]["observer_begin_usec"] > 250000:
            groups.append([])
        groups[-1].append(index)
    events = [{key: row[key] for key in ("process_frame", "observer_begin_usec", "gc_delta_usec", "gc_gen0_delta", "gc_gen1_delta", "gc_gen2_delta", "plot_frame_ms")}
        for row in accepted if row["gc_delta_usec"] or any(row[f"gc_gen{g}_delta"] for g in range(3))]
    unfocused_ranges = []
    for row in deltas:
        if row["focused"] == 1 and row["minimized"] == 0:
            continue
        if not unfocused_ranges or row["process_frame"] != unfocused_ranges[-1]["last_process_frame"] + 1:
            unfocused_ranges.append({"first_process_frame": row["process_frame"],
                "begin_engine_usec": row["observer_begin_usec"] - row["wall_interval_usec"], "frames": 0})
        unfocused_ranges[-1].update(last_process_frame=row["process_frame"], end_engine_usec=row["observer_begin_usec"])
        unfocused_ranges[-1]["frames"] += 1
    detail = {
        "source": path.as_posix(), "scenario": cost["scenario"], "variant": cost["variant"],
        "parent_summary_unchanged": raw["summary"], "accepted_alignment_verified": alignment,
        "analysis_scope": "accepted_exact" if alignment else "context_only_unmapped_parent_selection",
        "parent_focus_discards": cost.get("parent_focus_discards", 0),
        "accepted_range_exact_from_capture": cost.get("accepted_frame_range_exact", False),
        "parent_frame_count": len(raw["frames_ms"]),
        "observer_context_rows": len(deltas),
        "unfocused_observer_ranges_context_only": unfocused_ranges,
        "clock_anchor_fields": cost["clock_anchor_fields"],
        "clock_anchor_start": cost["clock_anchor_start"], "clock_anchor_end": cost["clock_anchor_end"],
        "focus_valid": all(row["focused"] == 1 and row["minimized"] == 0 for row in accepted) if alignment else None,
        "thread_counter_valid": all(row["thread_sample_valid"] == 1 and row["native_thread_id"] == cost["main_thread_id"] for row in accepted) if alignment else None,
        "counter_monotonic": all(row["cpu_delta_usec"] >= 0 and row["cycles_delta"] >= 0 and row["gc_delta_usec"] >= 0 for row in accepted) if alignment else None,
        "diagnostic_capture_valid": cost["diagnostic_capture_valid"],
        "observer_parent_interval_max_difference_usec": max((abs(row["wall_interval_usec"] - ms * 1000) for row, ms in zip(accepted, raw["frames_ms"])), default=None),
        "load_probe_max_usec": max(cost["load_probes"][4::cost["load_probe_stride"]], default=0),
        "all_accepted": summarize(accepted), "gc_events": events, "spike_blocks": [],
        "context_only_summary": summarize(deltas) if not alignment else None,
        "all_spikes_envelope_not_continuously_above_threshold": summarize(accepted[spike_indices[0]:spike_indices[-1] + 1]) if spike_indices else None,
    }
    for group in groups:
        block = accepted[group[0]:group[-1] + 1]
        first = block[0]["observer_begin_usec"] - block[0]["wall_interval_usec"]
        last = block[-1]["observer_begin_usec"]
        before = [row for row in deltas if row["observer_begin_usec"] <= first
            and row["observer_begin_usec"] - row["wall_interval_usec"] >= first - 3000000]
        after = [row for row in deltas if row["observer_begin_usec"] <= last + 3000000
            and row["observer_begin_usec"] - row["wall_interval_usec"] >= last]
        detail["spike_blocks"].append({"over_33_3_ms": len(group), "block": summarize(block),
            "three_seconds_before_whole_intervals": summarize(before),
            "three_seconds_after_whole_intervals": summarize(after)})
    return detail, deltas, accepted


def cpu_bins(rows, width_usec=500000):
    bins = {}
    for row in rows:
        bins.setdefault(row["observer_begin_usec"] // width_usec, []).append(row)
    return [(fmean(row["observer_begin_usec"] for row in values) / 1e6,
             100 * sum(row["cpu_delta_usec"] for row in values) / sum(row["wall_interval_usec"] for row in values))
        for values in bins.values()]


def plot(windows, output, zoom=False):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    figure, axes = plt.subplots(4, 1, figsize=(15, 10), sharex=True,
        gridspec_kw={"height_ratios": [2, 1.2, 1, 1]})
    colors = {"final": "#116ac2", "baseline": "#c46b21"}
    for detail, all_rows, accepted in windows:
        rows = accepted
        context_only = not detail["accepted_alignment_verified"]
        if context_only:
            rows = all_rows
        if zoom:
            if not detail["spike_blocks"]:
                continue
            block = detail["spike_blocks"][0]["block"]
            lower, upper = block["begin_engine_usec"] - 3000000, block["end_engine_usec"] + 3500000
            rows = [row for row in all_rows if lower <= row["observer_begin_usec"] <= upper]
        times = [row["observer_begin_usec"] / 1e6 for row in rows]
        color = "#888888" if context_only else colors[detail["variant"]]
        label = detail["scenario"] + (" — contexto; seleção não mapeada" if context_only else "")
        axes[0].plot(times, [row["plot_frame_ms"] for row in rows], color=color, lw=.7, label=label)
        bins = cpu_bins(rows)
        axes[1].plot([x for x, _ in bins], [y for _, y in bins], color=color, lw=1.2)
        axes[2].plot(times, [0] * len(times), color=color, lw=.7)
        for row in rows:
            if row["gc_delta_usec"]:
                axes[2].vlines(row["observer_begin_usec"] / 1e6, 0, row["gc_delta_usec"] / 1000, color="#9855ac", lw=2)
                axes[2].scatter(row["observer_begin_usec"] / 1e6, row["gc_delta_usec"] / 1000, color="#9855ac", s=22)
        axes[3].plot(times, [row["physics_steps"] for row in rows], color=color, lw=.65)
        if context_only:
            for axis in axes:
                axis.axvspan(times[0], times[-1], color="#888888", alpha=.08)
                for interval in detail["unfocused_observer_ranges_context_only"]:
                    axis.axvspan(interval["begin_engine_usec"] / 1e6,
                        interval["end_engine_usec"] / 1e6, color="#555555", alpha=.12)
        for event in detail["spike_blocks"]:
            for axis in axes:
                axis.axvspan(event["block"]["begin_engine_usec"] / 1e6,
                    event["block"]["end_engine_usec"] / 1e6, color="#cc3333", alpha=.09)
        if zoom:
            first = accepted[0]["observer_begin_usec"] - accepted[0]["wall_interval_usec"]
            if times[0] < first / 1e6:
                for axis in axes:
                    axis.axvspan(times[0], first / 1e6, color="#888888", alpha=.13)
                axes[0].text(times[0] + .15, axes[0].get_ylim()[1] * .93, "cinza: contexto de aquecimento", fontsize=9)
    axes[0].axhline(33.3, color="#b73535", linestyle="--", lw=.8)
    axes[0].axhline(66.7, color="#b73535", linestyle=":", lw=.8)
    axes[1].axhline(100, color="#666666", linestyle=":", lw=.8)
    axes[0].set_ylabel("Tempo do quadro (ms)")
    axes[1].set_ylabel("CPU thread principal\n% de 1 thread / bins 0,5 s")
    axes[2].set_ylabel("Pausa GC nova (ms)")
    gc_max = max((row["gc_delta_usec"] / 1000 for _, rows, _ in windows for row in rows), default=0)
    axes[2].set_ylim(0, max(.2, gc_max * 1.2))
    axes[3].set_ylabel("Passos físicos\nno intervalo")
    step_max = max((row["physics_steps"] for _, rows, _ in windows for row in rows), default=1)
    axes[3].set_yticks(range(step_max + 1))
    axes[3].set_xlabel("Relógio monotônico do motor (segundos); âncoras UTC/QPC no JSON")
    for axis in axes:
        axis.grid(alpha=.2)
    axes[0].legend(loc="upper right", fontsize=9)
    suffix = " — detalhe do bloco" if zoom else " — quatro janelas"
    if not any(detail["spike_blocks"] for detail, _, _ in windows):
        suffix = " — nenhum quadro aceito acima de 33,3 ms"
    if not zoom and any(not detail["accepted_alignment_verified"] for detail, _, _ in windows):
        suffix = " — aceitos exatos nas janelas 1/2/4; janela 3 apenas contexto"
    figure.suptitle("Diagnóstico diurno: quadros aceitos e contadores nativos" + suffix, fontsize=14)
    figure.text(.02, .012, "CPU nativa tem contabilização grosseira: agregada em 0,5 s. CPU/GPU não foram somadas. Vermelho: bloco de picos.\n"
        "Cinza: contexto sem mapear seleção; faixa cinza escura: sem foco. Não se infere agregado aceito. GC não mede todo stall.", fontsize=9)
    figure.tight_layout(rect=[0, .052, 1, .96])
    figure.savefig(output, dpi=140)
    plt.close(figure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    windows = [load_window(path) for path in sorted(args.directory.glob("day-*-cost.json"))]
    if not windows:
        raise ValueError("No completed cost files")
    result = {
        "source_directory": args.directory.as_posix(),
        "limits": [
            "No raw samples modified. Parent summaries unchanged; observer intervals differ by callback timing/overhead.",
            "Windows without exact parent-frame ID mapping are context only, including any focus-discarded intervals; no accepted cost summary is inferred.",
            "Thread times are cumulative and coarse: isolated frame deltas can be zero or exceed wall time. Use accumulated intervals.",
            "Thread cycles per accounted CPU microsecond is an accounting ratio, not an exact CPU-clock measurement.",
            "Cycles per physics step includes ALL main-thread work and is not isolated physics cost.",
            "Main-thread active CPU may include driver busy-wait; it does not identify useful game-system work.",
            "Three-second context before the first block includes warmup; this is labeled and never added to accepted benchmark summaries.",
            "Existing process/physics Performance monitors are not used as per-frame CPU attribution.",
        ],
        "windows": [detail for detail, _, _ in windows],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    overview = args.output.with_name(args.output.stem + "-overview.png")
    zoom = args.output.with_name(args.output.stem + "-spike.png")
    plot(windows, overview)
    has_spike = any(detail["spike_blocks"] for detail, _, _ in windows)
    if has_spike:
        plot(windows, zoom, zoom=True)
    print(json.dumps({"analysis":str(args.output),"overview":str(overview),"spike":str(zoom) if has_spike else None,
        "spike_figure_generated":has_spike,
        "alignment_verified":all(detail["accepted_alignment_verified"] for detail, _, _ in windows)}))


if __name__ == "__main__":
    main()
