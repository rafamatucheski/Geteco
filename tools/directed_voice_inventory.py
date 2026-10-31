"""Inventário de fala dirigida: banco antigo mais fala humana autorada só em texto.

Não acrescenta roteamento no runtime e nunca altera o gerador original em inglês.
Toda fala suplementar registra a fonte real e a exigência de vínculo com o locutor.
Sons não verbais e diálogo antigo sem uso são relatados à parte, não passam pelo
texto-para-fala. Papéis procedurais são divididos explicitamente por gênero/personalidade.
"""
from __future__ import annotations
import hashlib
import json
import re
import unicodedata
from pathlib import Path
from english_voice_catalog import inventory as legacy_inventory, ROOT

SOCIAL_SOURCE = "gameplay/civilian_social/CivilianSocialState.gd"
# Fonte em português, inglês de base, personalidades disponíveis (vazio = todas).
SOCIAL_LINES = [
    ("Agora não. Preciso me proteger!", "Not now. I need to get somewhere safe!", ()),
    ("Só um instante.", "Just a moment.", ()),
    ("Guarda essa arma primeiro, por favor.", "Put that gun away first, please.", ()),
    ("Fica longe de mim! Vou pedir ajuda!", "Stay away from me! I'm calling for help!", ()),
    ("Tá... vou respirar um pouco. Me dá espaço.", "Okay... let me catch my breath. Give me some space.", ()),
    ("Tá tudo bem por aqui. Obrigado por perguntar.", "I'm all right. Thanks for asking.", ()),
    ("Depois a gente conversa. Ainda estou tremendo.", "Let's talk later. I'm still shaking.", ()),
    ("Já entendi. Preciso voltar ao que estava fazendo.", "I got it. I need to get back to what I was doing.", ()),
    ("Opa, tudo certo? Bom te ver por aqui.", "Hey, everything all right? Good to see you.", ("friendly",)),
    ("Oi. Tudo bem?", "Hi. Everything okay?", ("reserved", "nervous")),
    ("Hoje estou sem cabeça pra brincadeira.", "I'm not in the mood for jokes today.", ("reserved",)),
    ("Ha! Essa foi boa. Eu precisava rir um pouco.", "Ha! That was a good one. I needed a laugh.", ()),
    ("Depois do susto que você me deu, prefiro ficar na minha.", "After the scare you gave me, I'd rather keep to myself.", ()),
    ("Dia corrido, mas uma conversa boa sempre ajuda.", "Busy day, but a good conversation always helps.", ("friendly",)),
    ("Só quero terminar o dia em paz.", "I just want to get through the day in peace.", ("reserved", "nervous")),
    ("Essa peça está me dando trabalho. Vai ser bom ver tudo funcionando.", "This part's giving me trouble. It'll be good to see it all working.", ()),
    ("Estou cuidando da comida. O segredo é não ter pressa.", "I'm taking care of the food. The trick is not to rush it.", ()),
    ("Papelada não acaba nunca. E você, como está levando o dia?", "The paperwork never ends. How's your day going?", ()),
    ("Estava falando com o pessoal de casa. É bom saber que está tudo bem.", "I was talking to the folks back home. It's good to know they're all right.", ()),
    ("Estou conferindo as coisas. Se eu me perder na conta, começo de novo.", "I'm checking everything. If I lose count, I start over.", ()),
    ("Achei uma leitura boa. Só falta um pouco de sossego pra terminar.", "Found something good to read. I just need some peace to finish it.", ()),
]
BUILDING_WARNINGS = [
    ("Larga essa porta. Você não devia estar aqui.", "Leave that door alone. You shouldn't be here."),
    ("Ei! Vou chamar a polícia!", "Hey! I'm calling the police!"),
]
REACTION_LINES = [
    ("LARGA A ARMA!", "DROP THE GUN!"),
    ("PARA COM ISSO!", "STOP THAT!"),
    ("VOU LIGAR PARA A POLÍCIA!", "I'M CALLING THE POLICE!"),
    ("SAI DAQUI!", "GET OUT OF HERE!"),
]
PANIC_LINES = [("SOCORRO!", "HELP!"), ("CORRE!", "RUN!"), ("CUIDADO!", "WATCH OUT!")]
FUEL_LINES = [
    ("Não vou abrir o caixa! Estou chamando a polícia!", "I'm not opening the till! I'm calling the police!"),
    ("Calma! Vou abrir o caixa...", "Easy! I'll open the till..."),
    ("Leva e vai embora!", "Take it and go!"),
]
SEWER_PERSONAS = [
    "raul", "cida", "beto", "seu abel", "dona marlene", "zeca", "o maluco",
    "padre nicanor", "tita", "tonho", "dona nena", "dona zefa", "beto cascavel",
    "ermitão jacó", "seu tião", "hóspede sete", "velho ozias",
]
PAIN_PERSONAS = SEWER_PERSONAS + [
    "dante", "ferrugem", "moradora", "neco", "nelson", "luísa",
    "guarda", "guarda feminina", "funcionário", "funcionária", "operador", "operadora",
    "operário", "polícia", "polícia feminina", "fuel cashier",
] + ["civilian " + personality + " " + gender
     for personality in ["friendly", "reserved", "nervous", "reaction"]
     for gender in ["male", "female"]] + ["village resident male", "village resident female"]


def _source_line(path: str, text: str) -> int:
    """Falha se o texto autorado mudou/se moveu; nenhum roteiro inventado pode entrar num plano."""
    escaped = json.dumps(text, ensure_ascii=False)[1:-1]
    for number, line in enumerate((ROOT / path).read_text(encoding="utf-8-sig").splitlines(), 1):
        if escaped in line:
            return number
    raise ValueError(f"Supplemental spoken text not found in source: {path}: {text}")


def _character_id(persona: str) -> str:
    normalized = unicodedata.normalize("NFKD", persona).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "_", normalized).strip("_")


def _row(persona, text, en, source, section, binding, *, channel="text"):
    persona = persona.lower()
    return {
        "key": hashlib.sha256((persona + "|" + text).encode("utf-8")).hexdigest(),
        "persona": persona, "text": text, "en": en, "section": section, "aliases": [],
        "source_file": source, "source_line": _source_line(source, text),
        "source_status": "actor_bound_voice_route", "previous_channel": channel,
        "current_channel": "actor-owned spatial voice and localized visible caption",
        "binding": binding,
        "publication_blockers": [],
        "runtime_validation": "Actor-binding focused tests passed; artistic and rendered reviews are separate.",
    }


def supplemental_inventory():
    rows = []
    for personality in ("friendly", "reserved", "nervous"):
        for gender in ("male", "female"):
            persona = f"civilian {personality} {gender}"
            binding = {
                "kind": "procedural_building_resident", "personality": personality,
                "gender": gender, "identity": "specification.id",
                "gender_source": "HarborBuildingResident.resident_model.wardrobe.female",
                "display_name_source": "specification.name",
                "policy": "Bind actual resident id, personality and model gender; never select by display name alone.",
            }
            for pt, en, allowed in SOCIAL_LINES:
                if allowed and personality not in allowed:
                    continue
                row = _row(persona, pt, en, SOCIAL_SOURCE, f"building_social:{personality}", binding, channel="BuildingSocialPanel")
                if gender == "female" and "Obrigado" in pt:
                    row["gender_agreement_note"] = "Fonte compartilhada diz Obrigado; locução/legenda feminina deve dizer Obrigada."
                rows.append(row)
            rows.append(_row(persona, "Pode falar.", "Go ahead.", "runtime/BuildingSocialInteraction.gd", f"building_social:{personality}", binding, channel="BuildingSocialPanel initial greeting"))
            for pt, en in BUILDING_WARNINGS:
                rows.append(_row(persona, pt, en, "world/places/harbor_buildings/HarborBuildingOccupants.gd", f"building_warning:{personality}", binding, channel="show_message without named speaker"))
    for gender in ("male", "female"):
        persona = f"civilian reaction {gender}"
        binding = {
            "kind": "ambient_civilian_reaction", "gender": gender, "identity": "reacting actor persistent id",
            "gender_source": "actor.visual child model wardrobe.female",
            "policy": "Use current actor gender and persist its chosen voice; no random cross-gender panic bank.",
        }
        for pt, en in REACTION_LINES:
            rows.append(_row(persona, pt, en, "gameplay/civilian_reactions/CivilianReactionDirector.gd", "civilian_reaction", binding, channel="Label3D bubble"))
        rows.append(_row(f"village resident {gender}", "Sai da minha casa! Vou chamar o pessoal!", "Get out of my house! I'm calling the others!", "gameplay/urban_v1/TruckersVillageHouseGuards.gd", "village_home_intrusion", {
            "kind": "village_house_resident", "gender": gender, "identity": "village_home_{index}_resident_{slot}",
            "gender_source": "TruckersVillageResidentModel.wardrobe_overrides.female = resident_variant == 1",
            "policy": "Bind the exact resident that detects entry, before the conflict callback.",
        }, channel="show_message without named speaker"))
    for pt, en in FUEL_LINES:
        rows.append(_row("fuel cashier", pt, en, "runtime/Robberies.gd", "fuel_robbery", {
            "kind": "fuel_cashier", "gender": "male", "identity": "fuel clerk generation",
            "gender_source": "FuelCashierModel -> CashierBaseModel -> WinterResidentModel.appearance_female=false; RobberyActor fuel branch does not assign female",
            "policy": "Use displayed FuelCashierModel gender; actor.female is not consumed in the fuel visual branch.",
        }, channel="show_message without named speaker"))
    gift = "Uma Malagousia para conhecer a casa. Ficou guardada com seus vinhos."
    row = _row("nelson", gift, "A Malagousia to get to know the place. It's been added to your wines.", "gameplay/wine/WineRuntime.gd", "wine_gift", {
        "kind": "named_character", "character_id": "nelson", "gender": "male",
        "policy": "Keep Nelson identity; add route for WineRuntime._feedback/UI and its subtitle before audio publication.",
    }, channel="WinePanel feedback or show_message")
    rows.append(row)
    for persona in SEWER_PERSONAS:
        rows.append(_row(persona, "PARE!", "STOP!", "world/places/sewers/SewerResident.gd", "sewer_warning", {
            "kind": "sewer_resident", "identity": "definition.id",
            "character_id": "raul_sewer" if persona == "raul" else _character_id(persona),
            "policy": "Warn only as the struck resident; preserve the same person's voice, fix model-gender binding first.",
        }, channel="Label3D warning after first bare-handed strike"))
    return rows


def inventory():
    rows = [dict(row, source_status="existing_authored_voice_route") for row in legacy_inventory()]
    # O corpo renderizado de guarda/funcionário/polícia já tem gênero estável. Chaves
    # de voz diferentes dividem o texto canônico da ação sem forçar esses corpos a masculinos.
    female_roles = {"guarda": ("guarda feminina", "guarda_female"),
                    "funcionário": ("funcionária", "funcionario_female"),
                    "operador": ("operadora", "operador_female"),
                    "polícia": ("polícia feminina", "policia_female")}
    for source in list(rows):
        if source["persona"] not in female_roles:
            continue
        persona, character_id = female_roles[source["persona"]]
        row = dict(source, persona=persona, aliases=[])
        row["key"] = hashlib.sha256((persona + "|" + source["text"]).encode("utf-8")).hexdigest()
        row["binding"] = {"kind": "gendered_role", "gender": "female", "character_id": character_id,
                          "policy": "VoiceActorBinding resolves the emitting model's final wardrobe; never derive gender from a display label."}
        row["source_status"] = "actor_bound_role_route"
        rows.append(row)
    for gender in ["male", "female"]:
        for pt, en in PANIC_LINES:
            row = _row("civilian reaction " + gender, pt, en,
                       "gameplay/civilian_reactions/CivilianReactionPresenter.gd", "civilian_reaction",
                       {"kind": "civilian_reaction", "gender": gender,
                        "character_id": "civilian_reaction_" + gender,
                        "policy": "Directed panic reuses the exact reacting body's voice; four-second actor cooldown."},
                       channel="actor-owned AudioStreamPlayer3D + Label3D")
            row["source_status"] = "newly_activated_authored_reaction"
            rows.append(row)
    for persona in PAIN_PERSONAS:
        row = _row(persona, "Ai!", "Ow!", "gameplay/Gameplay.gd", "combat_pain", {
            "kind": "actor_bound_pain", "policy": "Reuse an already-bound character identity; anonymous bodies use their gendered reaction role. No voice from a different named character."},
            channel="actor-owned spatial voice + short reactive caption")
        row["source_status"] = "newly_authored_reactive_speech"
        rows.append(row)
    seen = {row["key"] for row in rows}
    for row in supplemental_inventory():
        if row["key"] in seen:
            raise ValueError("Supplement conflicts with a legacy/persona line: " + row["key"])
        seen.add(row["key"])
        rows.append(row)
    return rows


def nonverbal_inventory():
    return [
        {
            "id": "civilian_panic", "kind": "nonverbal_vocalization", "script": None,
            "sources": ["gameplay/civilian_reactions/CivilianReactionPresenter.gd:41"],
            "assets": [f"assets/gameplay/audio/panic_{i}.wav" for i in range(3)],
            "binding": "random asset per scream; no model gender or stable character identity filter",
            "status": "legacy comparison mode only; directed mode uses gender-bound authored panic phrases",
            "active_when": "GETECO_DIRECTED_VOICES=0",
        },
        {
            "id": "combat_pain", "kind": "nonverbal_vocalization", "script": None,
            "sources": ["gameplay/Gameplay.gd:1148"],
            "assets": [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "assets/gameplay/audio").glob("hurt_*.wav"))],
            "binding": "AUDIO.take('hurt'); same pool for player/NPC; pitch 1.0/0.97 does not establish gender",
            "status": "legacy comparison mode only; directed mode uses actor-bound Ai!/Ow! with unchanged cooldown/chance",
            "active_when": "GETECO_DIRECTED_VOICES=0",
        },
        {
            "id": "mining_ambush_panic", "kind": "nonverbal_vocalization", "script": None,
            "sources": ["gameplay/mining/MiningRaid.gd:220"], "assets": ["assets/gameplay/audio/panic_1.wav"],
            "binding": "LAYOUT.SECRET_RETURN + Vector3.UP; anonymous spatial cue",
            "status": "requires listening and concrete emitter attribution",
        },
    ]


def exclusions():
    return [
        {"source": "runtime/ArrivalDialogue.gd:POLICE/PHONE", "status": "legacy_migration_data", "reason": "Source explicitly says current arrival uses HOME_CALL/MEETING/TOUR; ATENDENTE/CONTATO not counted as current cast."},
        {"source": "audio/WorldAudio.gd:STATIONS", "status": "programme_audio_not_character_script", "reason": "12 prerecorded radio programmes; no authored announcer text found in current scripts. Full listening/attribution of programme files remains outside textual inventory."},
        {"source": "cutscenes/opening/v3/opening_audio.gd", "status": "legacy_stems", "reason": "Old voice_pt/voice_en stem playback; current OpeningPresentation selects native FerryFilm. Existing stems are not new current speakers."},
    ]


if __name__ == "__main__":
    rows = inventory()
    print(json.dumps({"lines": len(rows), "personas": len({r["persona"] for r in rows}),
        "legacy_lines": len(legacy_inventory()), "formerly_text_only_now_bound": len(supplemental_inventory()),
        "nonverbal_routes": nonverbal_inventory(), "excluded_or_pending": exclusions()}, ensure_ascii=False, indent=2))

