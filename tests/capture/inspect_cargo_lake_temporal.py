"""Inspeciona o fluxo real do MovieWriter; picos de pixel são candidatos, não veredictos."""
import json
import argparse
from pathlib import Path
import cv2
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('--folder', type=Path, required=True)
parser.add_argument('--movie', type=Path, required=True)
args = parser.parse_args()
folder = args.folder.resolve()
metadata = json.loads((folder / 'temporal.json').read_text(encoding='utf-8'))
timeline = metadata['timeline']
movie = args.movie.resolve()
cap = cv2.VideoCapture(str(movie))
frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
movie_fps = cap.get(cv2.CAP_PROP_FPS)
width, height = int(cap.get(3)), int(cap.get(4))
begin = int(metadata['first_movie_frame'])
by_frame = {int(row['frame']): row for row in timeline}
selected = {}
for target in [2, 7, 12, 20, 27, 32, 37, 42, 50, 57]:
    row = min(timeline, key=lambda item: abs(item['sim_seconds']-target))
    selected[int(row['frame'])] = f'sequence-{target:02d}s.png'
out = folder / 'review'
out.mkdir(exist_ok=True)
decoded = 0
observed = 0
candidates = []
previous = None
before_previous = None
last_delta = 0.0
worst = []
while True:
    ok, frame = cap.read()
    if not ok:
        break
    index = decoded
    decoded += 1
    if index in selected:
        cv2.imwrite(str(out / selected[index]), frame)
    if index not in by_frame:
        continue
    observed += 1
    small = cv2.resize(frame, (480, 270), interpolation=cv2.INTER_AREA)[45:240, 100:450].astype(np.float32)
    if previous is not None:
        delta = float(np.abs(small-previous).mean())
        t = by_frame[index]['sim_seconds']
        if abs(t-30.0) > .25:
            worst.append((delta, index, t))
            if before_previous is not None:
                return_delta = float(np.abs(small-before_previous).mean())
                if delta > 2 and last_delta > 2 and return_delta < min(delta,last_delta)*.55:
                    candidates.append({'frame':index-1,'sim_seconds':t-1/movie_fps,'mean_delta':last_delta,'return_delta':return_delta})
        last_delta = delta
    before_previous, previous = previous, small
cap.release()
worst.sort(reverse=True)
report = {'movie':str(movie),'fps':movie_fps,'resolution':[width,height],'reported_frames':frame_count,'decoded_frames':decoded,'timeline_frames':len(timeline),'observed_timeline_frames':observed,'timeline_contiguous':all(int(b['frame'])==int(a['frame'])+1 for a,b in zip(timeline,timeline[1:])), 'missing_rendered_frames':len(timeline)-observed,'candidates':candidates,'largest_changes':worst[:12], 'notes':'All encoded frames decoded. Centre ROI excludes much of HUD; camera/fire/actors can create legitimate pixel changes. Human/model visual review remains required. The day/night cut is excluded from spike detection.'}
(folder/'inspection.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
