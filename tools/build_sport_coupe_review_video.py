"""Codifica os quadros reais do viewport do Godot com os carimbos de tempo gravados.

Rode depois de capture_sport_coupe_redesign.gd, nunca durante um benchmark de tempo de quadro.
Requer o pacote imageio_ffmpeg instalado localmente. Sem captura da área de trabalho.
"""
import argparse
import json
from pathlib import Path
import subprocess

import imageio_ffmpeg


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    folder = args.folder.resolve()
    report = json.loads((folder / "flow.json").read_text(encoding="utf-8"))
    frames = report["frames"]
    if not report["ok"] or report["external_capture"] or not frames:
        raise ValueError("Requires a successful viewport-frame capture")
    manifest = ["ffconcat version 1.0"]
    for index, frame in enumerate(frames):
        source = (folder / frame["file"]).resolve()
        if not source.is_relative_to(folder) or not source.is_file():
            raise ValueError("Missing or external frame path")
        escaped = source.as_posix().replace("'", "'\\''")
        manifest.extend([f"file '{escaped}'", "option framerate 1000"])
        duration = (frames[index + 1]["seconds"] - frame["seconds"]
                    if index + 1 < len(frames) else 1 / 30)
        if duration <= 0:
            raise ValueError("Non-increasing frame timestamp")
        manifest.append(f"duration {duration:.6f}")
    manifest.append(f"file '{escaped}'")
    manifest.append("option framerate 1000")
    concat = folder / "frames.ffconcat"
    concat.write_text("\n".join(manifest) + "\n", encoding="utf-8")
    output = folder / "drive.mp4"
    command = [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-y",
               "-safe", "0", "-i", str(concat), "-fps_mode", "vfr",
               "-c:v", "libx264", "-preset", "fast", "-crf", "18",
               "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output)]
    with (folder / "encode.log").open("w", encoding="utf-8") as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    print(json.dumps({"video": str(output), "source_frames": len(frames),
                      "source_seconds": report["continuous_seconds"]}))


if __name__ == "__main__":
    main()
