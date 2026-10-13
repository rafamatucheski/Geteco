"""Registra hashes das entradas para detectar mudanças concorrentes entre rodadas."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

project_path = Path(__file__).resolve().parents[2]
extensions = {'.gd', '.cs', '.gdshader', '.gdshaderinc', '.tscn', '.tres', '.json'}
source_paths = [project_path / 'project.godot', project_path / 'Main.tscn',
                project_path / 'Harbor.csproj',
                project_path / '.godot/mono/temp/bin/Debug/Harbor.dll',
                project_path / 'tests/measure/benchmark_west_route.gd',
                project_path / 'tests/measure/profile_west_cpu.gd']
for folder_name in ('runtime', 'scripts', 'world', 'gameplay', 'audio', 'systems', 'data'):
    source_paths.extend(path for path in (project_path / folder_name).rglob('*')
                        if path.is_file() and path.suffix in extensions)
hashes = {str(path.relative_to(project_path)).replace('\\', '/'):
          hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(set(source_paths)) if path.is_file()}
digest = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
output_path = project_path / 'evidence/profile-west-cpu-20261013' / (sys.argv[1] + '.inputs.json')
output_path.write_text(json.dumps({'source_digest': digest, 'files': hashes}, indent=2), encoding='utf-8')
print(f'Entradas registradas: {len(hashes)} arquivos; hash {digest}')
