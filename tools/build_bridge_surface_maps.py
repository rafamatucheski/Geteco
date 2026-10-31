"""Assa dados de material derivados da altura; preserva a fotografia de concreto autorada.

Roda offline. Sem geração de textura, processamento de imagem ou loops novos no jogo.
A sujeira de baixa frequência fica fora do normal map, para manchas nunca virarem calombos.
"""
from pathlib import Path
import shutil

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/materials/bridge"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Importação independente: a versão da cidade é limitada a 512px. Preserva a
    # fotografia original byte a byte e mantém 1024px na ponte.
    shutil.copyfile(ROOT / "assets/materials/harbor_paving/concrete.png", OUT / "concrete_albedo.png")
    source = Image.open(ROOT / "assets/materials/harbor_paving/concrete.png").convert("L")
    source = source.resize((512, 512), Image.Resampling.LANCZOS)
    fine = np.asarray(source, dtype=np.float32) / 255.0
    soft = np.asarray(source.filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255.0
    broad = np.asarray(source.filter(ImageFilter.GaussianBlur(7)), dtype=np.float32) / 255.0
    height = (fine-soft)*.6+(soft-broad)*.25
    dx = (np.roll(height, -1, 1)-np.roll(height, 1, 1))*3.0
    dy = (np.roll(height, -1, 0)-np.roll(height, 1, 0))*3.0
    normal = np.stack((-dx, dy, np.ones_like(height)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    Image.fromarray(np.uint8(np.clip(normal*.5+.5, 0, 1)*255)).save(OUT / "concrete_normal.png")
    roughness = np.clip(.88+(broad-.45)*.18+np.abs(fine-soft)*.3, .82, .98)
    Image.fromarray(np.uint8(roughness*255)).save(OUT / "concrete_roughness.png")
    for name, is_normal in (("concrete_albedo.png", False), ("concrete_normal.png", True), ("concrete_roughness.png", False)):
        path = OUT / (name+".import")
        if path.exists():
            continue
        path.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'
                        'compress/mode=2\ncompress/high_quality=true\n'
                        f'compress/normal_map={1 if is_normal else 0}\n'
                        f'mipmaps/generate=true\nprocess/size_limit={1024 if name == "concrete_albedo.png" else 512}\n', encoding="utf-8")
    print("Bridge material data baked: 1024px albedo import and two 512px maps")


if __name__ == "__main__":
    main()
