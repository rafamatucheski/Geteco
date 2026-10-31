"""Auditoria finita, só na CPU, de ondas e transcrições do banco fixo do Maciota."""
import difflib
import hashlib
import json
import os
import time
import unicodedata

os.environ['OMP_NUM_THREADS'] = '1'
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'

from pathlib import Path
import numpy as np
import soundfile as sf
from faster_whisper import WhisperModel
from generate_maciota_voice import OUTPUT, PROFILE, ROOT, lines


def words(text):
    text = ''.join(c for c in unicodedata.normalize('NFD', text.lower()) if unicodedata.category(c) != 'Mn')
    return ''.join(c if c.isalnum() else ' ' for c in text).split()


def main():
    production = json.loads((OUTPUT / 'production.json').read_text(encoding='utf-8'))
    manifest = json.loads((OUTPUT / 'recordings.json').read_text(encoding='utf-8'))
    authored = {row['key']: row for row in lines()}
    assert production['complete'] and production['profile'] == PROFILE
    assert set(authored) == set(manifest), 'Every current/legacy Maciota line needs the fixed voice'
    model_path = Path('D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120')
    model = WhisperModel(str(model_path), device='cpu', compute_type='int8', cpu_threads=1, num_workers=1, local_files_only=True)
    report = {'method': 'fixed named actor/configuration; PCM inspection; offline Whisper small int8, 1 CPU thread',
              'limitations': 'ASR checks text, not acting. Subjective timbre still benefits from listening.', 'lines': []}
    output = ROOT / 'evidence/maciota-voice/audit.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    for index, row in enumerate(production['lines']):
        assert time.monotonic() - started < 900, 'Finite audit exceeded 15 minutes'
        assert row['voice_profile'] == PROFILE['id']
        assert row['text'] == authored[row['key']]['text'] and row['path'] == manifest[row['key']]
        path = ROOT / row['path'].removeprefix('res://')
        signal, rate = sf.read(path, dtype='float32')
        assert signal.ndim == 1 and rate == 24000 and sf.info(path).subtype == 'PCM_16'
        assert np.isfinite(signal).all() and .03 < np.max(np.abs(signal)) < .86
        assert abs(len(signal) / rate - row['seconds']) < .001
        segments, _ = model.transcribe(str(path), language='pt', beam_size=3, best_of=1,
            temperature=0, vad_filter=False, condition_on_previous_text=False,
            initial_prompt='Dante, Maciota, Vicente, Jessica, Harbor, Ferrugem, Takeshi, Helena, Neco.')
        transcript = ' '.join(segment.text.strip() for segment in segments)
        similarity = difflib.SequenceMatcher(None, words(row['text']), words(transcript)).ratio()
        report['lines'].append({'key': row['key'], 'expected': row['text'], 'transcript': transcript,
            'similarity': round(similarity, 3), 'review': similarity < .8 or not transcript,
            'seconds': row['seconds'], 'peak': round(float(np.max(np.abs(signal))), 4),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        report['flagged'] = sum(line['review'] for line in report['lines'])
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'MACIOTA_AUDIT {index + 1}/{len(production["lines"])} similarity={similarity:.3f}', flush=True)
    print(f'MACIOTA_AUDIT_COMPLETE {len(report["lines"])} flagged={report["flagged"]}', flush=True)


if __name__ == '__main__':
    main()
