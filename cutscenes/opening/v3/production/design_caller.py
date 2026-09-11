"""Voz original dirigida localmente; nenhuma imitação de uma pessoa real.

Runtime isolado: D:/geteco/tools/opening_voice_design
Modelo: https://github.com/QwenLM/Qwen3-TTS (Apache-2.0).
Pesos/cache ficam fora do jogo. Somente WAV/OGG finais entram na produção.
"""
from pathlib import Path
import os, json, time

os.environ.setdefault('HF_HOME', 'D:/geteco/tools/opening_voice_models')
os.environ.setdefault('HF_HUB_DISABLE_SYMLINKS_WARNING', '1')
import torch
import soundfile as sf
from qwen_tts import Qwen3TTSModel

ROOT=Path(__file__).resolve().parents[1]
SOURCES=ROOT/'production'/'sources'
MODEL='Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign'
DIRECTION=(
    'Português brasileiro nativo, com pronúncia brasileira e fala coloquial. '
    'Homem brasileiro de aproximadamente 65 anos, voz de conversa levemente rouca. '
    'Tom médio-grave, sem engrossar ou arrastar a voz. Ele está ligando anonimamente '
    'para dar uma notícia delicada. Fala baixo, mas com clareza e urgência contida, '
    'como numa conversa real, preocupado com o rapaz de quem está falando. '
    'Ritmo cotidiano, entonação irregular e espontânea, pequenas pausas entre as ideias. '
    'Não declama, não faz voz de locutor e não caricatura um velho. Áudio seco e limpo.'
)
TEXT=('Dante? Você não me conhece, mas escuta. Seu irmão saiu da prisão. '
      'Viram ele em Harbor, perto da rodoviária. Desde então, ele não atende o telefone.')

def main():
    print('Loading',MODEL,flush=True)
    started=time.monotonic()
    model=Qwen3TTSModel.from_pretrained(MODEL,device_map='cuda:0',
        dtype=torch.bfloat16,attn_implementation='sdpa')
    print('Model loaded',round(time.monotonic()-started,1),flush=True)
    manifest={'model':MODEL,'direction':DIRECTION,'takes':[]}
    torch.manual_seed(5312)
    wavs,sr=model.generate_voice_design(text=TEXT,language='Portuguese',
        instruct=DIRECTION,max_new_tokens=500,temperature=.85,top_p=.95)
    path=SOURCES/'pt_caller_qwen_v2.wav'
    sf.write(path,wavs[0],sr,subtype='PCM_16')
    take={'id':'caller','text':TEXT,'file':path.name,'seconds':len(wavs[0])/sr,'sample_rate':sr,'seed':5312}
    manifest['takes'].append(take)
    print(json.dumps(take,ensure_ascii=False),flush=True)
    (SOURCES/'caller_direction_v2.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__': main()
