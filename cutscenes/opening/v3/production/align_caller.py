"""Alinha legendas à tomada contínua; não recorta nem acelera a interpretação."""
from pathlib import Path
import json, unicodedata
from faster_whisper import WhisperModel

ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'production'/'sources'/'pt_caller_qwen_v2.wav'
model=WhisperModel('small',device='cpu',compute_type='int8',cpu_threads=6,
    download_root='D:/geteco/tools/opening_voice_models/whisper')
segments,_=model.transcribe(str(source),language='pt',beam_size=5,word_timestamps=True)
words=[w for s in segments for w in s.words]
def plain(word):
    return ''.join(c for c in unicodedata.normalize('NFKD',word.lower()) if c.isalnum()).strip()
split=next(i for i,w in enumerate(words) if plain(w.word)=='prisao')
assert any(plain(w.word)=='rodoviaria' for w in words), 'Rever a pronúncia e a tomada antes de integrar.'
rows=[
    {'id':'release','text':'Dante? Você não me conhece, mas escuta. Seu irmão saiu da prisão.',
     'start':words[0].start,'end':words[split].end},
    {'id':'harbor','text':'Viram ele em Harbor, perto da rodoviária. Desde então, ele não atende o telefone.',
     'start':words[split+1].start,'end':words[-1].end},
]
out={'captions':rows,'recognized':' '.join(w.word.strip() for w in words),
     'words':[{'word':w.word,'start':w.start,'end':w.end} for w in words]}
(ROOT/'production'/'sources'/'caller_alignment_v2.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False),flush=True)
