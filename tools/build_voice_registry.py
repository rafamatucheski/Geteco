"""Registro das falas da campanha para gerar as vozes (21/10/2026).

Junta toda fala de missão que o jogo mostra em legenda e grava `data/campaign/voice-registry.json`
com, para cada uma: quem fala, o texto da legenda, o texto falado (sem as direções entre
parênteses), a chave da gravação que o jogo procura e se já existe gravação.

A chave é a mesma de audio/ExpressiveVoice.gd (`recording_key`): sha256 de
`personagem_em_minusculas + "|" + texto_da_legenda`, com o personagem tirado do nome que aparece na
legenda até o " · " (o "Joana · rádio" é a voz "joana"). Gere o WAV com essa chave no nome e
registre no manifesto de vozes como as falas de Harbor (audio/mission_voices/harbor_story/).

Fontes lidas:
- runtime/desert/act2/*.gd: linhas `["Quem", "texto"]` nas funções de falas (ato 2);
- data/campaign/*.json: entradas com `speaker` e `pt` (ato 1, missões novas, prólogo).

Fala com %d/%s no texto muda conforme o jogo (contagem de cartas, tempo da corrida): vai marcada
`variavel` e sem chave fixa; grave as variações quando o texto final estiver decidido.

Uso: python -I tools/build_voice_registry.py   (sem Godot, segundos)
"""
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "campaign", "voice-registry.json")
GD_SOURCES = [os.path.join(ROOT, "runtime", "desert", "act2", name) for name in ("VicenteReunion.gd", "Act2Lines.gd")]
JSON_DIR = os.path.join(ROOT, "data", "campaign")
SKIP_JSON = {"voice-registry.json", "campaign_v1.json", "harbor-story.json", "narrative-source.json", "source-flags.json"}
MANIFESTS = [
    os.path.join(ROOT, "audio", "mission_voices", "harbor_story", "production.json"),
    os.path.join(ROOT, "audio", "mission_voices", "recordings.json"),
    os.path.join(ROOT, "audio", "mission_voices", "maciota_baritone", "recordings.json"),
]

LINE = re.compile(r'\[\s*"((?:[^"\\]|\\.)+)"\s*,\s*(String\(TranslationServer\.translate\()?"((?:[^"\\]|\\.)*)"')
FUNC = re.compile(r'^static func (\w+)\(', re.M)
STAGE_DIRECTION = re.compile(r"\([^)]*\)")


def persona_of(speaker: str) -> str:
    return speaker.lower().split(" · ")[0].strip()


def key_of(persona: str, text: str) -> str:
    return hashlib.sha256((persona + "|" + text).encode("utf-8")).hexdigest()


def spoken(text: str) -> str:
    return re.sub(r"\s+", " ", STAGE_DIRECTION.sub("", text)).strip()


def recorded_keys() -> set:
    keys = set()
    for path in MANIFESTS:
        if not os.path.exists(path):
            continue
        data = json.load(open(path, encoding="utf-8"))
        if isinstance(data, dict):
            for item in data.get("lines", []):
                if isinstance(item, dict) and item.get("key"):
                    keys.add(item["key"])
            for k in data.keys():
                if re.fullmatch(r"[0-9a-f]{64}", str(k)):
                    keys.add(k)
    return keys


def gd_lines(path: str):
    src = open(path, encoding="utf-8").read()
    starts = [(m.start(), m.group(1)) for m in FUNC.finditer(src)]
    for m in LINE.finditer(src):
        section = ""
        for pos, name in starts:
            if pos <= m.start():
                section = name
        # No VicenteReunion.gd só as funções de falas (*_lines); o resto do arquivo tem listas de nomes.
        if path.endswith("VicenteReunion.gd") and not section.endswith("_lines"):
            continue
        speaker = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
        text = m.group(3).replace('\\"', '"')
        yield speaker, text, os.path.relpath(path, ROOT).replace("\\", "/") + ":" + section


def json_lines(path: str):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (ValueError, OSError):
        return

    def walk(node, section):
        if isinstance(node, dict):
            if isinstance(node.get("speaker"), str) and isinstance(node.get("pt"), str):
                yield node["speaker"], node["pt"], section
            for k, v in node.items():
                yield from walk(v, section + "/" + str(k) if section else str(k))
        elif isinstance(node, list):
            for v in node:
                yield from walk(v, section)

    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    for speaker, text, section in walk(data, ""):
        yield speaker, text, rel + ":" + section


def main() -> int:
    recorded = recorded_keys()
    rows, seen = [], set()
    sources = []
    for path in GD_SOURCES:
        if os.path.exists(path):
            sources.append(gd_lines(path))
    for name in sorted(os.listdir(JSON_DIR)):
        if name.endswith(".json") and name not in SKIP_JSON:
            sources.append(json_lines(os.path.join(JSON_DIR, name)))
    for source in sources:
        for speaker, text, where in source:
            persona = persona_of(speaker)
            variable = bool(re.search(r"%[ds]", text))
            only_direction = spoken(text) == ""
            key = "" if variable else key_of(persona, text)
            ident = (persona, text, where)
            if ident in seen:
                continue
            seen.add(ident)
            rows.append({
                "speaker": speaker,
                "persona": persona,
                "text": text,
                "spoken": spoken(text),
                "key": key,
                "source": where,
                "variavel": variable,
                "so_direcao": only_direction,
                "gravada": bool(key) and key in recorded,
            })
    to_record = [r for r in rows if not r["gravada"] and not r["so_direcao"]]
    summary = {
        "gerado_por": "tools/build_voice_registry.py",
        "chave": "sha256(personagem|texto da legenda), como audio/ExpressiveVoice.gd recording_key",
        "total": len(rows),
        "gravadas": sum(1 for r in rows if r["gravada"]),
        "a_gravar": len(to_record),
        "por_personagem": {},
        "falas": rows,
    }
    for r in to_record:
        summary["por_personagem"][r["persona"]] = summary["por_personagem"].get(r["persona"], 0) + 1
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(rows)} falas; {summary['gravadas']} gravadas; {len(to_record)} a gravar -> {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
