"""Fill missing Portuguese recordings without replacing approved existing takes.

Uses the same finite offline-asset pipeline as English. Published manifests are
merged only after every missing recording has been produced successfully.
"""
import asyncio
import json
import generate_english_voices as generator
from english_voice_catalog import ROOT, inventory
from generate_maciota_voice import PROFILE, write_json

OUTPUT = ROOT / 'audio/mission_voices/pt_complete'
FEMALE = set('ana bia cecília cida dora helena inês irene jessica lia luísa lívia mila moradora nora rute tita íris'.split()) | {
    'dona cida', 'dona marlene', 'dona nena', 'dona zefa', 'enfermeira clara', 'joana',
}


def main():
    main_path = ROOT / 'audio/mission_voices/recordings.json'
    maciota_path = ROOT / 'audio/mission_voices/maciota_baritone/recordings.json'
    main_bank = json.loads(main_path.read_text(encoding='utf8'))
    maciota_bank = json.loads(maciota_path.read_text(encoding='utf8'))
    previous = json.loads((OUTPUT / 'production.json').read_text(encoding='utf8')) if (OUTPUT / 'production.json').exists() else {}
    produced_keys = {row['key'] for row in previous.get('lines', [])}
    rows = []
    for row in inventory():
        bank = maciota_bank if row['persona'] in ('maciota', 'caller') else main_bank
        path = ROOT / bank.get(row['key'], 'res://missing')[6:]
        if path.is_file() and row['key'] not in produced_keys:
            continue
        row = dict(row, en=row['text'])
        rows.append(row)
    generator.OUTPUT = OUTPUT
    generator.inventory = lambda: rows
    generator.PROFILES = {
        persona: generator.profile('pt-BR-FranciscaNeural' if persona in FEMALE else 'pt-BR-AntonioNeural')
        for persona in {row['persona'] for row in rows}
    }
    for persona in ('maciota', 'caller'):
        generator.PROFILES[persona] = {key: PROFILE[key] for key in ('voice','rate','pitch','volume')}
    asyncio.run(generator.produce(3, 'msedge'))
    completed = json.loads((OUTPUT / 'production.json').read_text(encoding='utf8'))
    # The shared generator publishes paths under its usual language folder.
    # Canonicalize to this supplemental bank before exposing any take at runtime.
    for row in completed['lines']:
        row['path'] = 'res://audio/mission_voices/pt_complete/' + row['key'] + '.wav'
        bank = maciota_bank if row['persona'] in ('maciota', 'caller') else main_bank
        bank[row['key']] = row['path']
    completed['language'] = 'pt_BR'
    write_json(OUTPUT / 'production.json', completed)
    write_json(OUTPUT / 'recordings.json', {row['key']:row['path'] for row in completed['lines']})
    write_json(main_path, main_bank)
    write_json(maciota_path, maciota_bank)
    print('PT_VOICE_COMPLETE', len(rows), flush=True)


if __name__ == '__main__':
    main()
