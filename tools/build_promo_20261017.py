"""Monta o trailer de 30 s do Harbor (17/10/2026) a partir de capturas reais do jogo, sem HUD.

Fontes:
  - abertura da balsa já renderizada (cutscenes/opening/ferry/arrival.ogv) e as faixas separadas
    de voz e ambiente do mesmo filme, para cortar as falas com precisão;
  - tomadas gravadas por tools/capture_promo_20261017.gd (<cena>.avi + <cena>-shots.json) em
    evidence/promo-20261017/;
  - trilha do Gemini (Lyria) que ficou fora do jogo: a versão de ~100 BPM da música de
    carregamento (evidence/firefly_originais_20261015/musica/loading_gtadark_raw.wav). A batida
    entra em 11,71 s da faixa e cai exatamente no corte para a ação (HIT).

O quadro final é composto aqui em numpy (faixas de cinema, legendas, títulos, clarão na batida,
gradação leve) e codificado em H.264 + AAC. Uso: python tools/build_promo_20261017.py [--preview]
"""
import json, os, subprocess, sys
import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTURES = os.path.join(ROOT, "evidence", "promo-20261017")
OUT = os.path.join(CAPTURES, "edit")
FERRY = os.path.join(ROOT, "cutscenes", "opening", "ferry")
MUSIC = os.path.join(ROOT, "evidence", "firefly_originais_20261015", "musica", "loading_gtadark_raw.wav")
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "barlow", "BarlowSemiCondensed-SemiBold.ttf")
FONT_REGULAR = os.path.join(ROOT, "assets", "fonts", "barlow", "BarlowSemiCondensed-Regular.ttf")
try:
    import imageio_ffmpeg
    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except ImportError:
    FFMPEG = "ffmpeg"

W, H, FPS, RATE = 1920, 1080, 30, 48000
LENGTH = 30.0
HIT = 14.5                 # corte para a ação, em cima da batida da música
MUSIC_HIT = 11.71          # onde a batida cai na faixa original
MUSIC_OFFSET = HIT - MUSIC_HIT
TITLE_AT = 26.4            # cartão final
BAR = 135                  # faixas pretas do filme da balsa (12,5 % em cima e embaixo)

# Cada plano: onde começa no trailer, quanto dura e de onde vem. "film" é o tempo no
# arrival.ogv; "take"/"offset" apontam uma tomada gravada pelo capture_promo_20261017.gd.
TIMELINE = [
    dict(at=0.0, dur=2.1, film=1.6),                      # balsa chegando de noite, chuva
    dict(at=2.1, dur=2.6, film=31.8),                     # Dante atende o telefone
    dict(at=4.7, dur=1.25, film=37.0),                    # "Meu irmão?"
    dict(at=5.95, dur=1.35, film=42.2, fade_out=.35),     # lembrança do Vicente: "Viram ele em Harbor."
    # Áreas, ainda calmas, com a música crescendo.
    dict(at=7.3, dur=1.3, take="v1/vistas:cidade", offset=1.0, fade_in=.3),
    dict(at=8.6, dur=1.2, take="v1/vistas:sobrados", offset=1.2),
    dict(at=9.8, dur=1.1, take="v1/policia:fuga_alto", offset=1.2),
    dict(at=10.9, dur=1.0, take="v1/deserto:dunas", offset=1.2),
    dict(at=11.9, dur=1.0, take="v1/serra:descida_alto", offset=1.0),
    # Tensão: pilotos no portão em câmera lenta; a largada cai na batida.
    dict(at=12.9, dur=1.6, take="v1/moto:moto_chase", offset=1.6, speed=[(0, 1.0), (.9, 1.0), (1.4, .3)]),
    dict(at=14.5, dur=1.4, take="v1/moto:moto_chase", offset=2.8, speed=[(0, 1.5), (.6, 1.0)]),
    # Ação no ritmo da música.
    dict(at=15.9, dur=1.2, take="v1/corrida:lider", offset=1.6),
    dict(at=17.1, dur=1.3, take="v1/tiroteio:ombro", offset=0.5),
    dict(at=18.4, dur=1.0, take="v1/tiroteio:contraplano", offset=1.0),
    dict(at=19.4, dur=1.0, take="v1/policia:helicoptero", offset=1.0),
    dict(at=20.4, dur=1.2, take="v1/moto:moto_chase", offset=3.6),
    dict(at=21.6, dur=1.6, take="v1/tiroteio:rpg", offset=0.6),
    dict(at=23.2, dur=1.2, take="v1/serra:descida", offset=0.6),
    dict(at=24.4, dur=1.0, take="v1/corrida:pelotao", offset=0.2),
    dict(at=25.4, dur=1.0, take="v1/moto:moto_frente", offset=1.5),
]

# Falas: (início no trailer, início e fim no voice.ogg, legenda)
LINES = [
    (2.25, 31.05, 31.55, "Dante?"),
    (3.05, 34.05, 35.70, "O Vicente saiu da prisão."),
    (4.75, 37.05, 37.65, "Meu irmão?"),
    (6.0, 42.00, 43.15, "Viram ele em Harbor."),
]

# Rótulos das áreas no começo da montagem (aparecem no canto inferior esquerdo).
LABELS = [
    (7.45, 8.5, "A cidade"),
    (8.75, 9.7, "O litoral"),
    (9.95, 10.8, "A ponte"),
    (11.0, 11.8, "O deserto"),
    (12.0, 12.8, "A serra"),
]
SHAKES = [(14.5, 16), (17.3, 4), (18.6, 5), (22.3, 18), (23.2, 5)]  # (instante, amplitude em px)
WHIPS = [15.9, 19.4, 20.4, 24.4, 25.4]  # cortes com transição em chicote
TITLES = [(0.25, 1.95, "RCM STUDIOS", "apresenta")]


def run(args, **kw):
    return subprocess.run([FFMPEG, "-v", "error", "-y"] + [str(a) for a in args], check=True, **kw)


def font(path, size):
    return ImageFont.truetype(path, size)


def load_manifest(scene):
    path = os.path.join(CAPTURES, scene + "-shots.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def source_of(shot):
    """Arquivo e instante inicial (s) de um plano."""
    if "film" in shot:
        return os.path.join(FERRY, "arrival.ogv"), shot["film"]
    scene, take = shot["take"].split(":")
    manifest = load_manifest(scene)
    entry = next(s for s in manifest["shots"] if s["label"] == take)
    used = source_offsets(shot, int(round(shot["dur"] * FPS)) + 1, FPS)[-1]
    assert shot.get("offset", 0) + used <= entry["seconds"] + 1e-3, (shot, used, entry["seconds"])
    return os.path.join(CAPTURES, scene + ".avi"), entry["start_frame"] / FPS + shot.get("offset", 0)


def read_frames(path, start, count, speed=1.0):
    """Lê `count` quadros RGB a partir de `start` (s); speed < 1 desacelera a tomada."""
    vf = f"setpts=PTS/{speed},fps={FPS}," if speed != 1.0 else f"fps={FPS},"
    vf += f"scale={W}:{H}:flags=lanczos"
    proc = subprocess.run([FFMPEG, "-v", "error", "-ss", f"{start:.4f}", "-i", path, "-frames:v", str(count),
                           "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], check=True, capture_output=True)
    data = np.frombuffer(proc.stdout, np.uint8)
    n = len(data) // (W * H * 3)
    frames = data[: n * W * H * 3].reshape(n, H, W, 3)
    if n < count:  # repete o último quadro se a fonte acabar antes
        frames = np.concatenate([frames, np.repeat(frames[-1:], count - n, 0)])
    return frames


def grade(frame, shot):
    """Gradação leve: curva em S e saturação. A abertura noturna já vem tratada."""
    if "film" in shot:
        return frame
    x = frame.astype(np.float32) / 255.0
    x = x + (x - x * x) * 0.0  # mantém o tom-base
    s = 0.5 - np.cos(np.pi * np.clip(x, 0, 1)) * 0.5
    x = x * 0.7 + s * 0.3
    luma = (x * [0.2126, 0.7152, 0.0722]).sum(-1, keepdims=True)
    x = luma + (x - luma) * shot.get("saturation", 1.12)
    return (np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8)


VIGNETTE = None


def vignette():
    global VIGNETTE
    if VIGNETTE is None:
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
        VIGNETTE = (1.0 - np.clip(d - 0.75, 0, 1) * 0.35)[..., None]
    return VIGNETTE


def source_offsets(shot, count, rate):
    """Instante na fonte (s, a partir do início do plano) para cada amostra de saída.
    "speed" pode ser um número ou uma rampa [(t_local, velocidade), ...]: a câmera lenta
    antes da batida e a aceleração depois saem daqui, para imagem e som juntos."""
    t = np.arange(count) / rate
    speed = shot.get("speed", 1.0)
    if isinstance(speed, (int, float)):
        v = np.full(count, float(speed))
    else:
        xs, ys = zip(*speed)
        v = np.interp(t, xs, ys)
    return np.concatenate([[0.0], np.cumsum(v[:-1]) / rate])


def shake_offset(t):
    """Tremor de câmera: soma de impulsos amortecidos nos impactos (SHAKES)."""
    dx = dy = 0.0
    for at, amp in SHAKES:
        age = t - at
        if 0 <= age < 0.6:
            k = amp * np.exp(-age * 7.0)
            dx += k * np.sin(age * 2 * np.pi * 13 + at)
            dy += k * np.cos(age * 2 * np.pi * 11 + at * 1.7) * .7
    return dx, dy


def apply_shake(frame, t):
    dx, dy = shake_offset(t)
    if abs(dx) < 0.3 and abs(dy) < 0.3:
        return frame
    scale = 1.0 + (abs(dx) + abs(dy)) / W * 2.2
    m = cv2.getRotationMatrix2D((W / 2, H / 2), dx * .02, scale)
    m[0, 2] += dx
    m[1, 2] += dy
    return cv2.warpAffine(frame, m, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)


def apply_whip(frame, t):
    """Transição em chicote: borrão horizontal forte nos 3 quadros de cada lado do corte."""
    for at in WHIPS:
        dt = t - at
        if -0.1 <= dt < 0.1:
            k = 1.0 - abs(dt + 1 / (2 * FPS)) / 0.1
            size = int(10 + 150 * max(0.0, k))
            shift = int((1 if dt < 0 else -1) * 120 * max(0.0, k))
            blurred = cv2.blur(frame, (size, 1))
            return np.roll(blurred, -shift, axis=1)
    return frame


GRAIN_RNG = np.random.default_rng(11)


def apply_grain(frame, amount=3.2):
    noise = GRAIN_RNG.normal(0, amount, (H // 2, W // 2)).astype(np.float32)
    noise = cv2.resize(noise, (W, H), interpolation=cv2.INTER_LINEAR)
    return frame + noise[..., None]


def bar_height(t):
    if t < HIT:
        return BAR
    # Na batida as faixas abrem em 0,3 s: o filme vira jogo.
    k = min(1.0, (t - HIT) / 0.3)
    k = k * k * (3 - 2 * k)
    target = 0 if t < TITLE_AT else 0
    return int(round(BAR + (target - BAR) * k))


def text_layer(t):
    """Camada RGBA de textos para o instante t, ou None."""
    items = []
    for at, voice_start, voice_end, text in LINES:
        end = at + (voice_end - voice_start) + 0.35
        if at - 0.05 <= t <= end:
            a = min(1, (t - at + 0.05) / 0.12, (end - t) / 0.15)
            items.append(("caption", text, a))
    for at, end, big, small in TITLES:
        if at <= t <= end:
            a = min(1, (t - at) / 0.35, (end - t) / 0.35)
            items.append(("presents", (big, small, (t - at) / (end - at)), a))
    for at, end, text in LABELS:
        if at <= t <= end:
            a = min(1, (t - at) / 0.15, (end - t) / 0.15)
            items.append(("label", (text, (t - at) / (end - at)), a))
    if t >= TITLE_AT:
        items.append(("title", t - TITLE_AT, 1.0))
    if not items:
        return None
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for kind, value, alpha in items:
        alpha = max(0.0, min(1.0, alpha))
        if kind == "caption":
            f = font(FONT_REGULAR, 40)
            w = draw.textlength(value, font=f)
            y = H - BAR + (BAR - 40) // 2 - 6
            draw.text(((W - w) / 2, y), value, font=f, fill=(235, 236, 238, int(255 * alpha)))
        elif kind == "presents":
            big, small, k = value
            f = font(FONT_BOLD, 64)
            spacing = 22 + 10 * k  # letras se afastam devagar
            draw_tracked(draw, big, f, W / 2, H / 2 - 52, spacing, (240, 242, 245, int(255 * alpha)))
            f2 = font(FONT_REGULAR, 30)
            draw_tracked(draw, small.upper(), f2, W / 2, H / 2 + 30, 10, (170, 190, 200, int(230 * alpha)))
        elif kind == "label":
            text, k = value
            f = font(FONT_BOLD, 34)
            x0 = 96 + 18 * k
            draw.rectangle([x0 - 22, H - 172, x0 - 16, H - 134], fill=(255, 196, 64, int(255 * alpha)))
            draw_tracked(draw, text.upper(), f, None, H - 174, 9, (245, 245, 245, int(255 * alpha)), left=x0)
    layer = layer.filter(ImageFilter.GaussianBlur(0)) if False else layer
    return layer


def draw_tracked(draw, text, f, cx, y, spacing, fill, left=None):
    widths = [draw.textlength(c, font=f) for c in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = left if left is not None else cx - total / 2
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=f, fill=fill)
        x += w + spacing


def title_card(local):
    """Cartão final: HARBOR / EM DESENVOLVIMENTO / RCM STUDIOS sobre preto."""
    img = Image.new("RGB", (W, H), (6, 9, 13))
    draw = ImageDraw.Draw(img)
    def fade(at, dur=0.45):
        k = max(0.0, min(1.0, (local - at) / dur))
        return k * k * (3 - 2 * k)
    a = fade(0.1, 0.25)
    scale = 1.0 + 0.04 * max(0.0, 1 - local / 3.6)
    f = font(FONT_BOLD, int(190 * scale))
    c = int(244 * a)
    draw_tracked(draw, "HARBOR", f, W / 2, H / 2 - 190, int(34 * scale), (c, c, min(255, c + 4)))
    a2 = fade(0.9)
    line = int(260 * a2)
    draw.rectangle([W / 2 - line, H / 2 + 55, W / 2 + line, H / 2 + 57], fill=(int(255 * a2), int(196 * a2), int(64 * a2)))
    f2 = font(FONT_BOLD, 40)
    draw_tracked(draw, "EM DESENVOLVIMENTO", f2, W / 2, H / 2 + 82, 14, tuple(int(v * a2) for v in (226, 230, 235)))
    a3 = fade(1.7)
    f3 = font(FONT_REGULAR, 30)
    draw_tracked(draw, "RCM STUDIOS", f3, W / 2, H / 2 + 196, 16, tuple(int(v * a3) for v in (150, 170, 182)))
    return np.asarray(img)


def compose(preview=False):
    os.makedirs(OUT, exist_ok=True)
    total = int(round(LENGTH * FPS))
    video_path = os.path.join(OUT, "video.mp4")
    enc = subprocess.Popen([FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow" if not preview else "veryfast",
                            "-crf", "15" if not preview else "23", "-pix_fmt", "yuv420p", video_path], stdin=subprocess.PIPE)
    rng = np.random.default_rng(7)
    frame_index = 0
    cache = {}
    for i in range(total):
        t = i / FPS
        if t >= TITLE_AT:
            frame = np.clip(apply_grain(title_card(t - TITLE_AT).astype(np.float32), 2.0), 0, 255).astype(np.uint8)
            enc.stdin.write(np.ascontiguousarray(frame).tobytes())
            continue
        shot = next(s for s in TIMELINE if s["at"] <= t + 1e-6 < s["at"] + s["dur"])
        key = id(shot)
        if key not in cache:
            cache.clear()
            path, start = source_of(shot)
            n_out = int(round(shot["dur"] * FPS)) + 1
            offsets = source_offsets(shot, n_out, FPS)
            count = int(np.ceil(offsets[-1] * FPS)) + 3
            cache[key] = ([grade(f, shot) for f in read_frames(path, start, count)], offsets)
        frames, offsets = cache[key]
        local = min(int(round((t - shot["at"]) * FPS)), len(offsets) - 1)
        position = offsets[local] * FPS
        a = min(int(position), len(frames) - 1)
        b = min(a + 1, len(frames) - 1)
        w = position - int(position)
        # Câmera lenta: mistura os dois quadros vizinhos em vez de repetir o mesmo.
        frame = frames[a].astype(np.float32) if w < .05 or a == b else frames[a].astype(np.float32) * (1 - w) + frames[b].astype(np.float32) * w
        if "take" in shot:
            frame = apply_whip(apply_shake(frame, t), t)
        frame *= vignette()
        # Fades por plano (entrada/saída de preto) e clarão na batida.
        fin, fout = shot.get("fade_in", 0), shot.get("fade_out", 0)
        lt = t - shot["at"]
        if fin and lt < fin: frame *= lt / fin
        if fout and shot["dur"] - lt < fout: frame *= max(0.0, (shot["dur"] - lt) / fout)
        if HIT <= t < HIT + 0.1: frame = frame * 0.4 + 255 * 0.6 * (1 - (t - HIT) / 0.1)
        frame = apply_grain(frame)
        frame = np.clip(frame, 0, 255)
        b = bar_height(t)
        if b > 0:
            frame[:b] = 0
            frame[H - b:] = 0
        img = Image.fromarray(frame.astype(np.uint8))
        layer = text_layer(t)
        if layer is not None:
            img.paste(layer, (0, 0), layer)
        out = np.asarray(img)
        enc.stdin.write(np.ascontiguousarray(out).tobytes())
        if i % 60 == 0:
            print(f"quadro {i}/{total}", flush=True)
    enc.stdin.close()
    enc.wait()
    return video_path


def load_audio(path, start=0.0, duration=None):
    tmp = os.path.join(OUT, "_audio.wav")
    args = ["-ss", f"{start:.4f}", "-i", path]
    if duration is not None:
        args += ["-t", f"{duration:.4f}"]
    run(args + ["-vn", "-ac", "2", "-ar", str(RATE), tmp])
    x, _ = sf.read(tmp, always_2d=True, dtype="float32")
    return x


def place(mix, clip, at, gain=1.0, fade=0.01):
    start = int(round(at * RATE))
    if start >= len(mix):
        return
    clip = clip[: len(mix) - start].copy()
    n = min(len(clip), int(fade * RATE))
    if n > 1:
        ramp = np.linspace(0, 1, n)[:, None]
        clip[:n] *= ramp
        clip[-n:] *= ramp[::-1]
    mix[start:start + len(clip)] += clip * gain


def envelope(points, length):
    """Curva de ganho por trechos lineares: [(t, ganho), ...]."""
    t = np.arange(length) / RATE
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)[:, None]


def mix_audio():
    n = int(LENGTH * RATE)
    voice = np.zeros((n, 2), np.float32)
    world = np.zeros((n, 2), np.float32)
    # Ambiente do filme alinhado a cada plano da balsa (chuva, mar, motor da balsa).
    for shot in TIMELINE:
        if "film" in shot:
            amb = load_audio(os.path.join(FERRY, "ambience.ogg"), shot["film"], shot["dur"])
            place(world, amb, shot["at"], 0.9, fade=0.08)
        elif "take" in shot:
            path, start = source_of(shot)
            offsets = source_offsets(shot, int(shot["dur"] * RATE), RATE)
            clip = load_audio(path, start, offsets[-1] + 0.05)
            # Som acompanha a rampa (fica grave na câmera lenta, como fita).
            clip = clip[np.minimum((offsets * RATE).astype(int), len(clip) - 1)]
            place(world, clip, shot["at"], shot.get("gain", 0.8), fade=0.02)
    for at, a, b, _ in LINES:
        place(voice, load_audio(os.path.join(FERRY, "voice.ogg"), a - 0.05, b - a + 0.15), at - 0.05, 1.0, fade=0.03)
    music = np.zeros((n, 2), np.float32)
    src, rate = sf.read(MUSIC, always_2d=True, dtype="float32")
    assert rate == RATE
    first = int(max(0.0, -MUSIC_OFFSET) * RATE)
    place(music, src[first:first + n], max(0.0, MUSIC_OFFSET), 1.0, fade=0.5)
    # Ferrão do cartão final: repete a batida de entrada para o título cair em cima dela.
    hit_clip = src[int((MUSIC_HIT - 0.02) * RATE): int((MUSIC_HIT + 3.6) * RATE)]
    music_env = envelope([(0, 0.0), (MUSIC_OFFSET, 0.0), (MUSIC_OFFSET + 1.5, 0.35), (7.3, 0.45), (HIT - 0.05, 0.75),
                          (HIT, 1.0), (TITLE_AT - 0.25, 1.0), (TITLE_AT, 0.0), (LENGTH, 0.0)], n)
    music *= music_env
    place(music, hit_clip, TITLE_AT, 1.0, fade=0.004)
    tail = np.ones((n, 1), np.float32)
    end_fade = int((LENGTH - 1.2) * RATE)
    tail[end_fade:] = np.linspace(1, 0, n - end_fade)[:, None]
    music *= tail
    # A voz abaixa a música e o som do jogo; o som do jogo some sob o cartão final.
    voice_level = np.convolve(np.abs(voice).max(1), np.ones(4800) / 4800, "same")[:, None]
    duck = 1.0 - np.clip(voice_level * 25, 0, 0.55)
    world_env = envelope([(0, 1), (TITLE_AT - 0.1, 1), (TITLE_AT + 0.3, 0), (LENGTH, 0)], n)
    out = music * 0.55 * duck + world * world_env * duck + voice * 1.25
    peak = np.max(np.abs(out))
    out *= 0.89 / max(peak, 1e-6)
    path = os.path.join(OUT, "mix.wav")
    sf.write(path, out, RATE)
    return path


if __name__ == "__main__":
    preview = "--preview" in sys.argv
    for arg in sys.argv[1:]:
        if arg.startswith("--until="):  # prévia parcial: só os primeiros N segundos
            LENGTH = float(arg.split("=")[1])
    os.makedirs(OUT, exist_ok=True)
    audio = mix_audio()
    video = compose(preview)
    final = os.path.join(OUT, "HARBOR-trailer-30s.mp4" if not preview else "preview.mp4")
    run(["-i", video, "-i", audio, "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", final])
    print("PRONTO", final)
