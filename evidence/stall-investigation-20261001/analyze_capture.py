import json
import pathlib
import sys

folder = pathlib.Path(__file__).parent
report = json.loads((folder / (sys.argv[1] + '.json')).read_text(encoding='utf-8-sig'))
engine = (folder / (sys.argv[1] + '.engine.log')).read_text(encoding='utf-8-sig')
log_path = next(line.split(' em ', 1)[1] for line in engine.splitlines() if 'StallLog: gravando' in line)
rows = [json.loads(line) for line in pathlib.Path(log_path).read_text(encoding='utf-8-sig').splitlines()]
header = rows[0]
slow = sorted(report['slow'], key=lambda frame: frame['frame_ms'], reverse=True)
print(json.dumps({'summary': report['summary'], 'configuration': report['configuration'],
                  'shots': max(row['shots'] for row in report['census']),
                  'heartbeat_gaps': len(report['heartbeat_gaps']),
                  'engine_errors': 'SCRIPT ERROR' in engine or '\nERROR:' in engine}, indent=2))
for frame in slow[:8]:
    matches = [row for row in rows if row.get('type') == 'slow' and abs(row['process_frame'] - frame['process_frame']) <= 2]
    print('FRAME ' + json.dumps(frame))
    for row in matches:
        detail = {key: row[key] for key in ['t', 'process_frame', 'frame_ms', 'spans', 'units', 'pipelines_delta'] if key in row}
        detail['work'] = [event for event in row.get('work', []) if event.get('ms', 0) >= 2]
        print('LOG ' + json.dumps(detail))
loads = {}
for row in rows:
    for label, value in row.get('work_summary', {}).items():
        if '.load' not in label and label != 'vehicle_tires.skid_voice':
            continue
        stats = loads.setdefault(label, {'count': 0, 'max_ms': 0.0})
        stats['count'] += value['count']
        stats['max_ms'] = max(stats['max_ms'], value['max_ms'])
print('LOADS ' + json.dumps(loads))
print('WRITER ' + json.dumps(max((row['writer'] for row in rows if row.get('writer')), key=lambda row: row['max_write_ms'])))
