#!/usr/bin/env python3
"""Move arquivos/pastas do projeto e reescreve as referencias res:// que apontam
para eles.

Existe porque este projeto referencia recursos por STRING de caminho, nao por
UID: ~653 preload("res://...") e ~903 load("res://...") em GDScript, e quase
nenhum path= de .tscn tem uid= como companheiro. Mover arquivo na mao quebra
referencia, e conferir uma a uma nao escala.

Foi usado nas duas movimentacoes de 2026-09-09:
  Fase 2  district/harbor_preview -> world/harbor  (+5 pastas)  306 arquivos, 602 substituicoes
  Fase 3  Main.tscn e district/   -> legacy/       (+extracoes)  105 arquivos, 169 substituicoes

Fica aqui para a Fase 4 (reorganizar os ~72 scripts da raiz em subpastas
tematicas), que e a movimentacao maior e ainda pendente.

## Como usar

1. Edite MOVES abaixo com os pares (origem, destino), relativos a raiz do projeto.
2. python tools/move_folder_refactor.py --dry-run     # confira a lista
3. python tools/move_folder_refactor.py               # executa
4. python tools/check_references.py                   # tem que dar 0 quebras novas
5. GODOT --path . --import                            # OBRIGATORIO: reconstroi o
                                                      # cache global de class_name
6. GODOT --path . --script res://tests/profile_load_time_0909.gd   # carrega de verdade

O passo 5 nao e opcional. O registro de class_name do Godot
(.godot/global_script_class_cache.cfg) continua apontando para os caminhos
antigos depois de um move e quebra a resolucao de classes MESMO com todas as
strings corretas. O check_references.py nao pega isso; so o carregamento pega.

## Cuidados embutidos

- git mv quando o arquivo e rastreado (preserva historico), mv quando nao e.
- Leva junto os companheiros .uid (scripts) e .import (assets).
- Substitui sempre com o prefixo res:// para nao acertar mencao em prosa.
- A ordem de MOVES importa: coloque o caminho mais especifico ANTES do mais
  generico, senao o generico consome o especifico. Exemplo real da Fase 3:
  city_demo/art -> assets/art precisou vir antes de city_demo -> legacy/city_demo.
- .claude/ fica de fora: e configuracao de ferramenta do usuario, nao codigo.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".godot", ".git", "OLD", ".claude"}
EDIT_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".json", ".md"}
DRY = "--dry-run" in sys.argv

# (origem, destino) relativos a raiz do projeto. Do mais especifico ao mais generico.
# Fase 4 (docs/PLANO_REORGANIZACAO_PASTAS.md): dominio economy/, o menor e mais
# isolado, primeiro para validar o procedimento antes dos dominios maiores.
MOVES: list[tuple[str, str]] = [
    ("Collectible.gd", "economy/Collectible.gd"),
    ("CollectibleCatalog.gd", "economy/CollectibleCatalog.gd"),
    ("CashPickup.gd", "economy/CashPickup.gd"),
    ("HealthPickup.gd", "economy/HealthPickup.gd"),
    ("AchievementCatalog.gd", "economy/AchievementCatalog.gd"),
]


def is_tracked(rel: str) -> bool:
    return subprocess.run(
        ["git", "ls-files", "--error-unmatch", rel],
        cwd=ROOT, capture_output=True, text=True,
    ).returncode == 0


def move_one(src_rel: str, dst_rel: str) -> None:
    src = ROOT / src_rel
    if not src.exists():
        print(f"   SKIP (nao existe): {src_rel}")
        return
    if not DRY:
        (ROOT / dst_rel).parent.mkdir(parents=True, exist_ok=True)
    if is_tracked(src_rel):
        if DRY:
            print(f"   [dry] git mv {src_rel} -> {dst_rel}")
        else:
            r = subprocess.run(["git", "mv", src_rel, dst_rel], cwd=ROOT,
                               capture_output=True, text=True)
            status = "" if r.returncode == 0 else f"  [ERRO: {r.stderr.strip()}]"
            print(f"   git mv  {src_rel} -> {dst_rel}{status}")
    else:
        if not DRY:
            src.rename(ROOT / dst_rel)
        print(f"   mv      {src_rel} -> {dst_rel}")


def main() -> int:
    if not MOVES:
        print("MOVES esta vazio -- edite a lista no topo do arquivo antes de rodar.")
        print("Ver o docstring para o procedimento completo (o passo --import e obrigatorio).")
        return 1

    print("=== movendo ===")
    for src, dst in MOVES:
        move_one(src, dst)
        for suffix in (".uid", ".import"):
            if (ROOT / f"{src}{suffix}").exists():
                move_one(f"{src}{suffix}", f"{dst}{suffix}")

    replacements = [(f"res://{s}", f"res://{d}") for s, d in MOVES]

    print("\n=== reescrevendo referencias ===")
    changed = subs = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix not in EDIT_SUFFIXES:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            original = text
            here = 0
            for old, new in replacements:
                count = text.count(old)
                if count:
                    text = text.replace(old, new)
                    here += count
            if text != original:
                changed += 1
                subs += here
                if not DRY:
                    # newline="" preserva as quebras de linha originais do arquivo
                    path.write_text(text, encoding="utf-8", newline="")
                if here > 4:
                    print(f"   {str(path.relative_to(ROOT))}: {here}")

    print(f"\narquivos alterados: {changed}")
    print(f"substituicoes: {subs}")
    print("\nAgora: check_references.py, depois --import, depois carregar o jogo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
