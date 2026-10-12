"""Inventory actual character speech in the current game without starting Godot.

UI notices and documents/terminals are intentionally silent.
The English recording keys remain tied to the exact Portuguese authored line.
"""
from pathlib import Path
import hashlib
import json
import re
from harbor_voice_lines import ROOT, authored

OUTPUT = ROOT / 'audio/mission_voices/en'
TRANSLATIONS = ROOT / 'data/dialogue/english-voice-translations.json'
STRING = r'"(?:[^"\\]|\\.)*"'
DOCUMENTS = {'terminal', 'triagem', 'alarme', 'manifesto', 'anotação'}


def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')


def literal_constant(path, name):
    source = read(path)
    start = re.search(r'(?:const|var) ' + name + r'\s*:?=\s*', source).end()
    literal = re.sub(r'(?m)^\s*#.*$', '', source[start:])
    value, _ = json.JSONDecoder().raw_decode(re.sub(r',(\s*[\]}])', r'\1', literal))
    return value


def inventory():
    rows = {}

    def add(persona, text, en='', section='', aliases=()):
        persona = persona.lower().split(' · ')[0]
        if persona in DOCUMENTS or not persona or not text:
            return
        key = hashlib.sha256((persona + '|' + text).encode()).hexdigest()
        if key not in rows:
            rows[key] = dict(key=key, persona=persona, text=text, en=en, section=section, aliases=list(aliases))
        else:
            if en: rows[key]['en'] = en
            rows[key]['aliases'] = sorted(set(rows[key]['aliases']) | set(aliases))

    for row in authored():
        add(row['persona'], row['text'], row['en'], row['section'])
    for row in json.loads(read('cutscenes/opening/ferry/timing.json'))['lines']:
        add(row['speaker'], row['text'], row['en'], 'opening_ferry')
    # Discover literal spoken exchanges across current gameplay, including new
    # side quests. Do not require every new feature to update a hardcoded list.
    for folder in ['runtime', 'gameplay', 'activities', 'world']:
        for path in sorted((ROOT / folder).rglob('*.gd')):
            source = path.read_text(encoding='utf-8-sig')
            for match in re.finditer(r'"speaker"\s*:\s*(' + STRING + r')\s*,\s*"message"\s*:\s*(' + STRING + r')', source):
                speaker, pt = [json.loads(x) for x in match.groups()]
                add(speaker, pt, section=path.relative_to(ROOT).as_posix())
    source = read('activities/desert_drag/TakeshiDragController.gd')
    for name in ['INTRO', 'VICTORY']:
        add('takeshi', literal_constant('activities/desert_drag/TakeshiDragController.gd', name), section='takeshi_honor')
    for match in re.finditer(r'var words := (' + STRING + r') if[^\n]+ else (' + STRING + r')', source):
        for raw in match.groups(): add('takeshi', json.loads(raw), section='takeshi_honor')
    for section, lines in json.loads(read('data/campaign/mountain-story-dialogue.json')).items():
        for line in lines:
            add(line['speaker'], line['pt'], line['en'], 'mountain_story:' + section)
    for person in literal_constant('data/catalogs/ServiceDialogue.gd', 'PEOPLE').values():
        for text in person['messages']:
            add(person['speaker'], text, section='services')
    # Existing bilingual epilogue text is authoritative, even though the old
    # Portuguese production helper omitted those English strings.
    for match in re.finditer(r'"speaker":(' + STRING + r'),"message":_text\((' + STRING + r'),(' + STRING + r')\)', read('runtime/MissionWorld.gd')):
        speaker, pt, en = [json.loads(x) for x in match.groups()]
        add(speaker, pt, en, 'harbor_epilogue')
    special = [
        ('takeshi', 'Ganhou. Pode entrar na minha casa e olhar os registros. Depois disso, a escolha é tua.', 'You won. You can enter my house and look at the records. After that, the choice is yours.'),
        ('ferrugem', 'Tá. Você dirige bem. O motorista vai atender o Maciota. Teu irmão queria sair de Harbor, mas não parecia estar fugindo.', "All right. You can drive. The driver will take Maciota's call. Your brother wanted out of Harbor, but he didn't look like he was running away."),
    ]
    for speaker, pt, en in special: add(speaker, pt, en, 'harbor_race')
    # All current desert exchanges use literal [speaker, message] pairs.
    for match in re.finditer(r'\[(' + STRING + r'),(' + STRING + r')\]', read('runtime/desert/DesertCampaign.gd')):
        speaker, pt = [json.loads(x) for x in match.groups()]
        add(speaker, pt, section='desert_campaign')
    for path in ['gameplay/urban_v1/CemeteryOperations.gd', 'gameplay/urban_v1/TruckersVillageSecretPassage.gd', 'runtime/desert/DesertRuntime.gd']:
        for match in re.finditer(r'"speaker":(' + STRING + r'),"message":(' + STRING + r')', read(path)):
            speaker, pt = [json.loads(x) for x in match.groups()]
            add(speaker, pt, section=path)
    source = read('gameplay/routines_v1/RoutineCatalog.gd')
    shared = literal_constant('gameplay/routines_v1/RoutineCatalog.gd', 'shared_lines')
    names = literal_constant('gameplay/routines_v1/RoutineCatalog.gd', 'original_names')
    for match in re.finditer(r'\[Vector2\([^\n]*?\),"([A-Z]+)","[^"\n]+",Color\("[^"\n]+"\),(\[[^\n]*\]),(?:true|false)\]', source):
        speaker, messages = match.groups()
        for pt in json.loads(messages) or shared:
            add(names.get(speaker, speaker), pt, section='mountain_residents')
    for match in re.finditer(r'\["ski_[^"\n]+","([A-Z]+)",[^\n]*?,(\["[^\n]*"\])\]', source):
        speaker, messages = match.groups()
        for pt in json.loads(messages): add(speaker, pt, section='ski_lodge')
    sequence = {name: literal_constant('data/GarageSequence.gd', name) for name in ['GREETING', 'REQUEST', 'THANKS', 'MECHANIC_REQUEST']}
    for name in ['GREETING', 'REQUEST', 'THANKS']:
        add('maciota', sequence[name], section='garage_legacy')
    add('maciota', sequence['GREETING'] + '\n\n' + sequence['REQUEST'], section='garage_legacy')
    for pt in [sequence['MECHANIC_REQUEST'], 'Fala primeiro com o Maciota.', 'Pode levar a peça.', 'Tudo certo por aqui.']:
        add('mecânico', pt, section='garage_legacy')
    # Spoken notices and custom conversation panels do not currently pass
    # through show_dialogue; runtime consumers use the same bank keys.
    notice_sources = ['runtime/JessicaRuntime.gd', 'runtime/desert/DesertCampaign.gd',
                      'gameplay/urban_v1/TruckersVillageQuest.gd', 'gameplay/urban_v1/HarborPortSecurity.gd',
                      'runtime/FullSession.gd']
    for path in notice_sources:
        for raw in re.findall(STRING, read(path)):
            value = json.loads(raw)
            match = re.match(r'^(Jessica|Maciota|Tonico|GUARDA|POLÍCIA): (.+)', value, re.S)
            if match:
                add(match[1], match[2], section='spoken_notice:' + path, aliases=[value])
    for persona in ['guarda', 'funcionário', 'operador']:
        for pt in ['O expediente é das 8h às 18h. Mantenha a passagem dos caminhões livre.', 'Estamos fechados. Abrimos às 8h.']:
            add(persona, pt, section='vertice', aliases=[persona.upper() + ': ' + pt])
    for raw in re.findall(r'speech\.text = (' + STRING + ')', read('activities/motocross/Motocross.gd')):
        add('digo', json.loads(raw), section='motocross')
    for pt in literal_constant('gameplay/urban_v1/CemeteryOperations.gd', 'STORIES'):
        add('elias', pt, section='cemetery_stories', aliases=['ELIAS: ' + pt])
    for line in read('world/desert/expansion/DesertRelics.gd').splitlines():
        clue = re.search(r'"clue":(' + STRING + ')', line)
        amount = re.search(r'"amount":(\d+)', line)
        if clue and amount:
            pt = json.loads(clue[1])
            add('dante', pt, section='desert_discoveries', aliases=[pt + '  (+R$ ' + amount[1] + ')'])
    translations = json.loads(TRANSLATIONS.read_text(encoding='utf-8')) if TRANSLATIONS.exists() else {}
    for row in rows.values():
        if not row['en']:
            row['en'] = translations.get(row['text'], '')
        directed = translations.get('_speaker_overrides', {}).get(row['persona'], {}).get(row['text'], '')
        if directed and directed != row['en']:
            # A diction retake can clarify equivalent English wording while
            # preserving the PT authoring key and any existing EN subtitle alias.
            row['aliases'].append(row['en'])
            row['en'] = directed
    return list(rows.values())


def write_catalog():
    rows = inventory()
    missing = sorted({row['text'] for row in rows if not row['en']})
    OUTPUT.mkdir(parents=True, exist_ok=True)
    catalog = {'language': 'en', 'key': 'sha256(persona.lower() + "|" + canonical Portuguese text)',
               'excluded_non_speakers': sorted(DOCUMENTS), 'lines': rows}
    (OUTPUT / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'lines': len(rows), 'personas': sorted({r['persona'] for r in rows}), 'missing_translations': missing}, ensure_ascii=False, indent=2))


if __name__ == '__main__': write_catalog()
