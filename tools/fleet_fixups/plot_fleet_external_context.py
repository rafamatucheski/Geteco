"""Plot existing robust CPU brackets; do not invent an instantaneous CPU series."""

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


base = Path("evidence/fleet-day-investigation-20261011")
external = json.loads((base / "day-cause-baseline-external-analysis.json").read_text())
phase = external["phases"][0]
qpc_before, engine_usec, _, qpc_after, frequency, _ = phase["clock_anchor"]
qpc_anchor = (qpc_before + qpc_after) / 2


def engine_seconds(qpc):
    return engine_usec / 1e6 + (qpc - qpc_anchor) / frequency


cost_path = Path("evidence/fleet-redesign-20261011/validation/performance/day-cause-baseline/day-01-final-cost.json")
cost = json.loads(cost_path.read_text())
stride = cost["row_stride"]
rows = [dict(zip(cost["row_fields"], cost["rows"][i:i + stride])) for i in range(0, len(cost["rows"]), stride)]
ranges = [entry for entry in phase["ranges"] if entry["name"] in ("prior_3s", "spike_block", "following_3s")]
lower = min(engine_seconds(entry["cpu"]["bracket_qpc"][0]) for entry in ranges) - .25
upper = max(engine_seconds(entry["cpu"]["bracket_qpc"][1]) for entry in ranges) + .25
selected = [row for row in rows if lower <= row["observer_begin_usec"] / 1e6 <= upper]
figure, axes = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
axes[0].plot([row["observer_begin_usec"] / 1e6 for row in selected],
    [row["wall_interval_usec"] / 1000 for row in selected], color="#1766b4", lw=1)
axes[0].axhline(33.3, color="#ba3333", linestyle="--", lw=.8)
axes[0].axhline(66.7, color="#ba3333", linestyle=":", lw=.8)
axes[0].set_ylabel("Tempo do quadro (ms)\nobservador alinhado por frame ID")
labels = {"prior_3s": "Antes", "spike_block": "Bloco", "following_3s": "Contexto ampliado"}
colors = {"prior_3s": "#9a7733", "spike_block": "#bd3333", "following_3s": "#7751a0"}
for entry in ranges:
    cpu = entry["cpu"]
    left, right = map(engine_seconds, cpu["bracket_qpc"])
    value = cpu["external_machine_percent"]
    axes[1].plot([left, right], [value, value], color=colors[entry["name"]], lw=4, marker="|")
    suffix = "\n(inclui parte do bloco)" if entry["name"] == "following_3s" else ""
    axes[1].text((left + right) / 2, value + 3,
        f"{labels[entry['name']]}: {value:.2f}% em {cpu['bracket_seconds']:.3f} s{suffix}", ha="center", fontsize=10)
block = next(entry for entry in ranges if entry["name"] == "spike_block")
for axis in axes:
    axis.axvspan(block["engine_usec"][0] / 1e6, block["engine_usec"][1] / 1e6, color="#bd3333", alpha=.08)
    axis.grid(alpha=.2)
axes[1].set_ylim(0, 105)
axes[1].set_ylabel("CPU externa média\n% da capacidade lógica da máquina")
axes[1].set_xlabel("Relógio monotônico do motor (segundos), alinhado via QPC")
figure.suptitle("Picos e carga externa na mesma execução — intervalos preservados", fontsize=14)
figure.text(.035, .02, "Segmentos são médias por contadores acumulados nos brackets reais; não são uma série instantânea.\n"
    "CPU externa = total − Godot − observador. Brackets têm limites diferentes e podem se sobrepor. Associação não prova causa exclusiva.", fontsize=9)
figure.tight_layout(rect=[0, .07, 1, .95])
output = base / "day-cause-baseline-external-context.png"
figure.savefig(output, dpi=150)
plt.close(figure)
print(output)
