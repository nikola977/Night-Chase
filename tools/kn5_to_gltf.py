"""Assetto-Corsa .kn5 -> gekachelte glTF-Dateien (.glb) fuer Godot.

Warum dieses Skript?
    Godot kann .kn5 nicht lesen. Die vorhandenen Konverter schreiben ein einziges
    riesiges OBJ (hier 1,4 GB / 3,9 Mio. Dreiecke) - das laedt Godot nicht in
    vertretbarer Zeit. Dieses Skript liest die .kn5 direkt und schreibt pro
    Bodenkachel eine eigene .glb-Datei. Dadurch kann Godot Kacheln einzeln
    ausblenden (Sichtweite) und wir behalten die Kontrolle ueber Materialien.

Texturen:
    Echte Texturen aus der .kn5 werden als PNG in die .glb eingebettet (mit UVs),
    inklusive Leucht-Textur (emissive). Fehlt eine Textur (in dieser Strecke sind
    fast alle nur 70-Byte-Platzhalter), bleibt das Material einfarbig - Godot
    erzeugt dann selbst eine Koernung (siehe scripts/track_world.gd).

Aufruf (Beispiele):
    python tools/kn5_to_gltf.py --in TRACK/90sgdsp_osaka_nanko.kn5 --out assets/tracks/osaka --tile=250
    python tools/kn5_to_gltf.py --in TRACK/physical_free.kn5 --out assets/tracks/osaka --collision

Voraussetzungen: Python 3 mit numpy und pillow (pip install numpy pillow).
"""

import argparse
import io
import json
import os
import struct

import numpy as np
from PIL import Image


# ---------------------------------------------------------------- kn5 lesen

class Material:
    def __init__(self):
        self.name = ""
        self.shader = ""
        self.tx_diffuse = ""
        self.tx_normal = ""
        self.alpha_ref = 1.0
        self.emissive = 0.0


class MeshNode:
    def __init__(self):
        self.name = ""
        self.type = 0
        self.matrix = np.identity(4, dtype=np.float64)
        self.positions = None   # (n, 3) float32
        self.normals = None     # (n, 3) float32
        self.uvs = None         # (n, 2) float32
        self.indices = None     # (m,) uint32
        self.material_id = -1


def _read_string(data, pos):
    length = struct.unpack_from("<i", data, pos)[0]
    pos += 4
    return data[pos:pos + length].decode("utf-8", "replace"), pos + length


def _strided(data, offset, count, per_vertex, columns, first):
    """Liest count Zahlenreihen aus einem Vertex-Block fester Groesse."""
    view = np.frombuffer(
        data, dtype="<f4", count=count * (per_vertex // 4),
        offset=offset).reshape(count, per_vertex // 4)
    return np.array(view[:, first:first + columns], dtype=np.float32)


def read_kn5(path):
    """Liest Texturen, Materialien und alle Mesh-Knoten (mit Weltmatrix)."""
    with open(path, "rb") as file:
        data = file.read()
    if data[:6] not in (b"sc6969", b"sc5876"):
        raise SystemExit("Keine .kn5-Datei: %s" % path)
    version = struct.unpack_from("<I", data, 6)[0]
    pos = 10
    if version > 5:
        pos += 4

    texture_count = struct.unpack_from("<i", data, pos)[0]
    pos += 4
    textures = {}
    for _ in range(texture_count):
        _tex_type = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        name, pos = _read_string(data, pos)
        size = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        textures[name] = data[pos:pos + size]
        pos += size

    material_count = struct.unpack_from("<i", data, pos)[0]
    pos += 4
    materials = []
    for _ in range(material_count):
        material = Material()
        material.name, pos = _read_string(data, pos)
        material.shader, pos = _read_string(data, pos)
        pos += 2                                  # kurze Kennung
        if version > 4:
            pos += 4
        prop_count = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        for _ in range(prop_count):
            prop_name, pos = _read_string(data, pos)
            value = struct.unpack_from("<f", data, pos)[0]
            pos += 4 + 36
            if prop_name == "ksAlphaRef":
                material.alpha_ref = value
            elif prop_name == "ksEmissive":
                material.emissive = value
        sample_count = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        for _ in range(sample_count):
            sample, pos = _read_string(data, pos)
            pos += 4
            tex_name, pos = _read_string(data, pos)
            if sample == "txDiffuse":
                material.tx_diffuse = tex_name
            elif sample == "txNormal":
                material.tx_normal = tex_name
        materials.append(material)

    nodes = []

    def read_node(parent_matrix):
        nonlocal pos
        node = MeshNode()
        node.type = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        node.name, pos = _read_string(data, pos)
        children = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        pos += 1                                  # aktiv-Flag
        if node.type == 1:                        # leerer Knoten
            local = np.array(
                struct.unpack_from("<16f", data, pos), dtype=np.float64).reshape(4, 4)
            pos += 64
            node.matrix = local @ parent_matrix
        elif node.type in (2, 3):                 # Mesh / animiertes Mesh
            pos += 3
            if node.type == 3:
                bone_count = struct.unpack_from("<i", data, pos)[0]
                pos += 4
                for _ in range(bone_count):
                    _bone, pos = _read_string(data, pos)
                    pos += 64
            vertex_count = struct.unpack_from("<i", data, pos)[0]
            pos += 4
            # 44 Bytes je Vertex (Position, Normale, UV, Tangente), bei
            # animierten Meshes zusaetzlich 32 Bytes Knochen-Daten.
            per_vertex = 44 if node.type == 2 else 76
            node.positions = _strided(data, pos, vertex_count, per_vertex, 3, 0)
            node.normals = _strided(data, pos, vertex_count, per_vertex, 3, 3)
            node.uvs = _strided(data, pos, vertex_count, per_vertex, 2, 6)
            node.uvs[:, 1] = 1.0 - node.uvs[:, 1]
            pos += vertex_count * per_vertex
            index_count = struct.unpack_from("<i", data, pos)[0]
            pos += 4
            node.indices = np.frombuffer(
                data, dtype="<u2", count=index_count, offset=pos).astype(np.uint32)
            pos += index_count * 2
            node.material_id = struct.unpack_from("<i", data, pos)[0]
            pos += 4 + 29                          # 29 Bytes sind unbekannt
            if node.type == 3:
                pos += 12
            node.matrix = parent_matrix
        else:
            raise SystemExit("Unbekannter Knotentyp %d" % node.type)

        nodes.append(node)
        for _ in range(children):
            read_node(node.matrix)

    read_node(np.identity(4, dtype=np.float64))
    return textures, materials, nodes


def world_vertices(node):
    """Wendet die Knotenmatrix an (Assetto Corsa speichert Zeilen-Vektoren)."""
    matrix = node.matrix
    rotation = matrix[:3, :3].T
    positions = node.positions @ rotation + matrix[3, :3]
    normals = node.normals @ rotation
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    lengths[lengths == 0] = 1.0
    return positions.astype(np.float32), (normals / lengths).astype(np.float32)


# --------------------------------------------------- Materialien aus Namen

# (Schluesselwoerter, Farbe, Rauheit, Metall, durchsichtig)
_STYLES = [
    (("asphalt", "road", "tarmac"), (0.30, 0.30, 0.31), 0.85, 0.0, False),
    (("markings", "line"), (0.85, 0.84, 0.80), 0.60, 0.0, False),
    (("kerb", "curb"), (0.70, 0.68, 0.62), 0.75, 0.0, False),
    (("grass", "dirt", "gravel", "sand", "soil"), (0.32, 0.36, 0.24), 0.95, 0.0, False),
    (("glass", "window", "windscreen"), (0.55, 0.62, 0.68), 0.10, 0.0, True),
    (("chrome", "mirror", "metal_pole", "pole", "steel", "metal"), (0.55, 0.56, 0.58), 0.35, 0.9, False),
    (("container",), (0.45, 0.42, 0.38), 0.70, 0.3, False),
    (("brick", "brickwall"), (0.48, 0.36, 0.30), 0.90, 0.0, False),
    (("concrete", "wall", "pillar", "stand", "silo", "bareconcrete"), (0.36, 0.35, 0.34), 0.85, 0.0, False),
    (("rust",), (0.40, 0.30, 0.24), 0.85, 0.2, False),
    (("sign", "trafficlight", "lamp", "light", "emissive", "tube"), (0.80, 0.80, 0.78), 0.50, 0.0, False),
    (("scrap", "bag", "crate", "wood", "carpet", "tarp"), (0.44, 0.40, 0.34), 0.90, 0.0, False),
    (("tree", "leaf", "leaves", "bush", "plant"), (0.28, 0.34, 0.20), 0.90, 0.0, False),
]

## Materialien, die ohne ihre Textur sinnlos sind: Baeume, Buesche und Gras sind in
## Assetto Corsa flache Karten, die nur mit Alphakanal wie Pflanzen aussehen.
_NEEDS_TEXTURE = ("tree", "pltree", "bush", "ivy", "grass", "leaf", "leaves", "flag")


def should_skip(material):
    name = (material.name + " " + material.tx_diffuse).lower()
    if material.shader in ("ksTree", "ksGrass", "ksFlags"):
        return True
    return any(keyword in name for keyword in _NEEDS_TEXTURE)


def _material_style(material):
    name = (material.name + " " + material.tx_diffuse + " " + material.shader).lower()
    for keywords, color, roughness, metallic, transparent in _STYLES:
        if any(keyword in name for keyword in keywords):
            return _vary(material.name, color), roughness, metallic, transparent
    if material.shader.lower().startswith(("ksperpixelat", "ksperpixelalpha")) \
            or material.shader == "ksSkidMark":
        return (0.55, 0.55, 0.55), 0.5, 0.0, True
    return _vary(material.name, (0.50, 0.50, 0.52)), 0.80, 0.0, False


def _vary(name, color):
    """Kleine Helligkeits-/Farbstreuung je Materialname, damit nicht alle
    Flaechen exakt gleich aussehen (ohne Texturen sieht sonst alles wie eine
    einzige graue Flaeche aus)."""
    seed = 0
    for character in name:
        seed = (seed * 131 + ord(character)) & 0xFFFF
    brightness = 0.86 + (seed % 29) / 100.0
    warm = ((seed >> 5) % 9 - 4) / 100.0
    return (min(1.0, color[0] * brightness + warm),
            color[1] * brightness,
            min(1.0, color[2] * brightness - warm))


def texture_png(blob, name):
    """Echte .dds/.png-Textur aus der .kn5 in PNG wandeln.

    Platzhalter dieser Strecke sind 70 Byte kleine 1x1-PNGs - die sind nutzlos
    und werden deshalb verworfen."""
    if not blob or len(blob) < 2048:
        return None
    try:
        image = Image.open(io.BytesIO(blob))
        image = image.convert("RGBA")
        if image.size[0] < 8 or image.size[1] < 8:
            return None
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        return buffer.getvalue()
    except Exception:
        return None


# --------------------------------------------------------------- glb schreiben

def _pad(buffer, alignment=4):
    while len(buffer) % alignment:
        buffer.append(0)


class GlbBuilder:
    def __init__(self):
        self.blob = bytearray()
        self.materials = []
        self.primitives = []
        self.images = []      # (name, png bytes)
        self.textures = []    # Bildindex je Textur

    def add_image(self, name, png):
        self.images.append((name, png))
        self.textures.append(len(self.images) - 1)
        return len(self.textures) - 1

    def add_primitive(self, positions, normals, uvs, indices, material_index):
        if len(indices) == 0:
            return
        # Vertices zusammenfassen: gleiche Position + Normale + UV = ein Vertex
        packed = np.concatenate([positions, normals, uvs], axis=1)
        unique, inverse = np.unique(np.round(packed, 4), axis=0, return_inverse=True)
        remapped = inverse.astype(np.uint32)[indices]
        unique_positions = unique[:, :3].astype(np.float32)
        unique_normals = unique[:, 3:6].astype(np.float32)
        unique_uvs = unique[:, 6:8].astype(np.float32)

        parts = {}
        for key, array in (("position", unique_positions), ("normal", unique_normals),
                           ("uv", unique_uvs), ("index", remapped)):
            offset = len(self.blob)
            self.blob += array.tobytes()
            _pad(self.blob)
            parts[key] = (offset, len(array))
        self.primitives.append({
            "parts": parts,
            "material": material_index,
            "min": unique_positions.min(axis=0).tolist(),
            "max": unique_positions.max(axis=0).tolist(),
        })

    def add_material(self, name, color, roughness, metallic, transparent,
                     diffuse_texture=-1, emissive=False):
        pbr = {
            "metallicFactor": metallic,
            "roughnessFactor": roughness,
        }
        if diffuse_texture >= 0:
            # Textur bestimmt die Farbe, kein Toenen
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
            pbr["baseColorTexture"] = {"index": diffuse_texture}
        else:
            pbr["baseColorFactor"] = [color[0], color[1], color[2], 1.0]
        material = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": True}
        if diffuse_texture >= 0 and emissive:
            material["emissiveTexture"] = {"index": diffuse_texture}
            material["emissiveFactor"] = [1.0, 1.0, 1.0]
        if transparent:
            material["alphaMode"] = "BLEND"
            material["pbrMetallicRoughness"]["baseColorFactor"][3] = 0.45
        self.materials.append(material)
        return len(self.materials) - 1

    def save(self, path):
        accessors = []
        views = []
        primitives_json = []

        def add_view(offset, length, target=None):
            view = {"buffer": 0, "byteOffset": offset, "byteLength": length}
            if target is not None:
                view["target"] = target
            views.append(view)
            return len(views) - 1

        for primitive in self.primitives:
            parts = primitive["parts"]
            index_accessor = len(accessors)
            accessors.append({"bufferView": add_view(parts["index"][0], parts["index"][1] * 4, 34963),
                              "componentType": 5125, "count": parts["index"][1], "type": "SCALAR"})
            position_accessor = len(accessors)
            accessors.append({"bufferView": add_view(parts["position"][0], parts["position"][1] * 12, 34962),
                              "componentType": 5126, "count": parts["position"][1], "type": "VEC3",
                              "min": primitive["min"], "max": primitive["max"]})
            normal_accessor = len(accessors)
            accessors.append({"bufferView": add_view(parts["normal"][0], parts["normal"][1] * 12, 34962),
                              "componentType": 5126, "count": parts["normal"][1], "type": "VEC3"})
            uv_accessor = len(accessors)
            accessors.append({"bufferView": add_view(parts["uv"][0], parts["uv"][1] * 8, 34962),
                              "componentType": 5126, "count": parts["uv"][1], "type": "VEC2"})
            primitives_json.append({
                "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor,
                               "TEXCOORD_0": uv_accessor},
                "indices": index_accessor,
                "material": primitive["material"],
                "mode": 4,
            })

        images_json = []
        for name, png in self.images:
            offset = len(self.blob)
            self.blob += png
            _pad(self.blob)
            images_json.append({"bufferView": add_view(offset, len(png)), "mimeType": "image/png",
                                "name": name})

        _pad(self.blob)
        gltf = {
            "asset": {"version": "2.0", "generator": "kn5_to_gltf.py"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0, "name": os.path.splitext(os.path.basename(path))[0]}],
            "meshes": [{"primitives": primitives_json}],
            "materials": self.materials,
            "accessors": accessors,
            "bufferViews": views,
            "buffers": [{"byteLength": len(self.blob)}],
        }
        if images_json:
            gltf["images"] = images_json
            gltf["textures"] = [{"source": source, "sampler": 0} for source in self.textures]
            gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987,
                                 "wrapS": 10497, "wrapT": 10497}]
        json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        while len(json_chunk) % 4:
            json_chunk += b" "
        with open(path, "wb") as file:
            file.write(b"glTF")
            file.write(struct.pack("<II", 2, 12 + 8 + len(json_chunk) + 8 + len(self.blob)))
            file.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
            file.write(json_chunk)
            file.write(struct.pack("<II", len(self.blob), 0x004E4942))
            file.write(self.blob)


# ------------------------------------------------------------------ Ablauf

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="source", required=True, help=".kn5-Datei")
    parser.add_argument("--out", dest="target", required=True, help="Zielordner")
    parser.add_argument("--tile", type=float, default=250.0,
                        help="Kachelgroesse in Metern (0 = eine Datei)")
    parser.add_argument("--collision", action="store_true",
                        help="Alles in eine Datei, nur fuer die Fahrbahn-Physik")
    args = parser.parse_args()

    textures, materials, nodes = read_kn5(args.source)
    model = os.path.splitext(os.path.basename(args.source))[0]
    print("%d Materialien, %d Knoten, %d Texturen" % (len(materials), len(nodes), len(textures)))

    tiles = {}
    total_triangles = 0
    texture_count = 0
    low = np.array([1e9, 1e9, 1e9])
    high = np.array([-1e9, -1e9, -1e9])
    for node in nodes:
        if node.type not in (2, 3) or node.positions is None or len(node.indices) == 0:
            continue
        positions, normals = world_vertices(node)
        low = np.minimum(low, positions.min(axis=0))
        high = np.maximum(high, positions.max(axis=0))
        total_triangles += len(node.indices) // 3
        material_index = node.material_id if 0 <= node.material_id < len(materials) else -1
        if 0 <= material_index < len(materials) and should_skip(materials[material_index]):
            continue
        if args.collision or args.tile <= 0:
            key = (0, 0)
        else:
            center = positions.mean(axis=0)
            key = (int(np.floor(center[0] / args.tile)), int(np.floor(center[2] / args.tile)))
        tiles.setdefault(key, []).append(
            (material_index, positions, normals, node.uvs, node.indices))
    print("%.2f Mio. Dreiecke in %d Kacheln" % (total_triangles / 1e6, len(tiles)))

    os.makedirs(args.target, exist_ok=True)
    manifest_tiles = []
    bounds = {"min": low.tolist(), "max": high.tolist()}
    print("Ausdehnung x %.0f..%.0f  y %.0f..%.0f  z %.0f..%.0f" % (
        low[0], high[0], low[1], high[1], low[2], high[2]))

    for key in sorted(tiles):
        builder = GlbBuilder()
        material_ids = {}
        for material_index, positions, normals, uvs, indices in tiles[key]:
            if material_index not in material_ids:
                if args.collision or material_index < 0:
                    material_ids[material_index] = builder.add_material(
                        "collision", (0.5, 0.5, 0.5), 0.8, 0.0, False)
                else:
                    material = materials[material_index]
                    color, roughness, metallic, transparent = _material_style(material)
                    texture_index = -1
                    png = texture_png(textures.get(material.tx_diffuse, b""), material.tx_diffuse)
                    if png is not None:
                        texture_index = builder.add_image(material.name, png)
                        texture_count += 1
                    emissive = "emissive" in material.name.lower() or material.emissive > 0.0
                    material_ids[material_index] = builder.add_material(
                        material.name, color, roughness, metallic, transparent,
                        texture_index, emissive)
            builder.add_primitive(positions, normals, uvs, indices,
                                  material_ids[material_index])

        if args.collision or args.tile <= 0:
            name = "collision"
        else:
            # Jede Quelle bekommt eigene Namen, damit Strecke, Gebaeude und
            # Requisiten im selben Ordner liegen koennen.
            name = "%s_tile_%d_%d" % (model, key[0], key[1])
        path = os.path.join(args.target, name + ".glb")
        builder.save(path)
        size = os.path.getsize(path)
        manifest_tiles.append({"name": name, "file": os.path.basename(path), "bytes": size,
                               "textures": len(builder.images)})

    manifest = {
        "source": os.path.basename(args.source),
        "tile_size": args.tile,
        "triangles": total_triangles,
        "textures_used": texture_count,
        "bounds": bounds,
        "tiles": manifest_tiles,
    }
    manifest_name = "manifest.json" if args.collision else model + "_manifest.json"
    with open(os.path.join(args.target, manifest_name), "w", encoding="utf-8") as file:
        json.dump(manifest, file, indent=1)
    print("Fertig: %s (%d Dateien, %d echte Texturen)" % (args.target, len(manifest_tiles),
                                                          texture_count))


if __name__ == "__main__":
    main()
