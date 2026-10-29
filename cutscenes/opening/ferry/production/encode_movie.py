"""Trim the actual frame marker, retain constant 30 fps, mux dialogue into Theora.
Also writes a shareable H.264 review with the complete mix and switchable subtitles.
"""
from pathlib import Path
import argparse, json, subprocess, sys
import imageio_ffmpeg
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--art",type=Path,default=Path("D:/geteco/artifacts/opening-ferry-night-20261003"))
parser.add_argument("--movie-only",action="store_true")
parser.add_argument("--movie-output",type=Path,default=ROOT/"arrival.ogv")
args=parser.parse_args()
ART=args.art
MOVIE=args.movie_output
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
# Theora q6, não q7 (28/10): o filme de 16/10 saiu com 99,7 MB em q7, colado no limite de 100 MB por arquivo
# do GitHub; q6 deu 64,5 MB com PSNR médio de 44 dB (mínimo 41) contra o q7.
render=json.loads((ART/"render.json").read_text(encoding="utf-8"))
duration=render["duration"]
start=render["start_frame"]/render["fps"]
common=[FFMPEG,"-hide_banner","-loglevel","warning","-y","-ss",str(start),"-i",str(ART/"source1080.avi")]
video_filter=f"setpts=PTS-STARTPTS,fade=t=in:st=0:d=0.7,fade=t=out:st={duration-.6}:d=0.6"
subprocess.run(common+["-i",str(ROOT/"production/voice.wav"),"-map","0:v:0","-map","1:a:0","-t",str(duration),"-vf",video_filter,"-af","asetpts=N/SR/TB",
    "-c:v","libtheora","-q:v","6","-pix_fmt","yuv420p","-r","30","-c:a","libvorbis","-q:a","5",str(MOVIE)],check=True)
if "--movie-only" in sys.argv:
    print(json.dumps({"movie_bytes":MOVIE.stat().st_size}))
    sys.exit(0)
subprocess.run(common+["-i",str(ROOT/"production/review_mix.wav"),"-i",str(ROOT/"production/pt.srt"),"-i",str(ROOT/"production/en.srt"),
    "-map","0:v:0","-map","1:a:0","-map","2:0","-map","3:0","-t",str(duration),"-vf",video_filter,
    "-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p","-r","30","-c:a","aac","-b:a","192k",
    "-c:s","mov_text","-metadata:s:s:0","language=por","-metadata:s:s:1","language=eng","-disposition:s:0","default","-movflags","+faststart",
    str(ART/"Harbor-intro-noite-chuva-PT-BR.mp4")],check=True)
print(json.dumps({"start_seconds":start,"duration":duration,"movie_bytes":MOVIE.stat().st_size,
                  "review_bytes":(ART/"Harbor-intro-noite-chuva-PT-BR.mp4").stat().st_size},indent=2))
