"""Build the English ferry stem from the same authored cast as gameplay.

Keep the existing Portuguese performances; fit English only when it would
overlap the next spoken beat. The film's visual timeline remains unchanged.
"""
import hashlib
import json
import shutil
import subprocess
import tempfile
import numpy as np
import soundfile as sf
import static_ffmpeg
from scipy.signal import butter, sosfilt
from english_voice_catalog import ROOT
from generate_maciota_voice import write_json


def main():
    static_ffmpeg.add_paths()
    base = ROOT / 'cutscenes/opening/ferry'
    timing = json.loads((base/'timing.json').read_text(encoding='utf8'))
    originals = json.loads((base/'production/voices.json').read_text(encoding='utf8'))
    main_path = ROOT/'audio/mission_voices/recordings.json'
    maciota_path = ROOT/'audio/mission_voices/maciota_baritone/recordings.json'
    main_bank = json.loads(main_path.read_text(encoding='utf8'))
    maciota_bank = json.loads(maciota_path.read_text(encoding='utf8'))
    rate = 24000
    track = np.zeros(round(timing['duration']*rate), dtype=np.float32)
    report = []
    for index, row in enumerate(timing['lines']):
        key = hashlib.sha256((row['speaker']+'|'+row['text']).encode()).hexdigest()
        bank = maciota_bank if row['speaker']=='caller' else main_bank
        if key not in bank:
            original = next(r for r in originals['lines'] if r['id']==row['id'])
            target = ROOT/'audio/mission_voices/pt_complete'/('ferry_'+key+'.wav')
            # Preserve the approved cinematic actor rather than synthesizing PT again.
            shutil.copyfile(base/'production/takes'/original['file'], target)
            bank[key] = 'res://'+target.relative_to(ROOT).as_posix()
        path = ROOT/'audio/mission_voices/en'/(key+'.wav')
        signal, original_rate = sf.read(path, dtype='float32')
        assert original_rate==rate
        limit = (timing['lines'][index+1]['start'] if index+1<len(timing['lines']) else timing['duration']-.6)-row['start']-.2
        speed = max(1.0,len(signal)/rate/limit)
        if speed>1.0:
            assert speed<1.3, (row['id'],speed)
            with tempfile.TemporaryDirectory(prefix='ferry_dub_') as folder:
                out = Path(folder)/'fitted.wav'
                subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),'-af',f'atempo={speed}',str(out)],check=True)
                signal,_=sf.read(out,dtype='float32')
        if row.get('memory'):
            signal=sosfilt(butter(2,[300,3700],btype='bandpass',fs=rate,output='sos'),signal)
        signal *= .48 / max(.001,float(np.max(np.abs(signal))))
        offset=round(row['start']*rate)
        track[offset:offset+len(signal)] += signal
        row['end_en']=round(row['start']+len(signal)/rate,3)
        assert row['end_en'] < row['start']+limit+.2
        report.append({'id':row['id'],'start':row['start'],'end':row['end_en'],'tempo':speed})
    with tempfile.TemporaryDirectory(prefix='ferry_stem_') as folder:
        master = Path(folder)/'voice.wav'
        sf.write(master,track,rate,subtype='PCM_16')
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(master),'-c:a','libvorbis','-q:a','5',str(base/'voice_en.ogg')],check=True)
    write_json(base/'timing.json',timing)
    write_json(main_path,main_bank)
    write_json(maciota_path,maciota_bank)
    write_json(ROOT/'evidence/ferry-english-voice.json',{'duration':timing['duration'],'lines':report,'peak':float(np.max(np.abs(track)))})
    print('FERRY_ENGLISH_VOICE PASS',len(report),'lines; Portuguese takes preserved')


if __name__=='__main__':
    from pathlib import Path
    main()
