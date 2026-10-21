import json, hashlib
from pathlib import Path
root=Path('D:/geteco/game')
base=root/'artifacts/car-fleet-implementation-20261019'
manifest=json.loads((base/'candidates/current-manifest.json').read_text())
for id,row in manifest.items():
    prod=root/f'assets/fleet/redesigned/{id}.scn'
    candidate=base/f'candidates/{id}.scn'
    original=base/f'originals-current/{id}.scn'
    row['installed_path']=str(prod)
    row['installed_sha256']=hashlib.sha256(prod.read_bytes()).hexdigest()
    row['candidate_sha256']=hashlib.sha256(candidate.read_bytes()).hexdigest()
    row['original_sha256']=hashlib.sha256(original.read_bytes()).hexdigest()
    assert row['installed_sha256']==row['candidate_sha256'],id
(base/'current-installed-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('All 9 installed hashes match reviewed candidates; original hashes recorded.')
