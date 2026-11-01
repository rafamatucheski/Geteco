"""Confere as funções privadas que viraram públicas em FullSession, ProductionWorld e Gameplay.

Em 01/11 (item 2 de docs/analise-arquitetura-codigo-20261101.md) cada `_x` usada de fora ganhou a
pública `x`; uma das duas é delegação de uma linha para a outra. Este script acha esses pares pelo
próprio código (linha `func _x(...): x(...)` ou `func x(...): _x(...)`) e falha se:
- a pública não existe, aparece duas vezes ou colide com var/const/signal/enum/classe do dono;
- a pública tem nome de método ou propriedade de Object/Node/Node3D (sombrearia o motor);
- uma subclasse de teste declara var/const com o nome da pública;
- algum arquivo fora do dono e dos auxiliares ainda chama a privada por `session.`, `world.`,
  `production.` ou `gameplay.` (direto ou por nome em Callable/has_method/call).

Uso: python tools/check_promoted_privates.py   (sai 0 se tudo certo, 1 se achou problema)
Não substitui rodar o Godot: só confere nomes e texto.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OWNERS = {
    "FullSession": ("runtime/FullSession.gd", r"runtime/Session\w+\.gd$", ["session"]),
    "ProductionWorld": ("runtime/ProductionWorld.gd", None, ["world", "production", "controller"]),
    "Gameplay": ("gameplay/Gameplay.gd", r"gameplay/Gameplay(?!HUD)\w+\.gd$", ["gameplay"]),
}
# Membros de Object/Node/Node3D que uma pública nova não pode repetir.
BUILTIN = set("""
free get set call callv call_deferred connect disconnect emit_signal has_method has_signal notification
queue_free add_child remove_child get_node get_parent get_tree process physics_process input ready name
owner visible position rotation scale transform basis global_position global_transform global_rotation
show hide update update_gizmos translate rotate look_at duplicate replace_by print_tree get_index
move_child set_process set_physics_process propagate_call propagate_notification is_inside_tree
get_viewport get_window rpc rpc_id set_meta get_meta has_meta to_string get_class is_class set_script
get_script tr tr_n can_process top_level quaternion rotation_degrees reparent get_children get_child
get_child_count find_child find_children unique_name_in_owner process_mode scene_file_path
editor_description multiplayer process_priority physics_process_priority auto_translate_mode
visibility_parent gizmo force_update_transform orthonormalize set_identity is_visible_in_tree
""".split())


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
        return handle.read()


def gd_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", ".claude")]
        for name in files:
            if name.endswith(".gd"):
                yield os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, "/")


def top_level(src):
    names = {}
    patterns = [
        ("func", r"^(?:static\s+)?func\s+(\w+)"),
        ("var", r"^(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)"),
        ("const", r"^const\s+(\w+)"),
        ("signal", r"^signal\s+(\w+)"),
        ("enum", r"^enum\s+(\w+)"),
        ("class", r"^class\s+(\w+)"),
    ]
    for kind, pattern in patterns:
        for match in re.finditer(pattern, src, re.M):
            names.setdefault(match.group(1), []).append(kind)
    return names


def promoted_pairs(src):
    pairs = set()
    for match in re.finditer(r"^func\s+(_?)(\w+)\s*\(.*?\)\s*(?:->\s*[\w\[\]., ]+)?\s*:\s*(?:return\s+)?(?:await\s+)?(_?)(\w+)\(", src, re.M):
        lead, name, call_lead, called = match.groups()
        if name == called and lead != call_lead and not name.startswith("_"):
            pairs.add(name)
    return sorted(pairs)


def subclasses(owner_rel):
    """Devolve {arquivo:classe -> conjunto de var/const} das classes que estendem o dono."""
    found = {}
    for rel in gd_files():
        src = read(rel)
        consts = dict(re.findall(r'const\s+(\w+)\s*:?=\s*preload\("res://([^"]+)"\)', src))
        lines = src.split("\n")
        for index, line in enumerate(lines):
            match = re.match(r'^(\s*)(?:class\s+(\w+)\s+)?extends\s+(?:"res://([^"]+)"|(\w+))', line)
            if not match or (match.group(3) or consts.get(match.group(4) or "")) != owner_rel:
                continue
            indent = len(match.group(1))
            if match.group(2) is None and indent == 0:
                body = lines
            else:
                body = []
                for other in lines[index + 1:]:
                    if other.strip() and len(other) - len(other.lstrip()) <= indent:
                        break
                    body.append(other)
            members = set()
            for other in body:
                member = re.match(r"\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:var|const)\s+(\w+)", other)
                if member and len(other) - len(other.lstrip()) == (0 if body is lines else indent + 1):
                    members.add(member.group(1))
            found[f"{rel}:{match.group(2) or '<arquivo>'}"] = members
    return found


def main():
    problems = []
    total = 0
    for owner, (owner_rel, aux_pattern, variables) in OWNERS.items():
        src = read(owner_rel)
        names = top_level(src)
        pairs = promoted_pairs(src)
        total += len(pairs)
        for public in pairs:
            if names.get(public) != ["func"]:
                problems.append(f"{owner}.{public}: esperado uma func, achado {names.get(public)}")
            if names.get("_" + public) != ["func"]:
                problems.append(f"{owner}._{public}: privada sumiu ou duplicou ({names.get('_' + public)})")
            if public in BUILTIN:
                problems.append(f"{owner}.{public}: repete nome embutido do Godot")
        for where, members in subclasses(owner_rel).items():
            for public in sorted(members & set(pairs)):
                problems.append(f"{owner}.{public}: subclasse {where} declara var/const com esse nome")
        if not pairs:
            continue
        joined = "|".join(pairs)
        holders = "|".join(variables)
        direct = re.compile(r"\b(?:%s)\._(%s)\b" % (holders, joined))
        by_name = re.compile(r'(?:Callable\(\s*(?:%s)\s*,\s*|\b(?:%s)\.(?:call|call_deferred|callv|has_method)\(\s*)"_(%s)"' % (holders, holders, joined))
        for rel in gd_files():
            if rel == owner_rel or (aux_pattern and re.match(aux_pattern, rel)):
                continue
            text = read(rel)
            for pattern in (direct, by_name):
                for match in pattern.finditer(text):
                    line = text.count("\n", 0, match.start()) + 1
                    problems.append(f"{rel}:{line}: ainda usa {owner}._{match.group(1)}; use {match.group(1)}")
        print(f"{owner}: {len(pairs)} públicas promovidas: {', '.join(pairs)}")
    for problem in problems:
        print("PROBLEMA", problem)
    print(f"PROMOTED_PRIVATES total={total} problemas={len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
