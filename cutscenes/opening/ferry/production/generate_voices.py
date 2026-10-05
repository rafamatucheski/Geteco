"""Original PT-BR performances, cached Qwen VoiceDesign. Run with
D:/geteco/tools/opening_voice_design/Scripts/python.exe. No runtime network.
"""
from pathlib import Path
import json, os, time
ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[3]
os.environ.setdefault("HF_HOME", str(WORKSPACE / "tools/opening_voice_models"))
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
BASE = "Native Brazilian Portuguese, natural everyday Brazilian accent, clear consonants, intimate film dialogue, dry clean studio recording. "
VOICES = {
    "dante": BASE + "Man aged 32, warm medium-low voice, slightly textured, conversational and understated. Never an announcer. Same young adult man throughout.",
    "passenger": BASE + "Man aged 58, warm friendly slightly breathy baritone, easygoing local passenger making small talk, smiling gently, unhurried and natural.",
    "caller": BASE + "Man aged 65, discreet low slightly raspy voice, speaking quietly on a private phone call, concerned but clear, restrained urgency, no theatrical villain voice.",
}
LINES = [
    ("first_time", "passenger", 12.0, "É a sua primeira vez por aqui?", "Is this your first time here?", "Conversa espontânea em português brasileiro, pergunta amigável, pronúncia clara e ritmo natural."),
    ("brother", "dante", 16.0, "É. Vim encontrar meu irmão.", "Yeah. I'm here to see my brother.", "Relaxed, a small smile, optimistic, a short pause after É."),
    ("long_time", "passenger", 21.0, "Faz tempo que vocês não se veem?", "Been a while since you saw each other?", "Warm ordinary conversation, gentle curiosity."),
    ("too_long", "dante", 25.0, "Tempo demais.", "Too long.", "Quieter, affection and a little longing under the words, not despair."),
    ("release", "caller", 31.0, "Dante? Escuta. O Vicente saiu da prisão.", "Dante? Listen. Vicente got out of prison.", "Delicate news, quiet and serious, pause before the name Vicente."),
    ("surprise", "dante", 37.0, "Meu irmão? Como assim, saiu?", "My brother? What do you mean, got out?", "Surpresa genuína e dúvida. Português brasileiro coloquial. Duas perguntas claras, sem gritar."),
    ("clue", "caller", 42.0, "Viram ele em Harbor. Mas ele não atende mais o telefone.", "He was seen in Harbor. But he's stopped answering his phone.", "Careful, concerned, one restrained breath between the sentences."),
    ("identity", "dante", 49.0, "Peraí... Quem tá falando?", "Wait... Who is this?", "Urgent curiosity, controlled, starts softly then asks firmly."),
    ("docking", "passenger", 57.0, "Olha lá. Já tão preparando o desembarque.", "Look. They're getting ready for us to get off.", "Back to present, casual and welcoming, drawing attention to the pier."),
    ("thanks", "dante", 62.0, "Valeu pela conversa.", "Thanks for the company.", "Sincere, friendly, composed again with quiet determination."),
    ("luck", "passenger", 65.0, "Boa sorte com seu irmão.", "Good luck with your brother.", "Warm sincere farewell, no ominous undertone."),
]

def main():
    output = ROOT / "production" / "takes"
    output.mkdir(parents=True, exist_ok=True)
    def take_name(identifier):
        return identifier + ("-v2" if identifier in ["first_time", "surprise"] else "") + ".wav"
    missing = [line for line in LINES if not (output / take_name(line[0])).exists()]
    model = None
    if missing:
        print("Loading cached VoiceDesign", flush=True)
        cached = next((WORKSPACE / "tools/opening_voice_models/hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-VoiceDesign/snapshots").iterdir())
        model = Qwen3TTSModel.from_pretrained(str(cached), device_map="cuda:0", dtype=torch.bfloat16, attn_implementation="sdpa", local_files_only=True)
    rows = []
    for identifier, speaker, start, text, english, emotion in LINES:
        path = output / take_name(identifier)
        if not path.exists():
            torch.manual_seed({"dante":8131, "passenger":7024, "caller":5312}[speaker])
            before = time.monotonic()
            waves, rate = model.generate_voice_design(text=text, language="Portuguese", instruct=VOICES[speaker] + " " + emotion,
                max_new_tokens=240, temperature=.75, top_p=.9)
            signal = np.asarray(waves[0], dtype=np.float32)
            active = np.flatnonzero(np.abs(signal) > .004)
            if len(active):
                signal = signal[max(0, int(active[0] - rate * .08)):min(len(signal), int(active[-1] + rate * .16))]
            sf.write(path, signal, rate, subtype="PCM_16")
            print(identifier, "generated in", round(time.monotonic() - before, 1), "seconds", flush=True)
        info = sf.info(path)
        rows.append(dict(id=identifier, speaker=speaker, start=start, text=text, en=english,
                         direction=emotion, voice_direction=VOICES[speaker], file=path.name, seconds=info.duration))
        print(identifier, round(info.duration, 3), text, flush=True)
    (ROOT / "production" / "voices.json").write_text(json.dumps({"model":MODEL,"language":"pt-BR","lines":rows}, ensure_ascii=False, indent=2), encoding="utf-8")

if __name__ == "__main__":
    main()
