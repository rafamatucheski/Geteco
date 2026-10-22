"""Monta o plano de um lote ElevenLabs: uma linha por gravação (fala × idioma) que ainda falta.

Elenco ElevenLabs decidido em 21/10 (resto do jogo fica no banco local Qwen). A identidade de
cada fala vem do perfil em voice-cast.json (variantes e apelidos, como o DirectedVoiceBank faz):
só a Helena bancária (helena_bank) é ElevenLabs; o "caller" é o Maciota.
Uso: python tools/plan_elevenlabs_batch.py <saida.json>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAST = {  # character_id -> {idioma: (voice_id, nome)}
    "dante": {"pt_BR": ("ycxdm1PRMs962FxyyuJ0", "Otto - Intimidating and Aggressive"),
              "en": ("ycxdm1PRMs962FxyyuJ0", "Otto - Intimidating and Aggressive")},
    # Lucas não serve em inglês (teste de 21/10); o usuário escolheu o Mason para o Maciota em inglês.
    "maciota": {"pt_BR": ("GIuLCSVfgJaUuh7hYOY8", "Lucas - Deep & Profound Narrator"),
                "en": ("dxdOayhnd0jLtELGeNtF", "Mason - Southern Georgia, North Florida Southern Accent")},
    "helena_bank": {"pt_BR": ("YD2yOZItFdFEh7WxPLnp", "Juliana Gheno"), "en": ("YD2yOZItFdFEh7WxPLnp", "Juliana Gheno")},
    "takeshi": {"pt_BR": ("qjx83Y0UcERgVPICvVpl", "Kei"), "en": ("qjx83Y0UcERgVPICvVpl", "Kei")},
    "vicente": {"pt_BR": ("sNOgqySaECh2Vh5sDQNY", "Dantas | Deep, Warm & Slightly Raspy"),
                "en": ("sNOgqySaECh2Vh5sDQNY", "Dantas | Deep, Warm & Slightly Raspy")},
    # 22/10: o usuário estendeu a ElevenLabs às missões principais de Harbor (Ferrugem, Neco,
    # moradora e Jessica); vozes escolhidas pelo perfil de voice-cast.json, mesma voz nos dois idiomas.
    "ferrugem": {"pt_BR": ("E9a8LlXPNWtyvvSoZzrb", "Talis - Natural, Descontraído, Real"),
                 "en": ("E9a8LlXPNWtyvvSoZzrb", "Talis - Natural, Descontraído, Real")},
    "neco": {"pt_BR": ("75FhDGLofkNSQ8G4Htts", "Francis - Brazil | Minas Gerais"),
             "en": ("75FhDGLofkNSQ8G4Htts", "Francis - Brazil | Minas Gerais")},
    "moradora": {"pt_BR": ("k5aKjuBz9NhUMZc7SDpl", "Marilita - Natural & Conversacional"),
                 "en": ("k5aKjuBz9NhUMZc7SDpl", "Marilita - Natural & Conversacional")},
    "jessica": {"pt_BR": ("5p4THmLc2S6kXKO1pOM5", "Nayara Técia - PVC"),
                "en": ("5p4THmLc2S6kXKO1pOM5", "Nayara Técia - PVC")},
}
# Lucas soa lento: o prefixo pede ritmo (validado no teste de 20/10).
PREFIX = {("maciota", "pt_BR"): "ágil, "}
# Indicações curtas em inglês (contam como caracteres: curtas de propósito).
EN_TAG = {
    "atender sem suspeita": "casual, unsuspecting", "reconhecer e desconfiar": "recognizing, wary",
    "impedir que desligue": "urgent, reaching out", "cobrar identificação": "guarded, demanding",
    "testar o desconhecido": "testing, suspicious", "buscar resposta direta": "direct, pressing",
    "investigar vínculo": "probing", "admitir distância": "flat, honest", "retomar urgência": "urgent",
    "aceitar ouvir proposta": "reluctant, open", "questionar desvio": "skeptical",
    "reportar impedimento": "frustrated, reporting", "testar nova pista": "hopeful, careful",
    "agradecer ajuda": "grateful", "ligar pistas": "connecting the dots", "confirmar ligação": "focused, realizing",
    "reconhecer nome decisivo": "reading, stunned", "mostrar curiosidade": "curious", "notar carro": "impressed",
    "marcar limite": "firm", "cobrar consciência": "serious, warning", "justificar decisão difícil": "conflicted, resolute",
    "buscar chão": "shaken", "admirar competência": "admiring", "oferecer reencontro": "warm, tentative",
    "firmar promessa pequena": "quiet promise", "mostrar confiabilidade": "steady, wry", "confirmar destino": "determined",
    "deixar urgência aparecer": "emotional, urgent", "responder com reserva": "reserved", "admitir falta": "regretful",
    "assimilar choque": "shocked", "retomar controle": "regaining control, wary", "encerrar com gratidão": "polite, grateful",
    "conferir equipamento": "checking, focused", "identificar última etapa": "focused", "confirmar reparo": "relieved, pleased",
    "perceber adulteração": "suspicious, alert", "distinguir investigações": "thinking aloud",
    "confrontar omissão": "hurt, confronting", "acompanhar com humor": "amused", "reconhecer paixão alheia": "warm, admiring",
    "acolher novo interesse": "sincere", "entrar na brincadeira": "playful", "reconhecer marca": "alarmed, recognizing",
    "seguir investigação": "determined", "deduzir próximo caminho": "deducing", "reconhecer hábito íntimo": "moved, quiet",
    "aproximar da pista": "curious, careful", "tocar memória afetiva": "tender, emotional",
    "sentir encontro perdido": "heartbroken, quiet", "recuperar propósito": "resolute", "explicar sem absolvição": "heavy, honest",
    "apresentar prova": "firm, presenting evidence", "admitir responsabilidade e mostrar evidência": "guilty, insistent",
    "ordenar sequência temporal": "methodical", "definir conferência": "focused", "reconhecer armação": "angry realization",
    "descobrir terreno comum": "curious, friendly", "confirmar carro": "interested", "reconhecer progresso pessoal": "quietly proud",
    "descobrir vestígio na estação": "intrigued", "encontrar salário abandonado": "somber", "reconstruir descoberta": "piecing it together",
    "notar objeto recuperável": "noticing", "entregar com precisão": "composed, precise", "alertar com discrição": "discreet warning",
    "honrar acordo": "calm, honorable", "testar competência": "firm, challenging", "aceitar derrota com custo": "dignified defeat",
    "confirmar compromisso": "honorable", "cobrar preparo sem humilhar": "stern, fair", "entregar bem estimado": "solemn, proud",
    "transferir herança": "solemn", "confrontar ausência": "cold, hurt", "recusar desculpa e fixar regra": "hard, firm",
    "permitir aproximação limitada": "guarded", "nomear ferida central": "bitter, restrained",
    "cobrar perda irreparável": "pained, cold", "oferecer caminho sem reconciliação": "tired, measured",
    # Maciota (inglês, Mason).
    "abrir conversa difícil": "heavy, opening up", "acolher com cautela": "warm, cautious", "acolher e orientar": "playful, guiding",
    "acolher à distância": "warm, over the radio", "admitir acesso e baixar exposição": "low, discreet", "admitir risco e autonomia": "serious, letting go",
    "alívio e retomada": "relieved, back to business", "apertar urgência": "urgent", "assegurar apoio": "reassuring", "combinar tarefas": "practical, brisk",
    "confirmar vínculo": "proud, warm", "cuidar através de gesto": "proud, caring", "dar condições com humor seco": "dry humor",
    "definir ação de investigação": "focused, direct", "distinguir responsabilidades": "matter-of-fact", "eliminar mal-entendido": "patient, firm",
    "encaminhar conversa": "brisk", "encaminhar próximo contato": "brisk, practical", "entregar notícia urgente": "urgent, low",
    "enviar para proteção": "urgent, protective", "explicar acordo": "sly, confident", "explicar aposta decisiva": "serious, tense",
    "explicar vínculo e lealdade": "earnest", "fisgar atenção": "low, close", "indicar destino seguro": "calm, guiding",
    "medir notícia ruim": "careful, heavy", "mostrar gratidão contida": "moved, restrained", "oferecer pista concreta": "practical",
    "orientar aproximação": "practical, sly", "orientar entrega": "brisk, practical", "pedir tarefa breve": "casual", "preparar partida e cuidar": "caring, firm",
    "preparar viagem": "practical, caring", "pressionar sem explicar": "clipped, urgent", "priorizar pessoa antes da pista": "firm, protective",
    "propor acesso por corrida": "sly, confident", "propor reciprocidade": "frank, warm", "proteger e adiar": "protective, cautious",
    "receber com intimidade brincalhona": "playful, teasing", "reconhecer confiança": "warm, proud", "reconhecer entrega": "satisfied",
    "relatar sem condenar": "measured", "resolver e repreender": "urgent, scolding", "revelar confiança conquistada": "quiet, serious",
    "revelar dívida pessoal": "grateful, heavy", "se apresentar e conduzir": "friendly, brisk", "situar investigação": "explaining, low",
    "confiar o carro": "warm, handing over", "brincar e instruir": "teasing, practical", "estranhar com humor": "amused, incredulous",
    # Ferrugem, Neco e moradora.
    "dar serviço e soltar pista": "dry, brisk", "abrir acesso condicionado": "grudging, dry", "ceder respeito e pista": "grudging respect",
    "conferir prova e pressionar contato": "firm, deliberate", "pedir proteção urgente": "frightened, urgent",
    "confiar após resgate": "stunned relief",
    # Jessica.
    "reconhecer competência": "cool, appraising", "provocar rival": "teasing", "mudar para proposta": "casual, getting to it",
    "deixar porta aberta": "light, inviting", "dividir operação": "focused, low", "respeitar escolha": "even, honest",
    "estabelecer fuga": "steady, confident", "assumir controle": "calm, commanding", "baixar tensão com humor": "deadpan",
    "provocar após alívio": "teasing, relieved", "reafirmar ambição": "confident", "pedir vínculo pessoal": "soft, sincere",
    "disfarçar expectativa": "casual, hiding relief", "reconhecer cuidado": "warm, brief", "lembrar assunto adiado": "gentle reminder",
    "reencontrar rival querido": "playful, glad", "lançar desafio pessoal": "competitive, teasing",
    "retomar história compartilhada": "warm, nostalgic", "encorajar confronto necessário": "firm, encouraging",
    "adiar operação inviável": "matter-of-fact", "reportar rota bloqueada": "alert",
}
# A intenção das falas de dor é uma frase longa: indicação curta para não pagar por ela.
PAIN_TAG = {"pt_BR": "dor curta", "en": "short pain"}
PAIN_KEY = "80a833fa7c4bf1c457d0ce1d3fbaf3e0fe21b6b6f926b242223d70ce494307ac"
PAIN_EN_TONES = ["sharp pain, short", "muffled grunt, teeth clenched", "startled pain", "angry pain"]
GREETING_KEY = "873a8bd50b524f3b14f0c9c9ecc17d5bb9604f18e4c436e2d15fad6f32108b6b"
GREETING_EN_TONES = ["playful, laughing", "tired, dry irony", "warm, cheerful"]


def character(cast: dict, row: dict) -> str:
    person = cast.get(row["speaker"], {})
    for variant in person.get("variants", []):
        if row["key"] in variant.get("line_keys", []):
            return variant.get("default_character", variant.get("alias_of", variant.get("id")))
    return person.get("default_character", person.get("alias_of", person.get("id", "")))


def main() -> None:
    lines = json.loads((ROOT / "data/dialogue/voice-line-direction.json").read_text(encoding="utf-8"))["lines"]
    cast = json.loads((ROOT / "data/dialogue/voice-cast.json").read_text(encoding="utf-8"))["personas"]
    installed = json.loads((ROOT / "audio/mission_voices/directed/elevenlabs.json").read_text(encoding="utf-8"))["lines"]
    plan = []
    for row in lines:
        who = character(cast, row)
        for lang, field in (("pt_BR", "spoken_pt"), ("en", "spoken_en")):
            voice = CAST.get(who, {}).get(lang)
            if voice is None or row["key"] in installed.get(lang, {}):
                continue
            tones = [None]
            if row["key"] == PAIN_KEY and lang == "en": tones = PAIN_EN_TONES
            if row["key"] == GREETING_KEY and lang == "en": tones = GREETING_EN_TONES
            for tone in tones:
                if row["source_section"].startswith("combat_pain"):
                    tag = tone or PAIN_TAG[lang]
                else:
                    tag = tone or (row["intent"] if lang == "pt_BR" else EN_TAG[row["intent"]])
                plan.append({"label": f"{row['key'][:12]}_{lang}" + (f"_{tones.index(tone)}" if tone else ""),
                             "key": row["key"], "persona": row["speaker"], "character_id": who, "language": lang,
                             "voice_id": voice[0], "voice_name": voice[1],
                             "prompt": f"[{PREFIX.get((who, lang), '')}{tag}] {row[field]}"})
    Path(sys.argv[1]).write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    credits = sum(len(p["prompt"]) for p in plan)
    print(f"ELEVENLABS_PLAN takes={len(plan)} chars={credits}")


if __name__ == "__main__":
    main()
