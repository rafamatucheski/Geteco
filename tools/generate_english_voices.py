"""Produz o elenco completo em inglês como assets fixos e autorados do jogo, offline.

Só a geração usa o serviço neural Edge existente. O jogo nunca precisa de
conexão de rede nem de modelo de fala. Todo personagem mantém um ator/perfil nomeado.
"""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from english_voice_catalog import OUTPUT, ROOT, inventory
from generate_maciota_voice import write_json


def profile(voice, rate='+0%', pitch='+0Hz'):
    return {'voice': voice, 'rate': rate, 'pitch': pitch, 'volume': '+0%'}


# Elenco principal: atores de conversa com identidade estável. Christopher dá
# o registro naturalmente grave do Maciota; nenhuma reamostragem extrema ou efeito é aplicado.
PROFILES = {
    'dante': profile('en-US-AndrewMultilingualNeural', '+1%', '+2Hz'),
    'maciota': profile('en-US-ChristopherNeural', '-3%', '-8Hz'),
    'jessica': profile('en-US-AvaMultilingualNeural', '+2%', '+1Hz'),
    'vicente': profile('en-US-BrianMultilingualNeural', '-1%', '-4Hz'),
    'ferrugem': profile('en-US-GuyNeural', '+0%', '-4Hz'),
    'neco': profile('en-US-SteffanNeural', '-3%', '-5Hz'),
    'takeshi': profile('en-US-EricNeural', '-2%', '-4Hz'),
    'helena': profile('en-US-MichelleNeural', '+0%', '+0Hz'),
    'moradora': profile('en-US-JennyNeural', '-1%', '-3Hz'),
    'digo': profile('en-GB-RyanNeural', '+3%', '+2Hz'),
    'lívia': profile('en-US-EmmaMultilingualNeural', '+3%', '+1Hz'),
    'irene': profile('en-GB-SoniaNeural', '-3%', '-4Hz'),
    'raul': profile('en-US-RogerNeural', '-3%', '-5Hz'),
    'nadir': profile('en-CA-LiamNeural', '+1%', '-2Hz'),
    'bia': profile('en-IE-EmilyNeural', '+2%', '+1Hz'),
    'mecânico': profile('en-US-EricNeural', '+1%', '+0Hz'),
    'elias': profile('en-US-SteffanNeural', '-5%', '-7Hz'),
    'anselmo': profile('en-US-RogerNeural', '-5%', '-9Hz'),
    'tonico': profile('en-IE-ConnorNeural', '+1%', '-3Hz'),
    'dr. miguel': profile('en-US-BrianNeural', '-1%', '+0Hz'),
    'enfermeira clara': profile('en-US-JennyNeural', '+0%', '+2Hz'),
    'sargento morales': profile('en-US-GuyNeural', '-2%', '-7Hz'),
    'detetive ribeiro': profile('en-US-EricNeural', '-1%', '-7Hz'),
    'policial ferreira': profile('en-US-RogerNeural', '+0%', '+0Hz'),
    'dente de ouro': profile('en-US-GuyNeural', '+3%', '-2Hz'),
    'dona cida': profile('en-US-MichelleNeural', '-4%', '-6Hz'),
    'capitão rocha': profile('en-US-SteffanNeural', '-1%', '-3Hz'),
    'guarda': profile('en-CA-LiamNeural', '+0%', '-4Hz'),
    'funcionário': profile('en-US-BrianNeural', '+1%', '+2Hz'),
    'operador': profile('en-US-EricNeural', '+2%', '-2Hz'),
    'polícia': profile('en-US-GuyNeural', '+3%', '+0Hz'),
}
EXTRAS = {
    'ana': ('en-US-AvaNeural', '+2%', '+2Hz'),
    'bento': ('en-CA-LiamNeural', '-2%', '-4Hz'),
    'bruno': ('en-GB-ThomasNeural', '+2%', '+0Hz'),
    'caio': ('en-US-AndrewNeural', '+2%', '+3Hz'),
    'cecília': ('en-GB-SoniaNeural', '+1%', '+2Hz'),
    'dora': ('en-US-MichelleNeural', '+2%', '+1Hz'),
    'felipe': ('en-IE-ConnorNeural', '+2%', '+1Hz'),
    'inês': ('en-US-JennyNeural', '-2%', '-2Hz'),
    'lia': ('en-US-EmmaNeural', '+2%', '+0Hz'),
    'lucas': ('en-US-AndrewNeural', '+3%', '+5Hz'),
    'luísa': ('en-US-AvaNeural', '-1%', '-3Hz'),
    'matias': ('en-US-BrianNeural', '+2%', '+2Hz'),
    'mila': ('en-US-EmmaNeural', '+1%', '+3Hz'),
    'nora': ('en-US-MichelleNeural', '-1%', '-2Hz'),
    'noé': ('en-US-RogerNeural', '-2%', '-4Hz'),
    'otto': ('en-US-SteffanNeural', '-2%', '+1Hz'),
    'pedro': ('en-CA-LiamNeural', '+2%', '+1Hz'),
    'rui': ('en-GB-ThomasNeural', '-1%', '-3Hz'),
    'rute': ('en-US-JennyNeural', '+2%', '+1Hz'),
    'sérgio': ('en-US-EricNeural', '+1%', '+4Hz'),
    'tomás': ('en-US-BrianNeural', '-1%', '-3Hz'),
    'íris': ('en-US-AvaMultilingualNeural', '+1%', '+3Hz'),
}
PROFILES.update({name: profile(*settings) for name, settings in EXTRAS.items()})
PROFILES['caller'] = PROFILES['maciota'].copy()
for name, actor in {
    'beto':'en-US-GuyNeural', 'beto cascavel':'en-US-SteffanNeural',
    'cida':'en-US-JennyNeural', 'dona marlene':'en-US-MichelleNeural',
    'dona nena':'en-GB-SoniaNeural', 'dona zefa':'en-US-JennyNeural',
    'ermitão jacó':'en-US-RogerNeural', 'hóspede sete':'en-US-EricNeural',
    'o maluco':'en-IE-ConnorNeural', 'padre nicanor':'en-US-BrianNeural',
    'rauhz':'en-US-GuyNeural', 'seu abel':'en-US-RogerNeural',
    'seu tião':'en-US-SteffanNeural', 'tita':'en-US-AvaNeural',
    'tonho':'en-CA-LiamNeural', 'velho ozias':'en-US-BrianNeural',
    'zeca':'en-GB-ThomasNeural',
    'joana':'en-US-EmmaNeural', 'operário':'en-US-GuyNeural', 'nelson':'en-US-BrianNeural',
    'passenger':'en-US-RogerNeural',
}.items():
    PROFILES[name] = profile(actor)


def signature(row):
    return hashlib.sha256(json.dumps([row['text'], row['en'], PROFILES[row['persona']]], ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def publish(rows, completed, complete):
    output_rows = [completed[row['key']] for row in rows if row['key'] in completed]
    write_json(OUTPUT / 'production.json', {'version': 1, 'language': 'en', 'profiles': PROFILES,
        'sample_rate': 24000, 'format': 'PCM_16', 'complete': complete, 'lines': output_rows})
    if not complete: return
    manifest = {}
    meanings = {}
    for row in output_rows:
        for text in [row['text'], row['en']] + row.get('aliases', []):
            key = hashlib.sha256((row['persona'] + '|' + text).encode()).hexdigest()
            if key in meanings and meanings[key] != row['en']:
                raise ValueError('Conflicting translation/alias: ' + row['persona'] + ': ' + text)
            meanings[key] = row['en']
            manifest.setdefault(key, row['path'])
    # Um banco completo aparece de forma atômica. Nada de mistura parcial PT/EN.
    write_json(OUTPUT / 'recordings.json', manifest)


async def produce(concurrency, endpoint):
    import edge_tts
    import numpy as np
    import soundfile as sf
    import static_ffmpeg
    if endpoint == 'msedge':
        import edge_tts.communicate as communication
        from edge_tts.constants import TRUSTED_CLIENT_TOKEN
        communication.WSS_URL = ('wss://api.msedgeservices.com/tts/cognitiveservices/'
                                 'websocket/v1?Ocp-Apim-Subscription-Key=' + TRUSTED_CLIENT_TOKEN)
    static_ffmpeg.add_paths()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = inventory()
    assert rows and all(row['en'] for row in rows), 'Every current line needs an authored English translation'
    assert set(row['persona'] for row in rows) <= set(PROFILES), 'Every identity needs an explicit voice'
    previous = json.loads((OUTPUT / 'production.json').read_text(encoding='utf-8')) if (OUTPUT / 'production.json').exists() else {}
    completed = {r['key']: r for r in previous.get('lines', []) if r.get('signature') == signature(r) and (ROOT / r['path'][6:]).exists()}
    semaphore = asyncio.Semaphore(concurrency)

    async def generate(row):
        async with semaphore:
            settings = PROFILES[row['persona']]
            wav_path = OUTPUT / (row['key'] + '.wav')
            with tempfile.TemporaryDirectory(prefix='geteco_english_') as folder:
                mp3_path = Path(folder) / 'take.mp3'
                decoded = Path(folder) / 'decoded.wav'
                await edge_tts.Communicate(row['en'], **settings).save(str(mp3_path))
                # Uma thread por decodificação curta; nunca inicia modelo de síntese na GPU.
                subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-threads', '1',
                    '-i', str(mp3_path), '-ac', '1', '-ar', '24000', '-sample_fmt', 's16', str(decoded)], check=True)
                signal, rate = sf.read(decoded, dtype='float32')
                active = np.flatnonzero(np.abs(signal) > .003)
                if len(active) == 0: raise RuntimeError('Silent take: ' + row['key'])
                signal = signal[max(0, active[0] - int(rate * .08)):min(len(signal), active[-1] + int(rate * .18))]
                speech = signal[np.abs(signal) > .003]
                rms = float(np.sqrt(np.mean(speech ** 2)))
                signal *= min(.14 / max(rms, .0001), .85 / float(np.max(np.abs(signal))))
                sf.write(wav_path, signal, rate, subtype='PCM_16')
            result = dict(row)
            result.update(path='res://' + wav_path.relative_to(ROOT).as_posix(), seconds=sf.info(wav_path).duration,
                signature=signature(row), voice_profile=settings, status='generated')
            return result

    # Só retoma quando texto + ator + direção batem exatamente.
    pending = [row for row in rows if row['key'] not in completed or completed[row['key']]['signature'] != signature(row)]
    tasks = [asyncio.create_task(generate(row)) for row in pending]
    for task in asyncio.as_completed(tasks):
        result = await task
        completed[result['key']] = result
        publish(rows, completed, False)
        print(f'EN_VOICE {len(completed)}/{len(rows)} {result["persona"]}', flush=True)
    publish(rows, completed, True)
    print(f'EN_VOICE_COMPLETE lines={len(rows)} personas={len({r["persona"] for r in rows})}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--concurrency', type=int, choices=(1, 2, 3), default=2)
    parser.add_argument('--endpoint', choices=('default', 'msedge'), default='msedge')
    args = parser.parse_args()
    asyncio.run(produce(args.concurrency, args.endpoint))
