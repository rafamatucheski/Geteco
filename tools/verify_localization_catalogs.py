"""Check authored localization data without changing runtime or player settings."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Ignore literal %% and a space after a percent (e.g. '60% de integridade').
FORMAT = re.compile(r'%(?:[-+0#]*\d*(?:\.\d+)?)?[sdif]')


def audit():
    messages, owners, conflicts, failures = {}, {}, [], []
    files = sorted((ROOT / 'data/localization').glob('*.en.json'))
    for path in files:
        pairs = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(pairs, dict) or not pairs:
            failures.append(f'Empty or invalid catalog: {path.name}')
            continue
        for pt, en in pairs.items():
            if not pt or not isinstance(en, str) or not en:
                failures.append(f'Invalid translation: {path.name}: {pt}')
                continue
            if FORMAT.findall(pt.replace('%%', '')) != FORMAT.findall(en.replace('%%', '')):
                failures.append(f'Format placeholders differ: {path.name}: {pt}')
            if pt in messages and messages[pt] != en:
                conflicts.append({'source': pt, 'first': owners[pt], 'last': path.name})
            messages[pt], owners[pt] = en, path.name
    presets = (ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
    filters = re.findall(r'^include_filter="(.*)"$', presets, re.M)
    for index, value in enumerate(filters):
        for required in ['data/localization/*.json', 'data/dialogue/english-voice-translations.json']:
            if required not in value:
                failures.append(f'Export preset {index} misses {required}')
    return {'catalogs': len(files), 'unique_pairs': len(messages), 'conflicts': conflicts,
            'failures': failures, 'scope': 'Catalog schema, format placeholders and export filters; not proof of complete in-game text coverage.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = audit()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f"LOCALIZATION_CATALOGS files={result['catalogs']} pairs={result['unique_pairs']} conflicts={len(result['conflicts'])} failures={len(result['failures'])}")
    for failure in result['failures']:
        print(failure)
    raise SystemExit(bool(result['failures']))
