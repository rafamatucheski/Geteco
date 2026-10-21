"""Gera a tabela de falas do painel "Dublagem Geteco" (uma linha por fala do roteiro).

Classifica cada personagem (protagonista, principal, secundário, genérico) e cada fala
(principal, secundária, reação), diz qual motor de voz ela usa e o estado do áudio em PT-BR e inglês: ElevenLabs,
banco local (Qwen) ou sem áudio. Rodar de novo depois de cada lote e reenviar o arquivo.
Uso: python tools/build_voice_dashboard_data.py <saida.json>
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTED = ROOT / "audio/mission_voices/directed"

# Missões da história: o que o jogador precisa ouvir para seguir a trama.
MAIN_STORY = {"arrival", "garage", "garage_legacy", "opening_ferry", "first-favors-dialogue.json", "cobra-dialogue.json",
              "jessica-dialogue.json", "epilogue", "mountain_story", "desert_campaign", "takeshi_honor", "race_finale",
              "race", "gameplay/urban_v1/TruckersVillageSecretPassage.gd"}
# Bordões que tocam muitas vezes e por sorteio: merecem vários tons.
REACTIONS = {"combat_pain", "civilian_reaction", "building_social", "building_warning", "village_home_intrusion",
             "fuel_robbery", "vertice"}
GENERIC_PREFIXES = ("civilian", "guarda", "polícia", "funcionári", "operador", "operário", "village resident",
                    "fuel cashier", "passenger", "moradora")
# Decisão do usuário (21/10): ElevenLabs só para o elenco central, de falas longas e com contexto;
# rua, mendigos, aleatórios e o resto do elenco ficam no banco local (Qwen).
# Decidido por identidade (voice-cast.json), não por nome: o "caller" é o Maciota e só a Helena
# bancária (helena_bank) é ElevenLabs. Lote A: Dante e Maciota; lote B: Helena, Takeshi e Vicente.
ELEVEN_BATCH = {"dante": "A", "maciota": "A", "helena_bank": "B", "takeshi": "B", "vicente": "B"}


def character(cast: dict, row: dict) -> str:
    person = cast.get(row["speaker"], {})
    for variant in person.get("variants", []):
        if row["key"] in variant.get("line_keys", []):
            return variant.get("default_character", variant.get("alias_of", variant.get("id")))
    return person.get("default_character", person.get("alias_of", person.get("id", "")))


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def main() -> None:
    out = Path(sys.argv[1])
    lines = load(ROOT / "data/dialogue/voice-line-direction.json")["lines"]
    cast = load(ROOT / "data/dialogue/voice-cast.json")["personas"]
    eleven = load(DIRECTED / "elevenlabs.json").get("lines", {})
    local = load(DIRECTED / "runtime.json").get("lines", {})
    section = lambda row: row["source_section"].split(":")[0]
    story_speakers = {row["speaker"] for row in lines if section(row) in MAIN_STORY}

    def tier(speaker: str) -> str:
        if speaker == "dante": return "Protagonista"
        if speaker.startswith(GENERIC_PREFIXES): return "Genérico"
        return "Principal" if speaker in story_speakers else "Secundário"

    def status(lang: str, key: str) -> str:
        if key in eleven.get(lang, {}): return "ElevenLabs"
        if key in local.get(lang, {}): return "Banco local"
        return "Sem áudio"

    rows = []
    for row in lines:
        speaker, key, where = row["speaker"], row["key"], section(row)
        npc_tier = tier(speaker)
        if where in MAIN_STORY: importance = "Principal"
        elif where in REACTIONS or (where == "spoken_notice" and npc_tier == "Genérico"): importance = "Reação"
        else: importance = "Secundária"
        who = character(cast, row)
        engine = "ElevenLabs" if who in ELEVEN_BATCH else "Banco local"
        batch = ELEVEN_BATCH.get(who, "Qwen")
        pt, en = status("pt_BR", key), status("en", key)
        # O que falta: no elenco ElevenLabs, tudo que ainda não veio de lá; no Qwen, o que não tem áudio.
        pending = lambda value: value != "ElevenLabs" if engine == "ElevenLabs" else value == "Sem áudio"
        variants = len(eleven.get("pt_BR", {}).get(key, {}).get("variants", []))
        rows.append({"id": key[:12], "personagem": speaker, "tipo_personagem": npc_tier, "importancia": importance,
                     "lote": batch, "motor": engine, "status_pt": pt, "status_en": en,
                     "falta_pt": pending(pt), "falta_en": pending(en),
                     "tons_pt": variants or (1 if key in eleven.get("pt_BR", {}) else 0),
                     "fala_pt": row["spoken_pt"], "fala_en": row.get("spoken_en", ""), "intencao": row.get("intent", ""),
                     "onde": row["source_section"], "personagem_id": who, "caracteres_pt": len(row["spoken_pt"]),
                     "caracteres_en": len(row.get("spoken_en", ""))})
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=0), encoding="utf-8")
    done = sum(r["status_pt"] == "ElevenLabs" for r in rows)
    print(f"VOICE_DASHBOARD rows={len(rows)} elevenlabs_pt={done} at={datetime.now(timezone.utc).isoformat(timespec='seconds')}")


if __name__ == "__main__":
    main()
