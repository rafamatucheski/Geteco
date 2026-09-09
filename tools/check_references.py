#!/usr/bin/env python3
"""Verifica se toda referencia res:// do projeto aponta para um arquivo que existe.

Este projeto referencia recursos por STRING de caminho, nao por UID: sao ~653
preload("res://...") e ~903 load("res://...") em GDScript, e dos 133 path= em
.tscn so 15 tem uid= como companheiro. Ou seja, mover ou renomear uma pasta
quebra referencia de verdade -- o UID do Godot nao salva a operacao.

Este script e a rede de segurança para qualquer movimentacao de arquivos:
rode antes e depois, e compare. Sai com codigo 1 se achar algo quebrado.

Uso:
    python tools/check_references.py            # relatorio normal
    python tools/check_references.py --verbose  # lista tambem as sondagens opcionais

Dois casos NAO contam como quebra, e sao detectados pelo contexto no proprio
arquivo em vez de uma lista fixa:

1. Sondagem opcional -- caminho citado dentro de ResourceLoader.exists(...).
   E um teste de existencia proposital, com fallback (ProceduralAudio.gd faz
   isso para assets de audio opcionais).
2. Destino de escrita -- caminho passado para save_png(), ResourceSaver.save()
   ou FileAccess.open(..., WRITE). O arquivo ainda nao existe porque e a SAIDA
   do script, nao a entrada (os scripts capture_*.gd de tests/ fazem isso).
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".godot", ".git", "OLD"}
SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".json"}

# Quebras reais ja existentes, registradas para o script poder servir de portao
# (falha so em quebra NOVA) sem varrer o problema para debaixo do tapete.
# Devem ser corrigidas e removidas daqui -- nao e lugar para acumular divida.
KNOWN_BROKEN = {
    # RegionTravel.gd:190 faz load("res://PlayerCar.tscn").instantiate() e esse
    # arquivo nao existe em lugar nenhum do projeto: load() devolve null e o
    # .instantiate() estoura. E autoload, no caminho que reconstroi o veiculo a
    # partir do save. Encontrado em 2026-09-09 por esta ferramenta.
    "PlayerCar.tscn": "RegionTravel.gd:190 -- load() de cena inexistente, crash latente",
}

RES_REF = re.compile(r"res://([A-Za-z0-9_\-./]+\.[A-Za-z0-9]+)")
EXISTS_PROBE = re.compile(r'ResourceLoader\.exists\(\s*"res://([^"]+)"')
WRITE_CALL = r"(?:save_png|save_jpg|save_webp|ResourceSaver\.save|FileAccess\.open)"
# Caminho literal direto na chamada de escrita: img.save_png("res://...")
WRITE_TARGET = re.compile(WRITE_CALL + r'\([^)]*?"res://([^"]+)"')
# Caminho guardado em variavel e so entao escrito:
#   var save_path := "res://..."   ...   img.save_png(save_path)
VAR_ASSIGN = re.compile(r'\b(\w+)\s*:?=\s*"res://([^"]+)"')
WRITE_VAR = re.compile(WRITE_CALL + r"\(\s*(\w+)\s*[),]")


def scan_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix in SCAN_SUFFIXES:
                yield path


def main() -> int:
    verbose = "--verbose" in sys.argv

    # caminho -> lista de arquivos que o citam
    references: dict[str, list[str]] = {}
    # caminhos testados com ResourceLoader.exists() ou usados como destino de escrita
    probed: set[str] = set()
    written: set[str] = set()

    for path in scan_files():
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        rel = str(path.relative_to(ROOT)).replace("\\", "/")

        probed |= {m.group(1) for m in EXISTS_PROBE.finditer(text)}
        written |= {m.group(1) for m in WRITE_TARGET.finditer(text)}

        # variaveis que recebem um caminho literal e depois vao para uma escrita
        written_vars = {m.group(1) for m in WRITE_VAR.finditer(text)}
        if written_vars:
            written |= {
                m.group(2)
                for m in VAR_ASSIGN.finditer(text)
                if m.group(1) in written_vars
            }

        for match in RES_REF.finditer(text):
            references.setdefault(match.group(1), []).append(rel)

    missing = {r: src for r, src in references.items() if not (ROOT / r).exists()}
    optional = {r: src for r, src in missing.items() if r in probed}
    outputs = {r: src for r, src in missing.items() if r in written and r not in probed}
    all_broken = {
        r: src for r, src in missing.items() if r not in probed and r not in written
    }
    known = {r: src for r, src in all_broken.items() if r in KNOWN_BROKEN}
    broken = {r: src for r, src in all_broken.items() if r not in KNOWN_BROKEN}

    print(f"referencias res:// distintas : {len(references)}")
    print(f"sondagens opcionais (ok)     : {len(optional)}")
    print(f"destinos de escrita (ok)     : {len(outputs)}")
    print(f"quebras conhecidas (a corrigir): {len(known)}")
    print(f"QUEBRADAS NOVAS              : {len(broken)}")

    if known:
        print("\n--- quebras ja conhecidas (nao falham a verificacao) ---")
        for ref in sorted(known):
            print(f"  res://{ref}\n      {KNOWN_BROKEN[ref]}")

    if verbose:
        for label, group in (
            ("sondagens opcionais (ResourceLoader.exists, tem fallback)", optional),
            ("destinos de escrita (saida do script, nao entrada)", outputs),
        ):
            if group:
                print(f"\n--- {label} ---")
                for ref in sorted(group):
                    print(f"  {ref}  <- {group[ref][0]}")

    if broken:
        print("\n--- REFERENCIAS QUEBRADAS ---")
        for ref in sorted(broken):
            sources = broken[ref]
            extra = f" (+{len(sources) - 1} outros)" if len(sources) > 1 else ""
            print(f"  res://{ref}")
            print(f"      citado por: {sources[0]}{extra}")
        return 1

    print("\nOK: nenhuma referencia quebrada nova.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
