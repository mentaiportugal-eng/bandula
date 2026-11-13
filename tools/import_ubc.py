#!/usr/bin/env python3
"""Importa o pack «Universal Base Characters [Standard]» (Quaternius, CC0) para o Bandula.

    python3 -I godot/bandula/tools/import_ubc.py "<caminho>/Universal Base Characters[Standard].zip"

Copia os corpos (feminino/masculino), olhos, sobrancelhas e penteados em glTF para
assets/characters/ubc/, sem mapas normal/rugosidade (o toon shader não os usa) e com
texturas reduzidas para a exportação web. Depois: tools/build_characters.gd.
"""
import io
import json
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = "Universal Base Characters[Standard]/"
BODY_DIR = ROOT + "Base Characters/Godot - UE/"
HAIR_DIR = ROOT + "Hairstyles/Origin at 0/glTF (Godot)/"
OUT = Path(__file__).resolve().parent.parent / "assets" / "characters" / "ubc"
BODIES = ["Superhero_Female_FullBody", "Superhero_Male_FullBody"]
HAIRS = ["Hair_Beard", "Hair_Buns", "Hair_Buzzed", "Hair_BuzzedFemale", "Hair_Long", "Hair_SimpleParted"]
TEX_SIZE = {"T_Superhero": 1024, "T_Hair": 512, "T_Eye": 256}


def tex_size(name: str) -> int:
    for k, v in TEX_SIZE.items():
        if name.startswith(k):
            return v
    return 512


def strip_gltf(data: dict) -> tuple[dict, list[str]]:
    """Remove normal/rugosidade/oclusão e devolve as imagens de cor que restam."""
    used = set()
    for m in data.get("materials", []):
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
        pbr = m.setdefault("pbrMetallicRoughness", {})
        pbr.pop("metallicRoughnessTexture", None)
        if "baseColorTexture" in pbr:
            used.add(pbr["baseColorTexture"]["index"])
    textures = data.get("textures", [])
    keep_tex = sorted(used)
    remap_tex = {old: new for new, old in enumerate(keep_tex)}
    keep_img = sorted({textures[t]["source"] for t in keep_tex})
    remap_img = {old: new for new, old in enumerate(keep_img)}
    data["textures"] = [dict(textures[t], source=remap_img[textures[t]["source"]]) for t in keep_tex]
    data["images"] = [data["images"][i] for i in keep_img]
    for m in data.get("materials", []):
        pbr = m["pbrMetallicRoughness"]
        if "baseColorTexture" in pbr:
            pbr["baseColorTexture"]["index"] = remap_tex[pbr["baseColorTexture"]["index"]]
    if not data["textures"]:
        data.pop("textures")
        data.pop("images")
        data.pop("samplers", None)
    return data, [img["uri"] for img in data.get("images", [])]


def save_png(z: zipfile.ZipFile, member: str, dest: Path) -> None:
    im = Image.open(io.BytesIO(z.read(member))).convert("RGBA")
    s = tex_size(dest.name)
    if im.width > s:
        im = im.resize((s, s), Image.LANCZOS)
    im.save(dest, optimize=True)


def find_png(z: zipfile.ZipFile, folder: str, uri: str) -> str:
    """O glTF às vezes aponta para «X_png.png»; procura a versão existente."""
    names = set(z.namelist())
    for cand in (folder + uri, folder + uri.replace("_png.png", ".png"), ROOT + "Base Characters/Textures/" + uri):
        if cand in names:
            return cand
    raise FileNotFoundError(uri)


def main(zip_path: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        jobs = [(BODY_DIR, b, b) for b in BODIES] + [(HAIR_DIR, h, h) for h in HAIRS]
        for folder, src, dst in jobs:
            data, images = strip_gltf(json.loads(z.read(folder + src + ".gltf")))
            for img in data.get("images", []):
                clean = img["uri"].replace("_png.png", ".png")
                save_png(z, find_png(z, folder, img["uri"]), OUT / clean)
                img["uri"] = clean
            for buf in data["buffers"]:
                (OUT / buf["uri"]).write_bytes(z.read(folder + buf["uri"]))
            (OUT / (dst + ".gltf")).write_text(json.dumps(data, indent=1))
            print("ok", dst, images)
    print("→", OUT)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[3] / "Universal Base Characters[Standard].zip"))
