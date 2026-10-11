#!/usr/bin/env python3
"""Importa um pacote ZIP baixado do Meshy (personagem rigado, esqueleto Mixamo) para um GLB leve do jogo.

Lê só o GLB `*_Walking_withSkin.glb` de dentro do ZIP (sem extrair o resto nem confiar em caminhos do
arquivo), poda os ossos que o jogo não anima e reduz a textura (`tools/meshy_slim_glb.py`).

Uso: python tools/meshy_import_zip.py <pacote.zip> <saida.glb> [--size 1024]
"""
import argparse, os, sys, tempfile, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_slim_glb, meshy_curl_hands


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("zip_path")
    parser.add_argument("out_path")
    parser.add_argument("--size", type=int, default=1024)
    args = parser.parse_args()
    with zipfile.ZipFile(args.zip_path) as pack:
        members = [n for n in pack.namelist() if n.endswith("_Walking_withSkin.glb")]
        if len(members) != 1:
            raise SystemExit("esperava um GLB Walking_withSkin, achei %d: %s" % (len(members), pack.namelist()))
        data = pack.read(members[0])
    with tempfile.TemporaryDirectory() as folder:
        raw = os.path.join(folder, "raw.glb")
        with open(raw, "wb") as handle: handle.write(data)
        os.makedirs(os.path.dirname(os.path.abspath(args.out_path)), exist_ok=True)
        meshy_slim_glb.slim(raw, args.out_path, args.size, 88, True)
    # Mão relaxada em vez de dedos esticados (ver meshy_curl_hands.py).
    doc, blob = meshy_slim_glb.read_glb(args.out_path)
    blob = meshy_curl_hands.curl(doc, blob, 55.0, (0.0, 0.0, 1.0))
    blob = meshy_slim_glb.collect_garbage(doc, blob)
    meshy_slim_glb.write_glb(args.out_path, doc, blob)
    print("ok", args.out_path, os.path.getsize(args.out_path), "bytes")


if __name__ == "__main__":
    main()
