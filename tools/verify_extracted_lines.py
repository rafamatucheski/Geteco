"""Confere uma extração para auxiliar RefCounted (estilo gameplay/GameplayCombatSound.gd).

Toda linha não vazia que saiu do dono (diff contra uma revisão do Git) tem de reaparecer, na mesma
ordem e sem sobra, no corpo dos auxiliares (do primeiro `func` ou `static func` que não é `_init`,
com os `##` e `static var` colados acima dele, até o fim). Normaliza só o prefixo `g.` (e `self` do dono como `g`) e a anotação de tipo de `var` (`:=` vira `: T =`
quando o valor passa a vir de `g.`, que é Node3D e não infere tipo). O mesmo vale para o padrão de
parâmetro (`x := C` vira `x: T = g.C`), e `g.get_script().` (como se lê `static var` do dono) conta
como `g.`.

Com `--split` (função longa quebrada em etapas no auxiliar): linhas novas no auxiliar são aceitas e
listadas para revisão (cabeçalhos e chamadas das etapas); as removidas continuam tendo de reaparecer
todas, na ordem, e `x = ...` do dono pode virar `var x := ...` (local que passou a nascer na etapa).

Uso: python tools/verify_extracted_lines.py [--split] <rev> <dono.gd> <auxiliar.gd> [<auxiliar.gd>...]
Ex.: python tools/verify_extracted_lines.py HEAD world/regions/NativeRegion.gd \\
         world/regions/NativeLand.gd world/regions/NativeRoadSurfaces.gd
"""
import difflib
import re
import subprocess
import sys


SPLIT = False


def norm(line: str) -> str:
    # `self` do dono vira `g` no auxiliar (ex.: TUNNEL_CUTAWAY.prime(chunk, g, rect)).
    line = re.sub(r'(?<![\w.])self\b', 'g', line)
    line = re.sub(r'(?<![\w.])g\.get_script\(\)\.', '', line)
    line = re.sub(r'(?<![\w.])g\.', '', line)
    if re.match(r'(static )?func ', line):
        line = re.sub(r'\b(\w+): [\w\[\]]+ = ', r'\1 := ', line)
    line = re.sub(r'\bvar (\w+)(?:: [\w\[\]]+ =| :=)', r'var \1 :=', line)
    if SPLIT:
        line = re.sub(r'^(\s*)var (\w+) := ', r'\1\2 = ', line)
    return line


def helper_body(lines: list[str]) -> list[str]:
    # Auxiliar estático (só `static func`, ex.: CityNightLamps) também vale; o `##` e a `static var`
    # colados acima do primeiro func (sem linha em branco) contam como corpo, como no dono.
    # Com `_init(host)`, o corpo é tudo o que vem depois dele: constantes e campos que saíram do dono no
    # meio do bloco (ex.: CACHED_* do NativeRecordCache, antes do primeiro func movido) também contam.
    init = next((i for i, l in enumerate(lines) if l.startswith('func _init(')), None)
    if init is not None:
        start = init + 1
        while start < len(lines) and (lines[start].startswith('\t') or not lines[start].strip()):
            start += 1
        return [norm(l) for l in lines[start:] if l.strip()]
    start = next(i for i, l in enumerate(lines) if (l.startswith('func ') or l.startswith('static func '))
                 and not l.startswith('func _init('))
    while start > 0 and (lines[start - 1].startswith('##') or lines[start - 1].startswith('static var ')):
        start -= 1
    return [norm(l) for l in lines[start:] if l.strip()]


def main() -> int:
    global SPLIT
    args = sys.argv[1:]
    if '--split' in args:
        SPLIT = True
        args.remove('--split')
    if len(args) < 3:
        print(__doc__)
        return 2
    rev, owner, helpers = args[0], args[1], args[2:]
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
    ops = difflib.SequenceMatcher(None, wanted, moved, autojunk=False).get_opcodes()
    bad = [op for op in ops if op[0] != 'equal' and not (SPLIT and op[0] == 'insert')]
    if SPLIT:
        for tag, i1, i2, j1, j2 in ops:
            if tag == 'insert':
                for l in moved[j1:j2]:
                    print('  novo no auxiliar:', l[:160])
    for tag, i1, i2, j1, j2 in bad:
        print('DIVERGE (%s): dono %r / auxiliar %r' % (tag, wanted[i1:i2], moved[j1:j2]))
    if bad:
        return 1
    print('OK: as %d linhas removidas reaparecem, na mesma ordem e sem sobra, nos auxiliares' % len(removed))
    return 0


if __name__ == '__main__':
    sys.exit(main())
