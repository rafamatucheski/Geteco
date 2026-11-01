"""Confere uma extração para auxiliar RefCounted (estilo gameplay/GameplayCombatSound.gd).

Toda linha não vazia que saiu do dono (diff contra uma revisão do Git) tem de reaparecer, na mesma
ordem e sem sobra, no corpo dos auxiliares (do primeiro `func` que não é `_init`, com os `##` colados
acima dele, até o fim). Normaliza só o prefixo `g.` e a anotação de tipo de `var` (`:=` vira `: T =`
quando o valor passa a vir de `g.`, que é Node3D e não infere tipo).

Uso: python tools/verify_extracted_lines.py <rev> <dono.gd> <auxiliar.gd> [<auxiliar.gd>...]
Ex.: python tools/verify_extracted_lines.py HEAD world/regions/NativeRegion.gd \\
         world/regions/NativeLand.gd world/regions/NativeRoadSurfaces.gd
"""
import difflib
import re
import subprocess
import sys


def norm(line: str) -> str:
    line = re.sub(r'(?<![\w.])g\.', '', line)
    return re.sub(r'\bvar (\w+)(?:: [\w\[\]]+ =| :=)', r'var \1 :=', line)


def helper_body(lines: list[str]) -> list[str]:
    start = next(i for i, l in enumerate(lines) if l.startswith('func ') and not l.startswith('func _init('))
    while start > 0 and lines[start - 1].startswith('##'):
        start -= 1
    return [norm(l) for l in lines[start:] if l.strip()]


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    rev, owner, helpers = sys.argv[1], sys.argv[2], sys.argv[3:]
    before = subprocess.run(['git', 'show', '%s:%s' % (rev, owner)], check=True, capture_output=True,
                            text=True, encoding='utf-8').stdout.split('\n')
    after = open(owner, encoding='utf-8').read().split('\n')
    removed: list[str] = []
    added: list[str] = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, before, after, autojunk=False).get_opcodes():
        if tag in ('delete', 'replace'):
            removed.extend(l for l in before[i1:i2] if l.strip())
        if tag in ('insert', 'replace'):
            added.extend(l for l in after[j1:j2] if l.strip())
    moved: list[str] = []
    for path in helpers:
        moved.extend(helper_body(open(path, encoding='utf-8').read().split('\n')))
    wanted = [norm(l) for l in removed]
    print('dono %s: %d -> %d linhas; %d removidas, %d acrescentadas (não vazias)'
          % (owner, len(before), len(after), len(removed), len(added)))
    for l in added:
        print('  +', l[:160])
    bad = [op for op in difflib.SequenceMatcher(None, wanted, moved, autojunk=False).get_opcodes() if op[0] != 'equal']
    for tag, i1, i2, j1, j2 in bad:
        print('DIVERGE (%s): dono %r / auxiliar %r' % (tag, wanted[i1:i2], moved[j1:j2]))
    if bad:
        return 1
    print('OK: as %d linhas removidas reaparecem, na mesma ordem e sem sobra, nos auxiliares' % len(removed))
    return 0


if __name__ == '__main__':
    sys.exit(main())
