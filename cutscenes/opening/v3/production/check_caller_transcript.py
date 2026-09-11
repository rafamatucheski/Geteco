from faster_whisper import WhisperModel
from pathlib import Path
import json
model=WhisperModel('small',device='cpu',compute_type='int8',cpu_threads=6,download_root='D:/geteco/tools/opening_voice_models/whisper')
for path in Path('cutscenes/opening/v3/production/sources').glob('pt_*_qwen_v1.wav'):
 segments,info=model.transcribe(str(path),language='pt',beam_size=5,word_timestamps=True)
 print(path.name,flush=True)
 for s in segments: print(json.dumps({'text':s.text,'start':s.start,'end':s.end},ensure_ascii=False),flush=True)
