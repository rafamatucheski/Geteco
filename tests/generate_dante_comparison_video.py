import os
import glob
from PIL import Image

def main():
    frames_dir = os.path.join(os.path.dirname(__file__), "temp_dante_frames")
    frame_files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    
    if not frame_files:
        print(f"ERROR: No frame files found in {frames_dir}")
        return

    print(f"Found {len(frame_files)} frames. Processing animation...")

    images = []
    for f in frame_files:
        im = Image.open(f)
        # Redimensiona ligeiramente para economizar memória mantendo nitidez HD (854x480)
        im_resized = im.resize((960, 540), Image.Resampling.LANCZOS)
        images.append(im_resized)

    out_webp = os.path.join(os.path.dirname(__file__), "dante_animation_comparison.webp")
    out_gif = os.path.join(os.path.dirname(__file__), "dante_animation_comparison.gif")
    
    artifact_dir = "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"

    # Salva WEBP animado (alta qualidade, tamanho compacto, 30fps = 33ms por frame)
    images[0].save(
        out_webp,
        format="WEBP",
        save_all=True,
        append_images=images[1:],
        duration=33,
        loop=0,
        quality=85
    )
    print(f"SAVED: {out_webp}")

    # Salva também versão GIF
    images_quantized = [img.quantize(colors=128) for img in images]
    images_quantized[0].save(
        out_gif,
        save_all=True,
        append_images=images_quantized[1:],
        duration=33,
        loop=0
    )
    print(f"SAVED: {out_gif}")

    # Copia para os artefatos
    if os.path.exists(artifact_dir):
        import shutil
        shutil.copyfile(out_webp, os.path.join(artifact_dir, "dante_animation_comparison.webp"))
        shutil.copyfile(out_gif, os.path.join(artifact_dir, "dante_animation_comparison.gif"))
        print(f"COPIED to artifact dir: {artifact_dir}")

    # Limpeza dos frames temporários
    for f in frame_files:
        try:
            os.remove(f)
        except Exception:
            pass
    try:
        os.rmdir(frames_dir)
    except Exception:
        pass
    print("Animation compilation complete!")

if __name__ == "__main__":
    main()
