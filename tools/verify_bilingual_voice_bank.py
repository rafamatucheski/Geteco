"""Verifica as ondas bilíngues reais e amostra a fala recém-adicionada com ASR local."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import wave
import numpy as np
from english_voice_catalog import ROOT, inventory


def main(asr):
    rows = inventory()
    load = lambda p: json.loads((ROOT / p).read_text(encoding='utf8'))
    banks = {'en': load('audio/mission_voices/en/recordings.json'),
             'pt': load('audio/mission_voices/recordings.json')}
    maciota = load('audio/mission_voices/maciota_baritone/recordings.json')
    report = {'lines': len(rows), 'waveforms': [], 'asr': [],
              'limitations': 'All waveforms checked; ASR samples assess speech content, not artistic acting quality.'}
    for row in rows:
        assert row['en'], row['key']
        for language in ('pt', 'en'):
            bank = maciota if language == 'pt' and row['persona'] in ('maciota','caller') else banks[language]
            assert row['key'] in bank, (language, row['text'])
            path = ROOT / bank[row['key']][6:]
            with wave.open(str(path), 'rb') as wav:
                assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
                duration = wav.getnframes() / wav.getframerate()
                signal = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(np.int32)
            assert duration > .1 and np.max(np.abs(signal)) > 500, path
            report['waveforms'].append({'key':row['key'], 'language':language, 'path':bank[row['key']],
                'duration':duration, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    if asr:
        os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', OMP_NUM_THREADS='1')
        from faster_whisper import WhisperModel
        from verify_english_voice_bank import word_list
        cache = Path('D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120')
        model = WhisperModel(str(cache), device='cpu', compute_type='int8', cpu_threads=1, num_workers=1, local_files_only=True)
        # Os dois idiomas, vozes novas femininas/masculinas e personagens centrais da narrativa.
        for persona in ('joana', 'nelson', 'dante', 'dona zefa', 'passenger'):
            candidates = [r for r in rows if r['persona']==persona]
            row = min(candidates, key=lambda r:abs(len(r['text'])-150))
            for language in ('pt', 'en'):
                path = ROOT / banks[language][row['key']][6:]
                expected = row['text'] if language=='pt' else row['en']
                segments, info = model.transcribe(str(path), language=language, beam_size=3, best_of=1, temperature=0,
                    vad_filter=False, condition_on_previous_text=False)
                transcript = ' '.join(s.text.strip() for s in segments)
                similarity = difflib.SequenceMatcher(None,word_list(expected),word_list(transcript)).ratio()
                report['asr'].append({'persona':persona,'language':language,'key':row['key'],
                    'expected':expected,'transcript':transcript,'similarity':round(similarity,3),'review':similarity < .8})
                print('BILINGUAL_ASR',persona,language,round(similarity,3),flush=True)
    destination = ROOT / 'evidence/bilingual-voice-audit.json'
    if not asr and destination.exists():
        previous = json.loads(destination.read_text(encoding='utf8'))
        old_hashes = {(r['key'],r['language']):r['sha256'] for r in previous.get('waveforms',[])}
        new_hashes = {(r['key'],r['language']):r['sha256'] for r in report['waveforms']}
        report['asr'] = [r for r in previous.get('asr',[]) if old_hashes.get((r['key'],r['language'])) == new_hashes.get((r['key'],r['language']))]
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('BILINGUAL_BANK PASS',len(rows),'lines',len(report['waveforms']),'waveforms',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asr',action='store_true')
    main(parser.parse_args().asr)
