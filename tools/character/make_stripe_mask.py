"""Makes the stripe mask for a garment mesh (the long-sleeve top or the hat).

The stripes are computed from the 3D position of each texel (not from the UV layout), so they
run around the body and around the sleeves without a break at the UV seams.

The mode `cane` is for the cane: the bands are on the shaft only, and the mask has one more layer
for the shaft colour (the grip and the tip keep the first layer of the material).

usage: make_stripe_mask.py <mesh.glb> <out_dir> <mask_name> [size] [top|hat|cane] [band width in metres]
                           [half of the shoulder width in metres]
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF"
    off = 12
    js = None
    bin_chunk = None
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8 : off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(chunk)
        elif ctype.startswith(b"BIN"):
            bin_chunk = chunk
        off += 8 + clen
    return js, bin_chunk


COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NUM = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(js, bin_chunk, index):
    a = js["accessors"][index]
    bv = js["bufferViews"][a["bufferView"]]
    dtype = np.dtype(COMP[a["componentType"]])
    n = NUM[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    if stride and stride != dtype.itemsize * n:
        rows = [np.frombuffer(bin_chunk, dtype=dtype, count=n, offset=start + i * stride) for i in range(a["count"])]
        arr = np.array(rows)
    else:
        arr = np.frombuffer(bin_chunk, dtype=dtype, count=a["count"] * n, offset=start).reshape(a["count"], n)
    arr = arr.astype(np.float64)
    if a.get("normalized"):
        arr = arr / np.iinfo(dtype).max
    return arr


def load_lod0(js, bin_chunk):
    """Returns positions, uvs and triangles of all LOD 0 submeshes."""
    tris_p, tris_uv = [], []
    names = []
    for mesh in js["meshes"]:
        name = mesh.get("name", "")
        names.append(name)
        if "LOD_1" not in name and "LOD" in name:
            continue
        for prim in mesh["primitives"]:
            pos = accessor(js, bin_chunk, prim["attributes"]["POSITION"])
            uv = accessor(js, bin_chunk, prim["attributes"]["TEXCOORD_0"])
            idx = accessor(js, bin_chunk, prim["indices"]).astype(np.int64).reshape(-1, 3)
            tris_p.append(pos[idx])
            tris_uv.append(uv[idx])
    return np.concatenate(tris_p), np.concatenate(tris_uv), names


# Stripe widths in metres along the body: black, gap, black, gap ... The sequence repeats.
# Bands of the same width (user decision: the first, uneven barcode pattern did not read as stripes).
PATTERN = [0.038, 0.038]
# Cane: length of the grip part at the top and of the metal tip at the bottom, in metres.
CANE_GRIP = 0.06
CANE_TIP = 0.037


def stripe_value(t):
    """t: distance in metres from the top. Returns 1.0 where a colour stripe is."""
    period = sum(PATTERN)
    edges = np.cumsum(PATTERN)
    r = np.mod(t, period)
    k = np.searchsorted(edges, r, side="right")
    return (k % 2 == 0).astype(np.float64)


def main():
    glb, out_dir, mask_name = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    size = int(sys.argv[4]) if len(sys.argv) > 4 else 1024
    mode = sys.argv[5] if len(sys.argv) > 5 else "top"
    band = float(sys.argv[6]) if len(sys.argv) > 6 else 0.038
    PATTERN[:] = [band, band]
    js, bin_chunk = load_glb(glb)
    P, UV, names = load_lod0(js, bin_chunk)
    allp = P.reshape(-1, 3)
    lo, hi = allp.min(0), allp.max(0)
    print("meshes:", names)
    print("triangles:", len(P), "bounds min", np.round(lo, 3), "max", np.round(hi, 3))
    print("uv min", np.round(UV.reshape(-1, 2).min(0), 3), "max", np.round(UV.reshape(-1, 2).max(0), 3))

    # Axes: the up axis has the range of a torso (about 0.6 to 0.8 m) and its minimum is far from 0;
    # the arm axis has the largest range. glTF is Y up.
    up = 1
    side = int(np.argmax(hi - lo))
    if side == up:
        side = 0
    print("up axis", up, "side axis", side, "extent", np.round(hi - lo, 3))

    # Shoulder: the body is narrower than this, the arms are outside it.
    centre = (lo[side] + hi[side]) / 2.0
    shoulder_x = float(sys.argv[7]) if len(sys.argv) > 7 else 0.19
    top = hi[up]
    shoulder_y = top - 0.10

    def param(p):
        x = np.abs(p[..., side] - centre)
        y = p[..., up]
        if mode in ("hat", "cane"):
            # A hat and a cane have no arms: the stripes go around them by height only.
            return y
        body = y
        d = np.sqrt(np.maximum(x - shoulder_x, 0.0) ** 2 + (np.minimum(y - shoulder_y, 0.0)) ** 2)
        arm = shoulder_y - d
        return np.where(x > shoulder_x, np.minimum(arm, y), body)

    img_t = np.full((size, size), np.nan)
    for tri_p, tri_uv in zip(P, UV):
        uv = tri_uv * size
        x0, y0 = np.floor(uv.min(0)).astype(int) - 1
        x1, y1 = np.ceil(uv.max(0)).astype(int) + 1
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = uv
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        w2 = 1.0 - w0 - w1
        eps = -0.6 / max(1.0, np.sqrt(abs(den)))  # a small margin past the edges, against seams
        inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
        if not inside.any():
            continue
        pos = w0[..., None] * tri_p[0] + w1[..., None] * tri_p[1] + w2[..., None] * tri_p[2]
        t = param(pos)
        sub = img_t[y0 : y1 + 1, x0 : x1 + 1]
        strict = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        write = inside & (np.isnan(sub) | strict)
        sub[write] = t[write]

    covered = ~np.isnan(img_t)
    print("covered texels: %.1f %%" % (100.0 * covered.mean()))
    stripes = np.zeros((size, size))
    stripes[covered] = stripe_value(top - img_t[covered])
    # Layer 1 and layer 2 of the mask. Clothing: the stripes, and nothing. Cane: the shaft
    # (between the grip and the metal tip), and the bands on the shaft.
    if mode == "cane":
        shaft = np.zeros((size, size))
        depth = top - img_t[covered]
        shaft[covered] = ((depth > CANE_GRIP) & (depth < hi[up] - lo[up] - CANE_TIP)).astype(np.float64)
        layer_1, layer_2 = shaft, shaft * stripes
        stripes = shaft * (1.0 - stripes)
    else:
        layer_1, layer_2 = stripes, np.zeros((size, size))

    out_dir.mkdir(parents=True, exist_ok=True)
    layers = out_dir / (mask_name + "_layers")
    layers.mkdir(exist_ok=True)
    white = Image.fromarray(np.full((size, size), 255, np.uint8), "L").convert("RGBA")
    images = [white] + [Image.fromarray((layer * 255).astype(np.uint8), "L").convert("RGBA") for layer in (layer_1, layer_2)]
    lines = []
    for i in range(3):
        name = f"{mask_name}_{i}.png"
        images[i].save(layers / name)
        lines.append(f"{mask_name}_layers/{name}")
    (out_dir / (mask_name + ".masklist")).write_text("\n".join(lines) + "\n")

    # Debug picture: the stripes on the UV layout, grey where no triangle is.
    dbg = np.full((size, size, 3), 90, np.uint8)
    dbg[covered] = np.where(stripes[covered][:, None] > 0.5, [20, 20, 20], [235, 232, 220])
    Image.fromarray(dbg, "RGB").resize((768, 768)).save(out_dir / "debug_uv.png")

    # Debug picture: front view of the mesh with the stripes (orthographic, no shading).
    w, h = 700, 520
    front = np.full((h, w, 3), 90, np.uint8)
    depth_axis = 3 - up - side
    cen = P.mean(1)
    order = np.argsort(cen[:, depth_axis])
    sx = (w - 40) / (hi[side] - lo[side])
    sy = (h - 40) / (hi[up] - lo[up])
    s = min(sx, sy)
    for i in order:
        t = param(cen[i])
        col = (20, 20, 20) if stripe_value(np.array([top - t]))[0] > 0.5 else (235, 232, 220)
        px = ((P[i][:, side] - lo[side]) * s + 20).astype(int)
        py = (h - 20 - (P[i][:, up] - lo[up]) * s).astype(int)
        x0, x1 = max(px.min(), 0), min(px.max(), w - 1)
        y0, y1 = max(py.min(), 0), min(py.max(), h - 1)
        front[y0 : y1 + 1, x0 : x1 + 1] = col
    Image.fromarray(front, "RGB").save(out_dir / "debug_front.png")


if __name__ == "__main__":
    main()
