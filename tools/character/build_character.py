"""Builds the JSON sources of the Stripes character from base-game files.

Input:  JSON files made by `cp77tools convert serialize` from base-game resources.
Output: JSON files for the custom resources, at their depot paths below `out_dir`.
`build.ps1` runs this script and then converts the JSON files to game files.

usage: build_character.py <json_in_dir> <out_dir>
"""
import copy
import json
import sys
from pathlib import Path

import make_cane_icon

# Depot paths of the custom resources.
ROOT = "wendellstripes\\characters\\stripes\\"
ENT = ROOT + "stripes.ent"
APP = ROOT + "stripes.app"
TOP_MESH = ROOT + "garment\\t1_top_stripes.mesh"
HAT_MESH = ROOT + "garment\\h1_hat_stripes.mesh"
SETUP = ROOT + "garment\\textures\\ml_stripes.mlsetup"
TOP_MASK = ROOT + "garment\\textures\\ml_top_stripes.mlmask"
HAT_MASK = ROOT + "garment\\textures\\ml_hat_stripes.mlmask"
LOCALIZATION = "wendellstripes\\localization\\en-us.json"

# Text that the player sees. The key is used in the character record as LocKey#<key>.
TEXTS = {
    # His full name (user decision 2026-11-22). Also the title of the prompt, in Reward.reds.
    "WendellStripes-Name": "Wendell \"Stripes\" Strypovski",
    "WendellStripes-Cane-Name": "Stripes' Cane",
    "WendellStripes-Cane-Desc": "Wendell never needed it to walk. The grip hides a short-range transmitter: the thing that let him work a crowd and be gone before the mark looked up.",
    "WendellStripes-Cane-Ability": "Vanish: a hit has a 10% chance to trigger Reboot Optics on the target.",
}

# Base-game resources.
BASE_APP_APPEARANCE = "king_of_the_stoop_ma_01"
BASE_TANK_MESH = "base\\characters\\garment\\citizen_casual\\torso\\t1_008_tank__low_cut\\t1_008_ma_tank__low_cut.mesh"
BASE_NECKLACE_MESH = "base\\characters\\garment\\citizen_casual\\item\\i1_033_neck__necklace\\i1_033_ma_neck__necklace.mesh"
BASE_BEANIE_MESH = "base\\characters\\garment\\citizen_casual\\head\\h1_003_hat__beanie\\h1_003_ma_hat__beanie.mesh"
BASE_CHEST_TATTOO_MESH = "base\\characters\\common\\base_bodies\\man_average\\tattoos\\tattoo_ma__chest_01.mesh"
BASE_CANE_MESH = "base\\characters\\main_npc\\fingers\\i1_001_ma_slot__fingers_cane.mesh"
BASE_PANTS_MESH = "base\\characters\\garment\\citizen_casual\\legs\\l1_005_pants__tracksuit\\l1_005_ma_pants__tracksuit.mesh"
BASE_SLIM_PANTS_MESH = "base\\characters\\garment\\citizen_casual\\legs\\l1_028_pants__tight\\l1_028_ma_pants__tight.mesh"
BASE_GLASSES_MESH = "base\\characters\\garment\\citizen_casual\\head\\h1_069_specs__round\\h1_069_ma_specs__round.mesh"
FABRIC = "base\\surfaces\\materials\\fabric\\cotton_shirt\\cotton_shirt_clean_02_30.mltemplate"

# Colour names of the fabric template.
# White (0.875, 0.875, 0.875) and black (0.03, 0.03, 0.03). The hat and the top have the same stripes
# (user decisions 2026-11-20; magenta "058279_null" was tried first).
COLOR_BASE = "2898f2_null"
COLOR_STRIPE = "3eaf77_69039f"

# Rotation of the cane in the hand slot, as a quaternion (i, j, k, r): 270 degrees about the
# shaft (mesh Z), then 90 degrees about X (so that the shaft points down from the hand).
# History of the angle about the shaft, from in-game tests: 0 = shaft on the body side of the hand,
# through the leg; 180 = shaft on the outer side, handle across the hand; 270 = user request,
# "handle 90 degrees counter-clockwise" so that the handle lies along the hand.
CANE_ROTATION = (0.5, 0.5, -0.5, 0.5)
# Position of the cane in the hand slot, in metres (x, y, z of the slot). In the mesh the shaft is
# 6 cm from the grip point along the handle, and with CANE_ROTATION the handle lies along the
# slot Z axis with the shaft at z = +0.06. In game the shaft was in front of the fist; -0.05 on Z
# pulls it back below the hand (user request 2026-11-20).
CANE_OFFSET = (0.0, 0.0, -0.05)

# The cane and its weapon files are below this folder.
ITEMS = "wendellstripes\\items\\"
FACTORY = ITEMS + "factory.csv"

# The cane, for Stripes and for the weapon of V. The mesh is the plain cane of the base game (a
# decoration prop: same length and same grip position as the cane of the ripperdoc, but with no
# cables and no tech parts), with a new material: metal grip and tip, black shaft, white bands
# (user decision 2026-11-21). The weapon appearance files are copies of the base cane weapon files
# with this mesh. Their names in the factory table are the `appearanceResourceName` values in items.yaml.
CANE = ITEMS + "cane\\"
CANE_MESH = CANE + "cane.mesh"
CANE_SETUP = CANE + "textures\\ml_cane.mlsetup"
CANE_MASK = CANE + "textures\\ml_cane.mlmask"
BASE_PLAIN_CANE = "base\\environment\\decoration\\unique\\npc_cane\\"
CANE_WEAPON_FILES = [
    # (JSON of the base file, new depot path, name in the factory table)
    ("w_cane_appearances.app.json", CANE + "cane_weapon.app", "wendellstripes_cane"),
    ("w_cane_grip.app.json", CANE + "cane_grip.app", "wendellstripes_cane_grip"),
]
# Layers of the cane material: (template, colour name of the template). Metal, black, white.
PAINT = "base\\surfaces\\materials\\paint\\paint_fine\\paint_fine_clean_matte_01_300.mltemplate"
CANE_LAYERS = [
    ("base\\surfaces\\materials\\metal\\aluminium\\aluminium_bare_01_300.mltemplate", "51f259_null"),
    (PAINT, "86f75b_null"),
    (PAINT, "53e3a1_null"),
]
# The icons of the cane, two parts of one texture. Inventory icon: the game finds the icon of a
# weapon from its appearance name, and the new appearance name has no icon, so the item record
# names this one (`iconPath` in items.yaml, record `UIIcon.WendellStripes_Cane`). HUD icon: the
# record `HUDWeaponIcons.WendellStripes_Cane` (`hudIcon` in items.yaml). The picture is made by
# make_cane_icon.py.
CANE_ICON_ATLAS = CANE + "cane_icon.inkatlas"
CANE_ICON_TEXTURE = CANE + "textures\\cane_icon.xbm"
CANE_ICON_PART = "wendellstripes_cane"
CANE_HUD_PART = "wendellstripes_cane_hud"

APPEARANCE = "stripes"
# His appearance after he gave the cane to V (the names are also in character.yaml and Main.reds).
APPEARANCE_NO_CANE = "stripes_no_cane"
STRIPES_APPEARANCE = "stripes"
STRIPES_MATERIAL = "ml_stripes"


def cname(value):
    return {"$type": "CName", "$storage": "string", "$value": value}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(doc, out_dir, depot_path):
    target = Path(out_dir) / (depot_path.replace("\\", "/") + ".json")
    target.parent.mkdir(parents=True, exist_ok=True)
    doc["Header"]["ArchiveFileName"] = ""
    with open(target, "w", encoding="utf-8") as f:
        json.dump(doc, f)
    print("wrote", target)


def walk(node, visit):
    """Calls visit(dict) for each dict in the tree."""
    if isinstance(node, dict):
        visit(node)
        for v in node.values():
            walk(v, visit)
    elif isinstance(node, list):
        for v in node:
            walk(v, visit)


def renumber_handles(doc):
    """Gives all handles new numbers in file order. A file must have its handles in rising order."""
    owners, refs = [], []
    walk(doc, lambda n: owners.append(n) if "HandleId" in n else None)
    walk(doc, lambda n: refs.append(n) if "HandleRefId" in n else None)
    old_ids = [n["HandleId"] for n in owners]
    if len(set(old_ids)) != len(old_ids):
        raise SystemExit("two handles have the same id")
    mapping = {old: str(i) for i, old in enumerate(old_ids)}
    for node in owners:
        node["HandleId"] = mapping[node["HandleId"]]
    for node in refs:
        node["HandleRefId"] = mapping[node["HandleRefId"]]


def set_appearance(node, name):
    """A mesh component has `meshAppearance`; a visual controller dependency has `appearanceName`."""
    key = "appearanceName" if "appearanceName" in node else "meshAppearance"
    node[key] = cname(name)


def attach_to_slot(node, slot):
    """Binds a component to a slot of the body (`Item_Attachment_Slot`). Meshes without bones need this.

    Only the compiled chunk has the binding object; the `components` list refers to it.
    Returns 1 if the binding was changed.
    """
    binding = node.get("parentTransform")
    if isinstance(binding, dict) and isinstance(binding.get("Data"), dict):
        binding["Data"]["bindName"] = cname("Item_Attachment_Slot")
        binding["Data"]["slotName"] = cname(slot)
        return 1
    return 0


def mesh_info(json_in, name):
    """Geometry hash and number of chunks of a base mesh."""
    root = load(json_in / name)["Data"]["RootChunk"]
    return root["geometryHash"], len(root["appearances"][0]["Data"]["chunkMaterials"])


def depot_value(ref):
    if isinstance(ref, dict) and isinstance(ref.get("DepotPath"), dict):
        return ref["DepotPath"].get("$value")
    return None


def build_mlsetup(json_in, out_dir):
    doc = load(json_in / "ml_t1_004_ma_tshirt__longsleeve_lc_new_stripes.mlsetup.json")
    layers = doc["Data"]["RootChunk"]["layers"]
    for i, layer in enumerate(layers):
        layer["material"]["DepotPath"]["$value"] = FABRIC
        layer["microblend"]["DepotPath"]["$value"] = "base\\surfaces\\microblends\\default.xbm"
        layer["mbTile"] = 1
        layer["microblendContrast"] = 1
        layer["microblendNormalStrength"] = 0
        layer["matTile"] = 8
        layer["colorScale"] = cname(COLOR_BASE if i == 0 else COLOR_STRIPE)
        # Layer 0 is the cloth, layer 1 is the stripes. The masks have 3 layers.
        layer["opacity"] = 1 if i < 2 else 0
    save(doc, out_dir, SETUP)


def build_striped_mesh(json_in, out_dir, source_json, source_material, mask, target):
    """Copies a base-game garment mesh and adds the appearance `stripes` with the stripe material."""
    doc = load(json_in / source_json)
    root = doc["Data"]["RootChunk"]

    materials = root["localMaterialBuffer"]["materials"]
    entries = root["materialEntries"]
    source_entry = next(e for e in entries if e["name"]["$value"] == source_material)
    material = copy.deepcopy(materials[source_entry["index"]])
    found = 0
    for value in material["values"]:
        if "MultilayerSetup" in value:
            value["MultilayerSetup"]["DepotPath"]["$value"] = SETUP
            found += 1
        if "MultilayerMask" in value:
            value["MultilayerMask"]["DepotPath"]["$value"] = mask
            found += 1
    if found != 2:
        raise SystemExit(f"{source_json}: the material {source_material} is not a multilayer material")
    materials.append(material)

    entry = copy.deepcopy(source_entry)
    entry["index"] = len(materials) - 1
    entry["name"] = cname(STRIPES_MATERIAL)
    entries.append(entry)

    appearances = root["appearances"]
    appearance = copy.deepcopy(appearances[0])
    appearance["HandleId"] = "new"
    appearance["Data"]["name"] = cname(STRIPES_APPEARANCE)
    appearance["Data"]["chunkMaterials"] = [cname(STRIPES_MATERIAL) for _ in appearance["Data"]["chunkMaterials"]]
    appearances.append(appearance)
    renumber_handles(doc)
    save(doc, out_dir, target)


def build_app(json_in, out_dir):
    doc = load(json_in / "citizen__lowlife_ma.app.json")
    root = doc["Data"]["RootChunk"]
    source = next(a for a in root["appearances"] if a["Data"]["name"]["$value"] == BASE_APP_APPEARANCE)
    appearance = copy.deepcopy(source)
    data = appearance["Data"]
    data["name"] = cname(APPEARANCE)

    counts = {"top": 0, "glasses": 0, "hat": 0, "pants": 0, "cane": 0, "tattoos": 0, "garment": 0, "bindings": 0, "rotation": 0, "lod": 0, "proxy": 0}
    # Component id -> geometry hash of its new mesh. The clothing-fit data of these components
    # was made for the old meshes, so it must be switched off (if not, parts of the mesh are cut away).
    # The hat mesh has the geometry of the base beanie, so its data stays correct.
    swapped = {}
    top_info = mesh_info(json_in, "t1_004_ma_tshirt__longsleeve.mesh.json")
    glasses_info = mesh_info(json_in, "h1_069_ma_specs__round.mesh.json")
    cane_info = mesh_info(json_in, "npc_cane_a.mesh.json")

    def edit_component(node):
        mesh = depot_value(node.get("mesh"))
        # At a distance the game shows a low-detail stand-in mesh of the base appearance (a man in a
        # tank top). Hide it and keep the real meshes visible at all distances.
        name = node.get("name", {}).get("$value") if isinstance(node.get("name"), dict) else None
        if name == "AppearanceProxyMesh" and "chunkMask" in node:
            node["chunkMask"] = "0"
            counts["proxy"] += 1
        elif mesh and node.get("LODMode") == "Appearance":
            node["LODMode"] = "AlwaysVisible"
            counts["lod"] += 1
        if mesh == BASE_TANK_MESH and "id" in node:
            swapped[str(node["id"])] = top_info
        if mesh == BASE_NECKLACE_MESH and "id" in node:
            swapped[str(node["id"])] = glasses_info
        if mesh == BASE_CHEST_TATTOO_MESH and "id" in node:
            swapped[str(node["id"])] = cane_info
        if mesh == BASE_CHEST_TATTOO_MESH:
            # The chest tattoo component becomes the cane in his right hand. The cane mesh has no bones.
            node["mesh"]["DepotPath"]["$value"] = CANE_MESH
            set_appearance(node, "default")
            if "autoHideDistance" in node:
                node["autoHideDistance"] = 80
            counts["bindings"] += attach_to_slot(node, "WeaponRight")
            # The cane mesh goes down its -Z axis. Turn it 90 degrees about X so that it goes along the
            # +Y axis of the hand slot (first test: it stood out sideways from the hand).
            if isinstance(node.get("localTransform"), dict):
                node["localTransform"]["Orientation"].update({"i": CANE_ROTATION[0], "j": CANE_ROTATION[1], "k": CANE_ROTATION[2], "r": CANE_ROTATION[3]})
                for axis, metres in zip("xyz", CANE_OFFSET):
                    # FixedPoint: 1 m = 131072 bits.
                    node["localTransform"]["Position"][axis]["Bits"] = round(metres * 131072)
                counts["rotation"] += 1
            counts["cane"] += 1
        elif mesh and "\\tattoos\\" in mesh and "chunkMask" in node:
            # Tattoos on the arms and the chest come through the sleeves: hide all their chunks.
            node["chunkMask"] = "0"
            counts["tattoos"] += 1
        if mesh == BASE_TANK_MESH:
            node["mesh"]["DepotPath"]["$value"] = TOP_MESH
            set_appearance(node, STRIPES_APPEARANCE)
            counts["top"] += 1
        elif mesh == BASE_NECKLACE_MESH:
            # The glasses mesh has no bones: it must hang on the head slot (if not, it lies at his feet).
            node["mesh"]["DepotPath"]["$value"] = BASE_GLASSES_MESH
            set_appearance(node, "metallic")
            if "autoHideDistance" in node:
                node["autoHideDistance"] = 80
            counts["bindings"] += attach_to_slot(node, "Head")
            counts["glasses"] += 1
        elif mesh == BASE_PANTS_MESH:
            # White tracksuit pants: the `white` variant of the base mesh (user decision 2026-11-20).
            # Tight pants (BASE_SLIM_PANTS_MESH) were tried; the user prefers the tracksuit pants.
            set_appearance(node, "white")
            counts["pants"] += 1
        elif mesh == BASE_BEANIE_MESH:
            node["mesh"]["DepotPath"]["$value"] = HAT_MESH
            set_appearance(node, STRIPES_APPEARANCE)
            counts["hat"] += 1

    walk(data, edit_component)

    entries = []
    walk(data["parametersBuffer"], lambda n: entries.append(n) if n.get("$type") == "entGarmentParameterComponentData" else None)
    disabled = next(e for e in entries if e["disableGarment"] == 1)
    for entry in entries:
        component = str(entry["componentID"])
        if component in swapped:
            keep = {"componentID": entry["componentID"], "chunksCount": swapped[component][1], "meshGeometryHash": swapped[component][0]}
            for key in list(entry.keys()):
                entry[key] = copy.deepcopy(disabled[key])
            entry.update(keep)
            counts["garment"] += 1

    print("app edits:", counts)
    if counts["top"] == 0 or counts["glasses"] == 0 or counts["hat"] == 0 or counts["pants"] == 0 or counts["cane"] == 0 or counts["garment"] != 3 or counts["bindings"] != 2 or counts["rotation"] == 0 or counts["proxy"] == 0:
        raise SystemExit("a component of the base appearance was not found")

    # The appearance after he gave the cane to V: a copy with the cane hidden.
    no_cane = copy.deepcopy(appearance)
    no_cane["Data"]["name"] = cname(APPEARANCE_NO_CANE)
    hidden = [0]

    def hide_cane(node):
        if depot_value(node.get("mesh")) == CANE_MESH and "chunkMask" in node:
            node["chunkMask"] = "0"
            hidden[0] += 1

    walk(no_cane["Data"], hide_cane)
    if hidden[0] == 0:
        raise SystemExit(f"{APPEARANCE_NO_CANE}: the cane was not found")
    print("appearances:", APPEARANCE, APPEARANCE_NO_CANE)

    number_appearances(doc, [appearance, no_cane])
    save(doc, out_dir, APP)


def build_ent(json_in, out_dir):
    doc = load(json_in / "citizen__lowlife_ma.ent.json")
    root = doc["Data"]["RootChunk"]
    template = root["appearances"][0]
    entries = []
    for name in [APPEARANCE, APPEARANCE_NO_CANE]:
        entry = copy.deepcopy(template)
        entry["appearanceName"] = cname(name)
        entry["name"] = cname(name)
        entry["appearanceResource"]["DepotPath"]["$value"] = APP
        entries.append(entry)
    root["appearances"] = entries
    root["defaultAppearance"] = cname(APPEARANCE)
    save(doc, out_dir, ENT)


def build_localization(json_in, out_dir):
    # The header comes from a file that the CLI made, so that the versions are correct.
    header = load(json_in / "citizen__lowlife_ma.ent.json")["Header"]
    entries = [
        {"$type": "localizationPersistenceOnScreenEntry", "femaleVariant": text, "maleVariant": "", "primaryKey": "0", "secondaryKey": key}
        for key, text in TEXTS.items()
    ]
    doc = {
        "Header": dict(header),
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_PC",
                "root": {"HandleId": "0", "Data": {"$type": "localizationPersistenceOnScreenEntries", "entries": entries}},
            },
            "EmbeddedFiles": [],
        },
    }
    save(doc, out_dir, LOCALIZATION)


def number_appearances(doc, appearances):
    """Puts the appearances in an .app file. Each handle and each buffer in the file needs its own number."""
    doc["Data"]["RootChunk"]["appearances"] = appearances
    for index, item in enumerate(appearances):
        prefix = f"a{index}_"
        walk(item, lambda n, prefix=prefix: n.__setitem__("HandleId", prefix + n["HandleId"]) if "HandleId" in n else None)
        walk(item, lambda n, prefix=prefix: n.__setitem__("HandleRefId", prefix + n["HandleRefId"]) if "HandleRefId" in n else None)
    renumber_handles(doc)
    buffers = []
    walk(doc, lambda n: buffers.append(n) if "BufferId" in n else None)
    for number, node in enumerate(buffers):
        node["BufferId"] = str(number)


def replace_paths(node, paths):
    """Changes each resource path that is a key of `paths`. Returns the number of changes."""
    count = [0]

    def visit(n):
        ref = n.get("DepotPath")
        if isinstance(ref, dict) and ref.get("$value") in paths:
            ref["$value"] = paths[ref["$value"]]
            count[0] += 1

    walk(node, visit)
    return count[0]


def build_cane(json_in, out_dir):
    """The cane mesh with its material, and the appearance files of the cane weapon."""
    # Material: in the setup of the base cane, the first layer is bare aluminium and the third one is a plastic.
    doc = load(json_in / "ml_i1_001_ma_slot__fingers_cane.mlsetup.json")
    layers = doc["Data"]["RootChunk"]["layers"]
    metal, paint = layers[0], layers[2]
    new_layers = []
    for index, (template, colour) in enumerate(CANE_LAYERS):
        layer = copy.deepcopy(metal if index == 0 else paint)
        layer["material"]["DepotPath"]["$value"] = template
        layer["microblend"]["DepotPath"]["$value"] = "base\\surfaces\\microblends\\default.xbm"
        layer["microblendContrast"] = 1
        layer["microblendNormalStrength"] = 0
        layer["colorScale"] = cname(colour)
        layer["opacity"] = 1
        new_layers.append(layer)
    doc["Data"]["RootChunk"]["layers"] = new_layers
    save(doc, out_dir, CANE_SETUP)

    doc = load(json_in / "npc_cane_a.mesh.json")
    paths = {
        BASE_PLAIN_CANE + "textures\\ml_npc_cane_a.mlsetup": CANE_SETUP,
        BASE_PLAIN_CANE + "textures\\ml_npc_cane_a_masksset.mlmask": CANE_MASK,
    }
    if replace_paths(doc, paths) < 2:
        raise SystemExit("npc_cane_a.mesh: the material was not found")
    # The base mesh holds copies of its material files (setup, mask, normal texture) in the mesh file,
    # and the game uses those copies and not the files at the paths: the cane kept its old black look.
    # Take the copies out and make each reference a normal one, to the file at its path.
    embedded = len(doc["Data"]["EmbeddedFiles"])
    doc["Data"]["EmbeddedFiles"] = []
    doc["Data"]["RootChunk"]["inplaceResources"] = []
    flags = [0]

    def unembed(node):
        if node.get("Flags") == "Embedded":
            node["Flags"] = "Default"
            flags[0] += 1

    walk(doc["Data"]["RootChunk"], unembed)
    print(f"cane mesh: took out {embedded} embedded files, changed {flags[0]} references")
    if embedded == 0 or flags[0] == 0:
        raise SystemExit("npc_cane_a.mesh: the embedded material files were not found")
    save(doc, out_dir, CANE_MESH)

    for source, target, _ in CANE_WEAPON_FILES:
        doc = load(json_in / source)
        if replace_paths(doc, {BASE_CANE_MESH: CANE_MESH}) == 0:
            raise SystemExit(f"{source}: the cane mesh was not found")
        save(doc, out_dir, target)


def build_icon(json_in, out_dir):
    """The icons of the cane: the texture with the settings of an interface texture, and its atlas."""
    doc = load(json_in / "cane_icon.xbm.json")
    setup = doc["Data"]["RootChunk"]["setup"]
    setup["group"] = "TEXG_Generic_UI"
    setup["isGamma"] = 1
    setup["isStreamable"] = 0
    save(doc, out_dir, CANE_ICON_TEXTURE)

    # The atlas of the base game has a slot for each screen resolution. Both get the same texture.
    doc = load(json_in / "item_icons3.inkatlas.json")
    slots = doc["Data"]["RootChunk"]["slots"]["Elements"]
    pattern = slots[0]["parts"][0]
    parts = []
    for name, (left, top, right, bottom) in ((CANE_ICON_PART, make_cane_icon.ICON_RECT), (CANE_HUD_PART, make_cane_icon.HUD_RECT)):
        part = copy.deepcopy(pattern)
        part["partName"] = cname(name)
        part["clippingRectInUVCoords"].update({
            "Left": left / make_cane_icon.WIDTH, "Top": top / make_cane_icon.HEIGHT,
            "Right": right / make_cane_icon.WIDTH, "Bottom": bottom / make_cane_icon.HEIGHT,
        })
        parts.append(part)
    for slot in slots[:2]:
        slot["parts"] = copy.deepcopy(parts)
        slot["texture"]["DepotPath"]["$value"] = CANE_ICON_TEXTURE
    save(doc, out_dir, CANE_ICON_ATLAS)


def build_factory(json_in, out_dir):
    """The table that gives the file for each `appearanceResourceName` of the item records."""
    header = load(json_in / "citizen__lowlife_ma.ent.json")["Header"]
    rows = [[name, target, "false"] for _, target, name in CANE_WEAPON_FILES]
    columns = ["name", "path", "shared"]
    doc = {
        "Header": dict(header),
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "C2dArray",
                "compiledData": rows,
                "compiledHeaders": columns,
                "cookingPlatform": "PLATFORM_PC",
                "data": rows,
                "headers": columns,
            },
            "EmbeddedFiles": [],
        },
    }
    save(doc, out_dir, FACTORY)


def main():
    json_in, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    build_cane(json_in, out_dir)
    build_icon(json_in, out_dir)
    build_factory(json_in, out_dir)
    build_mlsetup(json_in, out_dir)
    build_striped_mesh(json_in, out_dir, "t1_004_ma_tshirt__longsleeve.mesh.json", "ml_t1_004_ma_tshirt__longsleeve_masksset", TOP_MASK, TOP_MESH)
    build_striped_mesh(json_in, out_dir, "h1_003_ma_hat__beanie.mesh.json", "ml_h1_003_ma_hat__beanie_masksset", HAT_MASK, HAT_MESH)
    build_app(json_in, out_dir)
    build_ent(json_in, out_dir)
    build_localization(json_in, out_dir)


if __name__ == "__main__":
    main()
