"""Confere a troca das cadeias session.world.* pela fachada de jogador do FullSession.

Item 1 de docs/analise-arquitetura-codigo-20261101.md: as leituras
session.world.player.global_position / .player.position / .gameplay.health / .driving.occupied /
.driving.car viraram session.player_position() / player_local_position() / player_health() /
player_in_vehicle() / player_vehicle(). Este script compara cada .gd fora de tests/ com a versão
de uma referência do Git e falha se:
- desfazendo a troca (fachada -> cadeia) o arquivo não volta byte a byte ao que era
  (ou seja, mudou algo além das leituras);
- alguma chamada da fachada ficou do lado esquerdo de uma atribuição (seria escrita trocada);
- o número de escritas pela cadeia (session.world.<cadeia>[.membro] = / += / -= ...) mudou.
O próprio runtime/FullSession.gd é conferido sem o bloco que define a fachada.

Uso: python tools/check_player_query_reads.py [ref]   (ref padrão: HEAD; sai 0 se tudo certo)
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAINS = {
    "player_position()": "player.global_position",
    "player_local_position()": "player.position",
    "player_health()": "gameplay.health",
    "player_in_vehicle()": "driving.occupied",
    "player_vehicle()": "driving.car",
}
FACADE = re.compile(r"\bsession\.(%s)" % "|".join(re.escape(k) for k in CHAINS))
CHAIN = re.compile(r"\bsession\.world\.(%s)\b" % "|".join(re.escape(v) for v in CHAINS.values()))
TRAIL = re.compile(r"(?:\.\w+|\[[^\[\]]*\])*")
ASSIGN = re.compile(r"\s*(=(?!=)|\+=|-=|\*=|/=|%=|\*\*=|<<=|>>=|&=|\|=|\^=)")
FACADE_BLOCK = re.compile(r"^## Fachada de leitura do jogador.*?^func player_vehicle\(\): return world\.driving\.car\n\n", re.M | re.S)


def writes(text, pattern):
    found = 0
    for match in pattern.finditer(text):
        if ASSIGN.match(text, TRAIL.match(text, match.end()).end()):
            found += 1
    return found


def at_ref(ref, rel):
    result = subprocess.run(["git", "-C", ROOT, "show", f"{ref}:{rel}"], capture_output=True)
    return result.stdout.decode("utf-8") if result.returncode == 0 else None


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    changed = subprocess.run(["git", "-C", ROOT, "diff", "--name-only", ref, "--", "*.gd"],
                             capture_output=True, text=True).stdout.split()
    problems = []
    swapped = 0
    checked = 0
    for rel in changed:
        if rel.startswith("tests/") or os.path.basename(rel).startswith("test_"):
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as handle:
            now = handle.read()
        before = at_ref(ref, rel)
        if before is None:
            continue
        if rel == "runtime/FullSession.gd":
            now = FACADE_BLOCK.sub("", now, count=1)
        uses = len(FACADE.findall(now))
        if not uses:
            continue
        checked += 1
        swapped += uses
        undone = FACADE.sub(lambda m: "session.world." + CHAINS[m.group(1)], now)
        if undone != before:
            problems.append(f"{rel}: muda algo além de trocar leitura por fachada")
        lhs = writes(now, FACADE)
        if lhs:
            problems.append(f"{rel}: {lhs} chamada(s) da fachada do lado esquerdo de atribuição")
        if writes(before, CHAIN) != writes(now, CHAIN):
            problems.append(f"{rel}: escritas pela cadeia mudaram ({writes(before, CHAIN)} -> {writes(now, CHAIN)})")
    for problem in problems:
        print("PROBLEMA", problem)
    print(f"PLAYER_QUERY arquivos={checked} leituras_trocadas={swapped} problemas={len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
