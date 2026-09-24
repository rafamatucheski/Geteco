"""Assemble recorded frames, without modifying gameplay assets.

Columns: original V2 / live V1 / corrected V2. Silent frame sequences at
10 frames/s are presentation evidence, never a frame-time measurement.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import imageio_ffmpeg

root = Path(__file__).resolve().parents[1]
out = root / "evidence" / "police-0922"
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
inputs = [out / "before/frame-%03d.png", out / "v1-tiers/frame-%03d.png", out / "final-video/frame-%03d.jpg"]
command = [ffmpeg, "-y", "-loglevel", "error"]
for source in inputs:
    command += ["-stream_loop", "-1", "-framerate", "10", "-i", str(source)]
command += ["-filter_complex", "[0:v]scale=640:360[a];[1:v]scale=640:360[b];[2:v]scale=640:360[c];[a][b][c]hstack=inputs=3[v]",
            "-map", "[v]", "-t", "12", "-an", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", str(out / "v2-before_v1_v2-after.mp4")]
subprocess.run(command, check=True)
hashes = []
for family in ("pistol", "smg"):
    for take in range(3):
        relative = f"{family}_{take}.wav"
        v1 = root.parent / "audio/acoustic" / relative
        v2 = root / "assets/gameplay/audio" / relative
        one = hashlib.sha256(v1.read_bytes()).hexdigest()
        two = hashlib.sha256(v2.read_bytes()).hexdigest()
        hashes.append({"sample": relative, "v1_sha256": one, "v2_sha256": two, "identical": one == two})
(out / "audio-comparison.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
print(out / "v2-before_v1_v2-after.mp4")
