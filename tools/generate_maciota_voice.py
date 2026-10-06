"""One fixed Brazilian voice for Maciota, including his opening phone call.

Generation uses the existing edge-tts package; runtime only reads mono PCM WAVs.
Existing VoiceDesign takes remain intact. No other character's manifest is changed.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

from harbor_voice_lines import ROOT, authored

OUTPUT = ROOT / 'audio/mission_voices/maciota_baritone'
PROFILE = {'id': 'maciota_baritone_v1', 'voice': 'pt-BR-AntonioNeural',
           'rate': '-6%', 'pitch': '-22Hz', 'volume': '+0%',
           'sample_rate': 24000, 'channels': 1, 'format': 'PCM_16'}


def lines():
    rows = [row for row in authored() if row['persona'] in ('maciota', 'caller')]
    # Restored saves can still complete the old bench task in the workshop.
    source = (ROOT / 'data/GarageSequence.gd').read_text(encoding='utf-8-sig')
    for name in ('GREETING', 'REQUEST', 'THANKS'):
        text = json.loads(re.search(r'const ' + name + r' := ("[^\n]*")', source)[1])
        key = hashlib.sha256(('maciota|' + text).encode()).hexdigest()
        rows.append(dict(key=key, persona='maciota', text=text, en='', section='garage_legacy'))
    return list({row['key']: row for row in rows}.values())


def write_json(path, value):
    pending = path.with_suffix(path.suffix + '.pending')
    pending.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    pending.replace(path)


async def produce(endpoint):
    import edge_tts
    import numpy as np
    import soundfile as sf
    import static_ffmpeg

    if endpoint == 'msedge':
        # Same service endpoint supported by edge-tts 7.2.3, selected explicitly
        # when the current speech.platform.bing.com host is unavailable.
        import edge_tts.communicate as communication
        from edge_tts.constants import TRUSTED_CLIENT_TOKEN
        communication.WSS_URL = ('wss://api.msedgeservices.com/tts/cognitiveservices/'
                                 'websocket/v1?Ocp-Apim-Subscription-Key=' + TRUSTED_CLIENT_TOKEN)
    static_ffmpeg.add_paths()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    production_path = OUTPUT / 'production.json'
    previous = json.loads(production_path.read_text(encoding='utf-8')) if production_path.exists() else {}
    if previous and previous.get('profile') != PROFILE:
        raise RuntimeError('Profile changed: create a new version/bank instead of mixing takes.')
    completed = {row['key']: row for row in previous.get('lines', [])}
    rows = lines()
    for index, row in enumerate(rows):
        wav_path = OUTPUT / (row['key'] + '.wav')
        if row['key'] not in completed or not wav_path.exists():
            with tempfile.TemporaryDirectory(prefix='geteco_maciota_') as folder:
                mp3_path = Path(folder) / 'take.mp3'
                decoded = Path(folder) / 'decoded.wav'
                await edge_tts.Communicate(row['text'], PROFILE['voice'], rate=PROFILE['rate'],
                                          pitch=PROFILE['pitch'], volume=PROFILE['volume']).save(str(mp3_path))
                subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-threads', '1',
                                '-i', str(mp3_path), '-ac', '1', '-ar', str(PROFILE['sample_rate']),
                                '-sample_fmt', 's16', str(decoded)], check=True)
                signal, rate = sf.read(decoded, dtype='float32')
                active = np.flatnonzero(np.abs(signal) > .003)
                if len(active) == 0:
                    raise RuntimeError('Silent take: ' + row['key'])
                signal = signal[max(0, active[0] - int(rate * .08)):min(len(signal), active[-1] + int(rate * .16))]
                # Fixed dialogue loudness; limit peak without runtime pitch or effects.
                speech = signal[np.abs(signal) > .003]
                rms = float(np.sqrt(np.mean(speech ** 2)))
                signal *= min(.14 / max(rms, .0001), .85 / float(np.max(np.abs(signal))))
                sf.write(wav_path, signal, rate, subtype='PCM_16')
            row.update(path='res://audio/mission_voices/maciota_baritone/' + wav_path.name,
                       seconds=sf.info(wav_path).duration, voice_profile=PROFILE['id'], status='generated')
            completed[row['key']] = row
        write_json(production_path, {'profile': PROFILE, 'complete': False, 'lines': list(completed.values())})
        print(f'MACIOTA_VOICE {index + 1}/{len(rows)}', flush=True)
    output_rows = [completed[row['key']] for row in rows]
    write_json(production_path, {'profile': PROFILE, 'complete': True, 'lines': output_rows})
    # Publish only a complete bank, so interruption never introduces a mixed voice.
    write_json(OUTPUT / 'recordings.json', {row['key']: row['path'] for row in output_rows})
    print(f'MACIOTA_VOICE_COMPLETE {len(output_rows)}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', choices=('default', 'msedge'), default='default')
    args = parser.parse_args()
    asyncio.run(produce(args.endpoint))
