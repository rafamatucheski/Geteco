"""Verifica todas as tomadas em inglês do jogo; opcionalmente audita uma amostra finita de elenco/falas longas.

Não inicia o Godot nem modelo na GPU. O ASR confirma idioma/conteúdo, não atuação.
"""
from __future__ import annotations
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import time
import unicodedata
import wave

os.environ['OMP_NUM_THREADS'] = '1'
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
from english_voice_catalog import OUTPUT, ROOT, inventory
from generate_english_voices import PROFILES, signature


def word_list(text):
    plain = ''.join(c for c in unicodedata.normalize('NFD', text.lower()) if unicodedata.category(c) != 'Mn')
    return ''.join(c if c.isalnum() else ' ' for c in plain).split()


def verify(asr, review_key=''):
    import numpy as np
    review_keys = set(review_key.split(',')) if review_key else set()
    catalog = inventory()
    production = json.loads((OUTPUT / 'production.json').read_text(encoding='utf-8'))
    manifest = json.loads((OUTPUT / 'recordings.json').read_text(encoding='utf-8'))
    expected = {r['key']: r for r in catalog}
    actual = {r['key']: r for r in production['lines']}
    assert production['complete'] and set(expected) == set(actual)
    assert production['profiles'] == PROFILES
    assert PROFILES['caller'] == PROFILES['maciota'] and PROFILES['dante'] != PROFILES['maciota']
    destination = ROOT / 'evidence/english-voice-audit.json'
    previous = json.loads(destination.read_text(encoding='utf-8')) if review_key and destination.exists() else {}
    if review_keys: assert review_keys <= set(actual) and previous.get('asr_checks'), 'Targeted review needs the original completed audit'
    report = {'total_lines': len(catalog), 'personas': len({r['persona'] for r in catalog}),
              'actors': len({PROFILES[r['persona']]['voice'] for r in catalog}),
              'waveform_checks': [], 'asr_checks': [], 'limitations': 'ASR samples check content, not artistic delivery; identity is pinned in the cast profiles.'}
    for row in catalog:
        produced = actual[row['key']]
        assert produced['signature'] == signature(row), 'Stale voice/text/profile: ' + row['key']
        assert produced['en'] == row['en'] and produced['text'] == row['text']
        assert produced['voice_profile'] == PROFILES[row['persona']]
        for text in [row['text'], row['en']] + row['aliases']:
            alias = hashlib.sha256((row['persona'] + '|' + text).encode()).hexdigest()
            assert alias in manifest and (ROOT / manifest[alias][6:]).is_file(), 'Missing alias: ' + text
            assert manifest[alias] == produced['path'], 'Alias switched recording: ' + text
        path = ROOT / produced['path'][6:]
        with wave.open(str(path), 'rb') as source:
            assert source.getnchannels() == 1 and source.getframerate() == 24000 and source.getsampwidth() == 2
            seconds = source.getnframes() / source.getframerate()
            samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2')
        peak = int(np.max(np.abs(samples.astype(np.int32))))
        assert 980 < peak < 28200 and seconds > .25 and abs(seconds - produced['seconds']) < .001
        report['waveform_checks'].append({'key': row['key'], 'seconds': seconds, 'peak': peak,
                                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    if review_key:
        report['asr_checks'] = [r for r in previous['asr_checks'] if r['key'] not in review_keys]
        report['review_history'] = previous.get('review_history', []) + [r for r in previous['asr_checks'] if r['key'] in review_keys]
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'EN_BANK PASS lines={len(catalog)} personas={report["personas"]} actors={report["actors"]} aliases={len(manifest)}', flush=True)
    if not asr: return
    from faster_whisper import WhisperModel
    cache = Path('D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120')
    model = WhisperModel(str(cache), device='cpu', compute_type='int8', cpu_threads=1, num_workers=1, local_files_only=True)
    # Uma tomada de tamanho médio para cada ator nomeado, mais a tomada mais longa de
    # cada personagem principal e as duas falas de quem liga na abertura. Sem repetições ilimitadas.
    chosen = {}
    for voice in sorted({PROFILES[r['persona']]['voice'] for r in catalog}):
        candidates = [r for r in actual.values() if r['voice_profile']['voice'] == voice]
        row = min(candidates, key=lambda r: abs(r['seconds'] - 6.0))
        chosen[row['key']] = row
    for persona in ['dante', 'maciota', 'jessica', 'vicente', 'ferrugem', 'neco', 'takeshi', 'helena', 'digo']:
        row = max((r for r in actual.values() if r['persona'] == persona), key=lambda r: r['seconds'])
        chosen[row['key']] = row
    for row in actual.values():
        if row['persona'] == 'caller': chosen[row['key']] = row
    if review_keys: chosen = {key: actual[key] for key in sorted(review_keys)}
    started = time.monotonic()
    for index, row in enumerate(chosen.values()):
        assert time.monotonic() - started < 900, 'ASR finite audit exceeded 15 minutes'
        segments, _ = model.transcribe(str(ROOT / row['path'][6:]), language='en', beam_size=3, best_of=1,
            temperature=0, vad_filter=False, condition_on_previous_text=False,
            initial_prompt='Dante, Maciota, Vicente, Jessica, Harbor, Ferrugem, Takeshi, Helena, Neco.')
        transcript = ' '.join(segment.text.strip() for segment in segments)
        similarity = difflib.SequenceMatcher(None, word_list(row['en']), word_list(transcript)).ratio()
        report['asr_checks'].append({'key': row['key'], 'persona': row['persona'], 'expected': row['en'],
                                    'transcript': transcript, 'similarity': round(similarity, 3), 'review': similarity < .8 or not transcript})
        report['flagged'] = sum(r['review'] for r in report['asr_checks'])
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'EN_ASR {index + 1}/{len(chosen)} {row["persona"]} similarity={similarity:.3f}', flush=True)
    print(f'EN_ASR_COMPLETE sampled={len(chosen)} flagged={report["flagged"]}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asr', action='store_true')
    parser.add_argument('--review-key', default='', help='Recheck comma-separated changed recording keys, preserving the original audit history')
    args = parser.parse_args()
    verify(args.asr or bool(args.review_key), args.review_key)
