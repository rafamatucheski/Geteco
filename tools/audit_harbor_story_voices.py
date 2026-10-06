"""Finite, single-thread offline transcript audit; no voice generation."""
import ctypes
import difflib
import json
import os
import sys
from pathlib import Path
import time
import unicodedata
import wave

os.environ['OMP_NUM_THREADS'] = '1'
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
if os.name == 'nt':
    kernel = ctypes.windll.kernel32
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetPriorityClass.argtypes = [ctypes.c_void_p,ctypes.c_uint32]
    kernel.SetPriorityClass(kernel.GetCurrentProcess(),0x4000)

from faster_whisper import WhisperModel

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path('D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120')

def words(text):
    plain = ''.join(char for char in unicodedata.normalize('NFD',text.lower()) if unicodedata.category(char) != 'Mn')
    return ''.join(char if char.isalnum() else ' ' for char in plain).split()

def main():
    manifest = json.loads((ROOT/'audio/mission_voices/harbor_story/production.json').read_text(encoding='utf-8-sig'))
    model = WhisperModel(str(CACHE),device='cpu',compute_type='int8',cpu_threads=1,num_workers=1,local_files_only=True)
    output = ROOT/'evidence/harbor-story-voices-audit.json'
    reviewing = '--review-short' in sys.argv
    rows = manifest['lines']
    if reviewing:
        previous = json.loads(output.read_text(encoding='utf-8'))
        flagged = {line['key'] for line in previous['lines'] if line['review']}
        rows = [row for row in rows if row['key'] in flagged]
        output = ROOT/'evidence/harbor-story-voices-review.json'
    report = {'method':'offline Whisper small int8, one CPU thread','complete_manifest':manifest['complete'],
        'limitations':'ASR flags require review; transcript similarity does not certify acting or voice continuity.', 'lines':[]}
    began = time.monotonic()
    if reviewing: report['method'] += '; short-clip review without VAD, beam 5, cast-name vocabulary'
    for index,row in enumerate(rows):
        if time.monotonic()-began > 900: raise TimeoutError('Finite voice audit exceeded 15 minutes')
        path = ROOT/row['path'].removeprefix('res://')
        with wave.open(str(path),'rb') as audio:
            seconds = audio.getnframes()/audio.getframerate()
        segments,_ = model.transcribe(str(path),language='pt',beam_size=5 if reviewing else 1,best_of=1,temperature=0,
            vad_filter=not reviewing,condition_on_previous_text=False,
            initial_prompt='Dante, Maciota, Vicente, Jessica, Harbor, Ferrugem, Takeshi, Helena, Neco.' if reviewing else None)
        transcript = ' '.join(segment.text.strip() for segment in segments)
        similarity = difflib.SequenceMatcher(None,words(row['text']),words(transcript)).ratio()
        report['lines'].append({'key':row['key'],'persona':row['persona'],'expected':row['text'],
            'transcript':transcript,'seconds':seconds,'similarity':round(similarity,3),
            'review':similarity<.65 or seconds<.7 or not transcript})
        report['flagged'] = sum(line['review'] for line in report['lines'])
        output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('VOICE_AUDIT '+str(index+1)+'/'+str(len(rows))+' similarity='+str(round(similarity,3)),flush=True)
    print('VOICE_AUDIT_COMPLETE lines='+str(len(report['lines']))+' flagged='+str(report['flagged']),flush=True)

if __name__ == '__main__': main()
