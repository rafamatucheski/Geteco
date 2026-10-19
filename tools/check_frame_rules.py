"""Confere as regras do docs/HOW-TO-DEVELOP.md que mais custaram quadros, sem rodar o Godot.

Por que existe: as regras "luz nova passa pelo LightBudget" e "nunca surface_get_arrays no jogo"
(e, desde 19/10, as leituras de malha por dentro do motor e a varredura de grupo por quadro) estavam só
no documento; em 18/10/2026 cerca de 55 arquivos criavam luz direto e 86 lugares
liam malha da GPU (revisão cruzada, F10). Quebrar tudo de uma vez não é viável, então é uma
catraca: tools/frame_rules_baseline.json guarda quantas ocorrências cada arquivo tem hoje, e a
checagem só falha quando um arquivo passa desse número (código novo). Diminuir é sempre bem-vindo;
depois de diminuir, rode --update-baseline para a catraca não deixar voltar.

Uso:
  python -I tools/check_frame_rules.py                 # confere a árvore de trabalho
  python -I tools/check_frame_rules.py --staged        # só o que está no índice; recusa 200+ arquivos
  python -I tools/check_frame_rules.py --update-baseline
Variável: GETECO_ALLOW_BIG_COMMIT=1 libera o limite de arquivos (consolidação combinada).
Sai com 0 quando está tudo dentro da catraca.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tools" / "frame_rules_baseline.json"
# Pastas de jogo. tests/, tools/ e addons/ podem assar malha e criar luz de captura à vontade.
GAME_DIRS = ("activities", "audio", "cutscenes", "gameplay", "runtime", "scripts", "systems", "ui", "world")
MAX_STAGED_FILES = 200
RULES = {
    "dynamic_light": {
        "pattern": re.compile(r"\b(OmniLight3D|SpotLight3D)\.new\(\)"),
        "why": "luz dinâmica nova fora do LightBudget (HOW-TO-DEVELOP §3.9)",
    },
    "mesh_readback": {
        "pattern": re.compile(r"\bsurface_get_arrays\("),
        "why": "surface_get_arrays lê a malha da GPU e espera os quadros em voo; use MeshArrayCache (§3.2)",
    },
    # Os mesmos surface_get_arrays por dentro do motor (auditoria de 19/10, §3 item 8): a catraca só olhava a
    # chamada explícita. Colisão sai das arrays que o código montou (world/chunk_bake/CollisionFaces.gd);
    # lote de caixas usa StaticBoxBatch (por isso BOX_BATCH.append_from não conta). get_faces() de uma forma
    # (ConcavePolygonShape3D) não lê a GPU, mas o texto não distingue: fica na baseline do arquivo.
    "mesh_readback_internal": {
        "pattern": re.compile(r"\bcreate_trimesh_shape\(|\bcreate_convex_shape\(|\bget_faces\(|(?<!BOX_BATCH)\.append_from\("),
        "why": "create_trimesh_shape/create_convex_shape/get_faces/append_from leem a malha da GPU por dentro; "
               "monte com as arrays da CPU (CollisionFaces, MeshArrayCache) (§3.2)",
    },
    "group_scan_per_frame": {
        "pattern": None,  # contado por função em count_text: precisa saber em que func a linha está
        "why": "get_nodes_in_group/find_children dentro de _process/_physics_process varre a árvore todo quadro; "
               "guarde a lista ou use sinal (§3)",
    },
}
FUNC_LINE = re.compile(r"^(?:static\s+)?func\s+(\w+)")
PER_FRAME_FUNCS = ("_process", "_physics_process")
GROUP_SCAN = re.compile(r"\b(get_nodes_in_group|find_children)\(")


def count_text(text):
    """Ocorrências de cada regra num arquivo. A varredura de grupo só conta dentro de _process e
    _physics_process (a func corrente muda em toda linha `func` sem recuo; lambda e func interna não)."""
    result = {}
    for name, rule in RULES.items():
        if rule["pattern"] is not None:
            result[name] = len(rule["pattern"].findall(text))
    current = ""
    scans = 0
    for line in text.splitlines():
        match = FUNC_LINE.match(line)
        if match:
            current = match.group(1)
            continue
        if current in PER_FRAME_FUNCS and not line.lstrip().startswith("#"):
            scans += len(GROUP_SCAN.findall(line))
    result["group_scan_per_frame"] = scans
    return result


def tracked_game_files():
    out = subprocess.run(["git", "ls-files", "--", *GAME_DIRS], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    files = [line for line in out.stdout.splitlines() if line.endswith(".gd")]
    # Arquivo novo ainda não rastreado também conta: é justamente o código novo.
    extra = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *GAME_DIRS], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    files += [line for line in extra.stdout.splitlines() if line.endswith(".gd")]
    return sorted(set(files))


def count_all():
    counts = {name: {} for name in RULES}
    for rel in tracked_game_files():
        path = ROOT / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for name, n in count_text(text).items():
            if n:
                counts[name][rel] = n
    return counts


def count_staged():
    """Só os .gd de jogo que estão no índice, com o conteúdo que vai ser commitado. Assim a mudança
    não commitada de outra sessão nunca bloqueia o commit de quem não tocou nela."""
    out = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", *GAME_DIRS],
                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    counts = {name: {} for name in RULES}
    for rel in out.stdout.splitlines():
        if not rel.endswith(".gd"):
            continue
        shown = subprocess.run(["git", "show", ":" + rel], cwd=ROOT, capture_output=True)
        text = shown.stdout.decode("utf-8", errors="replace")
        for name, n in count_text(text).items():
            counts[name][rel] = n
    return counts


def main(argv):
    counts = count_staged() if "--staged" in argv else count_all()
    if "--update-baseline" in argv:
        counts = count_all()
        BASELINE.write_text(json.dumps(counts, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
        total = {name: sum(v.values()) for name, v in counts.items()}
        print(f"frame-rules: baseline gravada {total}")
        return 0
    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    problems = []
    for name, per_file in counts.items():
        allowed = baseline.get(name, {})
        for rel, n in sorted(per_file.items()):
            if n > int(allowed.get(rel, 0)):
                problems.append(f"{rel}: {n - int(allowed.get(rel, 0))} nova(s) — {RULES[name]['why']}")
    if "--staged" in argv and os.environ.get("GETECO_ALLOW_BIG_COMMIT") != "1":
        staged = subprocess.run(["git", "diff", "--cached", "--name-only"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
        n = len([line for line in staged.stdout.splitlines() if line.strip()])
        if n > MAX_STAGED_FILES:
            problems.append(f"commit com {n} arquivos (limite {MAX_STAGED_FILES}): divida por sessão/assunto ou use GETECO_ALLOW_BIG_COMMIT=1")
    if problems:
        print("frame-rules: FALHOU")
        for line in problems:
            print("  " + line)
        return 1
    if "--staged" in argv:
        print(f"frame-rules: ok ({sum(len(v) for v in counts.values()) // max(1, len(RULES))} arquivo(s) de jogo no commit)")
        return 0
    total = {name: sum(v.values()) for name, v in counts.items()}
    print(f"frame-rules: ok {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
