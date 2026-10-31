"""Autoload .NET real: watchdog de etapa, correlação de erros, spans de quadro rápido e detalhes limitados."""
import json
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
os.environ['HARBOR_SESSION_LOG'] = '1'
os.environ['HARBOR_SESSION_PROFILE'] = '1'
run = subprocess.run([sys.argv[1], '--headless', '--path', str(root), '--script',
                      'res://tests/test_session_detail.gd'], capture_output=True, text=True,
                     encoding='utf-8', errors='replace', timeout=45)
assert run.returncode == 0, run.stdout + run.stderr
marker = 'SESSION_DETAIL_PATH '
folder = pathlib.Path(next(line.split(marker, 1)[1] for line in run.stdout.splitlines() if marker in line))
rows = [json.loads(line) for p in sorted(folder.glob('session-*.jsonl'))
        for line in p.read_text(encoding='utf-8-sig').splitlines()]
data = [r.get('data',r) for r in rows]
assert data[0]['schema'] == 5
errors = [r for r in data if r['type'] == 'error']
assert len(errors) == 1, errors
assert errors[0]['active_operations'][0]['system'] == 'test_loader'
assert any(r.get('type') == 'main_thread_unresponsive' and r['active_operations'] for r in data)
assert any(r.get('type') == 'operations_pending' and r['operations'][0]['operation'] == 'blocking_load' for r in data)
end = next(r for r in data if r['type'] == 'operation_end')
assert end['duration_ms'] >= 6200 and end['details']['region'] == 'fixture'
slow = [r for r in data if r['type'] == 'slow_operations']
small = next(r for r in slow if any(s['label'] == 'fixture.small_work' for s in r['slow_spans']))
assert small['frame_ms'] < 33.3, small
assert small['slow_spans'][0]['details']['queued_after'] == 7
bounded = next(r for r in slow if any(s['label'] == 'fixture.bounded' for s in r['slow_spans']))
assert len(bounded['slow_spans']) == 16 and bounded['dropped'] == 4
aggregates = [r['systems']['fixture.bounded'] for r in data if r['type'] == 'system_metrics' and 'fixture.bounded' in r['systems']]
assert sum(r['calls'] for r in aggregates) == 20
assert sum(r['slow_calls'] for r in aggregates) == 20
assert len([r for r in data if r['type'] == 'telemetry_error']) == 1
assert data[-1]['type'] == 'session_end'
assert data[-1]['unfinished_operations'][0]['operation'] == 'unfinished'
assert not any(r.get('type') == 'records_dropped' for r in data)
print('PASS: watchdog, stages, error correlation, fast-frame detail, bounded events, malformed record recovery, unfinished stage', folder)

history = [r for r in data if r['type'] == 'frame_history']
assert any(r['phase'] == 'before' and r['frames'] for r in history)
assert data[0]['clock_sync']['stopwatch_frequency'] > 0
assert all('process_frame' in frame and 'late_process_usec' in frame for r in history for frame in r['frames'])
assert any('runtime' in frame['context'] for r in history for frame in r['frames'])
assert any(r['phase'].startswith('after') and r['frames'] for r in history)
assert all(len(r['frames']) <= 360 for r in history)
assert any(r['runtime']['gc_collections'] for r in history if 'runtime' in r)
assert any(r['type'] == 'lifecycle_events' and r['events'][0]['details']['queued_after'] == 7 for r in data)
print('PASS: bounded incident history, runtime memory counters and fast lifecycle details')
