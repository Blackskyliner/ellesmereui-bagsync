#!/usr/bin/env python3
"""Blizzard UI textures for the visual tests, from Blizzard's CDN.

  blizzard-art.py [--client=retail|forever] COMMAND

  blizzard-art.py fetch [DEST]   download the files of the lock into a
                                 minimal WoW install at DEST (default
                                 .tools/blizzard-art/<version>), skipping
                                 files already there and intact
  blizzard-art.py inventory      list the textures the addon's surfaces need
                                 (D: held by their frame trees, S: named in our
                                 code, EllesmereUI's core and Bags, or the
                                 Blizzard templates and mixins they build on)
  blizzard-art.py lock           re-pin against the client's current build until
                                 the inventory and a run of every scenario
                                 find no texture missing; fails on anything it
                                 cannot pin or the simulator cannot decode

Each client has its own lock (sim/visual/blizzard-art.lock.json for retail,
blizzard-art-forever.lock.json for WoW Forever, CDN product wowf), built
from its own simulator checkout and Blizzard UI source. A lock holds keys and
archive offsets only: Blizzard's art is not ours to redistribute, so the repository never
carries it. Each file is a byte range of a CDN archive, BLTE-encoded; it is
decoded and checked against its content key (MD5) before it is written.
DEST looks like a WoW install to the simulator: Data/data marks it as one
(asset-resolver), and the textures sit in the client's extracted art tree
(_retail_/ or _classic_beta_/BlizzardInterfaceArt), which it reads besides
CASC. With WOW_INSTALL_PATH=DEST and
WOW_SIM_CASC=0 (no CASC archives exist) it reads only that tree.
"""
import concurrent.futures
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, ".tools", "vendor")
# Per client: its lock, CDN product, simulator checkout (atlas table and
# listfile), Blizzard UI source, and the install directory the simulator
# reads extracted art from (wow-ui-sim paths::blizzard_interface_art_root_for_install_root).
CLIENTS = {
    "retail": {"lock": "blizzard-art.lock.json", "product": "wow", "sim": "wow-ui-sim",
               "atlas": "atlas.rs", "ui": "wow-ui-source", "art": "_retail_"},
    "forever": {"lock": "blizzard-art-forever.lock.json", "product": "wowf", "sim": "wow-ui-sim-forever",
                "atlas": "atlas_wowforever.rs", "ui": "wow-ui-source-forever", "art": "_classic_beta_"},
}
CLIENT = "retail"
LOCK = SIM = BLIZZARD_UI = ART_DIR = None


def use_client(name):
    global CLIENT, LOCK, SIM, BLIZZARD_UI, ART_DIR
    c = CLIENTS[name]
    CLIENT = name
    LOCK = os.path.join(ROOT, "sim", "visual", c["lock"])
    SIM = os.path.join(VENDOR, c["sim"])
    BLIZZARD_UI = os.path.join(VENDOR, c["ui"], "Interface", "AddOns")
    ART_DIR = os.path.join(c["art"], "BlizzardInterfaceArt")


use_client("retail")
CDN = "https://us.cdn.blizzard.com/tpr/wow/data"


def load_lock():
    with open(LOCK, encoding="utf-8") as fh:
        return json.load(fh)


def default_dest(lock):
    return os.path.join(ROOT, ".tools", "blizzard-art", lock["version"])


def blte_decode(data, entry):
    if data[:4] != b"BLTE":
        raise ValueError("no BLTE signature")
    header_size = int.from_bytes(data[4:8], "big")
    if header_size == 0:
        chunks = [data[8:]]
    else:
        count = int.from_bytes(data[9:12], "big")
        pos, offset, chunks = 12, header_size, []
        for _ in range(count):
            size = int.from_bytes(data[pos:pos + 4], "big")
            chunks.append(data[offset:offset + size])
            offset += size
            pos += 24
    if hashlib.md5(data[:header_size] if header_size else data).hexdigest() != entry["encoding_key"]:
        raise ValueError("encoding key mismatch")
    out = []
    for chunk in chunks:
        mode, body = chunk[:1], chunk[1:]
        if mode == b"N":
            out.append(body)
        elif mode == b"Z":
            out.append(zlib.decompress(body))
        else:
            raise ValueError("unsupported BLTE chunk mode %r" % mode)
    return b"".join(out)


def intact(path, entry):
    try:
        with open(path, "rb") as fh:
            return hashlib.md5(fh.read()).hexdigest() == entry["content_key"]
    except OSError:
        return False


def download(entry):
    if entry["archive"]:
        name = entry["archive"]
        headers = {"Range": "bytes=%d-%d" % (entry["offset"], entry["offset"] + entry["size"] - 1)}
    else:
        name, headers = entry["encoding_key"], {}
    url = "%s/%s/%s/%s" % (CDN, name[:2], name[2:4], name)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as resp:
                data = resp.read()
            if len(data) != entry["size"]:
                raise ValueError("got %d bytes, expected %d" % (len(data), entry["size"]))
            return data
        except (urllib.error.URLError, TimeoutError, ValueError):
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def fetch_one(entry, dest):
    # One case for the whole tree: the listfile spells a few paths with
    # capitals (Interface/Buttons/...), and on a case-sensitive file system
    # those would become a second Interface directory next to interface/,
    # of which the simulator's case-insensitive lookup only searches one.
    path = os.path.join(dest, ART_DIR, entry["path"].lower())
    if intact(path, entry):
        return False
    content = blte_decode(download(entry), entry)
    if hashlib.md5(content).hexdigest() != entry["content_key"]:
        raise ValueError("%s: content key mismatch" % entry["path"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".part", "wb") as fh:
        fh.write(content)
    os.replace(path + ".part", path)
    return True


def fetch(dest):
    lock = load_lock()
    dest = dest or default_dest(lock)
    os.makedirs(os.path.join(dest, "Data", "data"), exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        jobs = {pool.submit(fetch_one, e, dest): e for e in lock["files"]}
        fetched = 0
        for job in concurrent.futures.as_completed(jobs):
            try:
                fetched += job.result()
            except Exception as err:  # noqa: BLE001 - name the file, then fail
                print("blizzard-art: %s: %s" % (jobs[job]["path"], err), file=sys.stderr)
                return 1
    print("blizzard-art: %d files in %s (%d fetched)" % (len(lock["files"]), dest, fetched))
    return 0


EUI = os.path.join(VENDOR, "EllesmereUI")
UI_NS = "{http://www.blizzard.com/wow/ui/}"
LUA_STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"|' + r"'((?:[^'\\\n]|\\.)*)'")


class Catalog:
    """The simulator's atlas table (name -> file) and listfile (path, ID)."""

    def __init__(self):
        self.atlas = {}
        atlas = os.path.join(SIM, "crates", "sim-data-profile", "data", CLIENTS[CLIENT]["atlas"])
        with open(atlas, encoding="utf-8") as fh:
            for m in re.finditer(r'^\s*"([^"]+)" => AtlasInfo \{ file: r"([^"]+)"', fh.read(), re.M):
                self.atlas[m.group(1).lower()] = m.group(2)
        self.paths, self.ids = {}, {}
        with open(os.path.join(SIM, "data", "wow-ui-sim-listfile.csv"), encoding="utf-8") as fh:
            for line in fh:
                fid, _, path = line.strip().partition(";")
                stem, ext = os.path.splitext(path.lower())
                if fid.isdigit() and ext in (".blp", ".tga"):
                    self.paths.setdefault(stem, path)
                    self.ids[int(fid)] = path

    def texture(self, text):
        """A texture path for an atlas name, texture path or file ID; else None."""
        value = text.strip()
        if value.isdigit():
            return self.ids.get(int(value))
        if value.lower() in self.atlas:
            return self.texture(self.atlas[value.lower()])
        key = os.path.splitext(value.replace("\\\\", "/").replace("\\", "/").lower())[0]
        return self.paths.get(key) or self.paths.get("interface/" + key)


def lua_files(*roots):
    for root in roots:
        if os.path.isfile(root):
            yield root
        for dirpath, _, names in os.walk(root):
            for name in names:
                if name.endswith(".lua"):
                    yield os.path.join(dirpath, name)


def literals(chunk):
    return {a or b for a, b in LUA_STRING.findall(chunk)}


LUA_CALL = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\(")
LUA_BLOCK = re.compile(r"^function\s+([A-Za-z_]\w*)([:.]\w+)?\s*\(.*?^end\b", re.M | re.S)
LUA_CONST = re.compile(r'^([A-Z][A-Z0-9_]*)\s*=\s*"([^"\n]*)"', re.M)
LUA_UPPER = re.compile(r"\b([A-Z][A-Z0-9_]{3,})\b")
LAYOUT = re.compile(r"^\t(\w+)\s*=\s*\n\t\{(.*?)^\t\};?", re.M | re.S)


class BlizzardUI:
    """Blizzard's UI source: virtual and intrinsic XML templates, top-level Lua
    functions (global ones by name, methods by mixin) and NineSlice layouts."""

    def __init__(self):
        self.templates, self.functions, self.methods, self.layouts = {}, {}, {}, {}
        self.constants = {}
        for dirpath, _, names in os.walk(BLIZZARD_UI):
            for name in names:
                path = os.path.join(dirpath, name)
                if name.endswith(".xml"):
                    self._index_xml(path)
                elif name.endswith(".lua"):
                    self._index_lua(path)

    def _index_xml(self, path):
        try:
            tree = ET.parse(path)
        except ET.ParseError:
            return
        for el in tree.iter():
            name = el.get("name")
            if name and (el.get("virtual") == "true" or el.get("intrinsic") == "true"):
                self.templates.setdefault(name, el)

    def _index_lua(self, path):
        with open(path, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
        for m in LUA_BLOCK.finditer(text):
            if m.group(2):
                self.methods.setdefault(m.group(1), []).append(m.group(0))
            else:
                self.functions.setdefault(m.group(1), m.group(0))
        for m in LUA_CONST.finditer(text):
            self.constants.setdefault(m.group(1), m.group(2))
        if os.path.basename(path) == "NineSliceLayouts.lua":
            for m in LAYOUT.finditer(text):
                self.layouts.setdefault(m.group(1), m.group(2))

    def closure(self, roots, calls, depth=2):
        """-> the strings reachable from the templates in roots and the global
        functions in calls: XML attributes and KeyValues, the methods of their
        mixins, their script handler functions, the NineSlice layouts and
        templates any of these name (also through string constants such as
        SCROLL_FRAME_SCROLL_BAR_TEMPLATE), and the global functions that Lua
        calls, up to depth calls deep."""
        strings, todo, done = set(), list(roots), set()
        lua_todo, lua_done = [(c, 0) for c in calls], set()

        def named(value):
            strings.add(value)
            if value in self.templates:
                todo.append(value)
            if value in self.layouts:
                strings.update(literals(self.layouts[value]))

        def scan_lua(chunk, level):
            for value in literals(chunk):
                named(value)
            for const in LUA_UPPER.findall(chunk):
                if const in self.constants:
                    named(self.constants[const])
            if level < depth:
                lua_todo.extend((c, level + 1) for c in LUA_CALL.findall(chunk))

        while todo or lua_todo:
            while todo:
                name = todo.pop()
                if name in done or name not in self.templates:
                    continue
                done.add(name)
                for el in self.templates[name].iter():
                    tag = el.tag.replace(UI_NS, "")
                    if tag in self.templates:
                        todo.append(tag)
                    for attr in ("file", "atlas", "layoutType"):
                        if el.get(attr):
                            named(el.get(attr))
                    if tag == "KeyValue" and el.get("value"):
                        named(el.get("value"))
                    if el.get("function"):
                        lua_todo.append((el.get("function"), 0))
                    for attr in ("inherits", "mixin", "secureMixin"):
                        for ref in (el.get(attr) or "").split(","):
                            ref = ref.strip()
                            for block in self.methods.get(ref, ()):
                                scan_lua(block, 0)
                            if ref:
                                todo.append(ref)
            while lua_todo:
                name, level = lua_todo.pop()
                if (name, level) in lua_done:
                    continue
                lua_done.add((name, level))
                if name in self.functions:
                    scan_lua(self.functions[name], level)
                for block in self.methods.get(name, ()):
                    scan_lua(block, level)
        return strings


def static_inventory(catalog):
    """Textures named in our code and EllesmereUI's Bags module, and in the
    Blizzard templates, mixins and functions they use. EllesmereUI's core
    serves every module of the suite; what it puts into our frames the
    frame-tree inventory finds."""
    strings, calls = set(), set()
    for path in lua_files(os.path.join(ROOT, "EllesmereUIBags_Alts"), os.path.join(EUI, "EllesmereUIBags")):
        with open(path, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
        strings |= literals(text)
        calls.update(LUA_CALL.findall(text))
    ui = BlizzardUI()
    roots = {"ItemButton"} | {t.strip() for text in strings for t in text.split(",") if t.strip() in ui.templates}
    strings |= ui.closure(roots, calls)
    return {catalog.texture(t) for t in strings} - {None}


def dynamic_inventory(catalog):
    """Textures the frame trees of every surface hold (visual-test.sh --inventory)."""
    subprocess.run([os.path.join(ROOT, "scripts", "visual-test.sh"), "--client=" + CLIENT, "--inventory"],
                   check=True, stdout=sys.stderr)
    found = set()
    with open(os.path.join(ROOT, ".tools", "visual-out", CLIENT, "inventory.log"), encoding="utf-8") as fh:
        for line in fh:
            kind, _, value = line.rstrip("\n").partition(" ")
            if kind in ("atlas", "path", "fdid") and "addons" not in value.lower():
                found.add(catalog.texture(value) or value)
    return found


def inventory(catalog=None):
    catalog = catalog or Catalog()
    dynamic = dynamic_inventory(catalog)
    static = static_inventory(catalog)
    return dynamic, static


def texture_errors(log_dir):
    """-> (paths the simulator did not find, files it failed to decode) in
    the logs below log_dir."""
    missing, broken = set(), set()
    for log in glob.glob(os.path.join(log_dir, "**", "*.log"), recursive=True):
        with open(log, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = re.search(r"\[TexMgr\] (Not found|Load error): (.+)$", line.rstrip("\n"))
                if m:
                    (missing if m.group(1) == "Not found" else broken).add(m.group(2))
    return missing, broken


def write_lock(paths):
    """Pins paths against the client's current build; -> the paths it could not pin."""
    tool = os.path.join(ROOT, "scripts", "blizzard-art")
    target = os.path.join(ROOT, ".tools", "blizzard-art-target")
    env = dict(os.environ, CARGO_HOME=os.path.join(ROOT, ".tools", "cargo"), CARGO_TARGET_DIR=target)
    subprocess.run(["cargo", "build", "--release", "--quiet"], cwd=tool, env=env, check=True)
    listing = os.path.join(ROOT, ".tools", "blizzard-art-paths.txt")
    with open(listing, "w", encoding="utf-8") as fh:
        fh.write("\n".join(sorted(paths)) + "\n")
    run = subprocess.run([
        os.path.join(target, "release", "blizzard-art"),
        "--listfile", os.path.join(SIM, "data", "wow-ui-sim-listfile.csv"),
        "--paths", listing, "--out", LOCK, "--cache", os.path.join(ROOT, ".tools", "blizzard-cdn"),
        "--product", CLIENTS[CLIENT]["product"],
    ], check=True, stderr=subprocess.PIPE, text=True)
    sys.stderr.write(run.stderr)
    return [line for line in run.stderr.splitlines() if line.startswith("not in ")]


def norm(path):
    """A texture path as the simulator's misses and the listfile compare."""
    return os.path.splitext(path.replace("\\", "/").lower())[0].removeprefix("interface/")


ABSENT = re.compile(r"^not in (?:the listfile: (.+)|root: \d+ (.+))$")


def record_absent(unpinned, absent):
    """Adds the textures that cannot be pinned for this client to absent and
    stores them in the lock; -> the lines that are another failure. Absent
    are textures the build's root does not hold (e.g. retail talent icons the
    simulator preloads on Forever) and names the simulator cannot map to a
    file: no listfile entry, or an atlas missing from its table for the
    client. They can never be pinned, and the simulator misses them the same
    way in every run."""
    other = []
    for line in unpinned:
        m = ABSENT.match(line)
        if m:
            absent.add(m.group(1) or m.group(2))
        else:
            other.append(line)
    lock = load_lock()
    lock["absent"] = sorted(absent, key=str.lower)
    with open(LOCK, "w", encoding="utf-8") as fh:
        json.dump(lock, fh, indent=2)
        fh.write("\n")
    return other


def relock():
    """Pins until a full run finds nothing missing: each round fetches the
    lock, takes the inventory, renders every scenario, and pins whatever the
    inventory names or the simulator did not find. A texture that cannot be
    pinned for the client is recorded as absent (record_absent); anything else that cannot be
    pinned or decoded fails the run, so the lock covers every texture the
    simulator asks for."""
    catalog = Catalog()
    static = static_inventory(catalog)
    logs = os.path.join(ROOT, ".tools", "visual-out", CLIENT)
    absent = set(load_lock().get("absent", ())) if os.path.exists(LOCK) else set()
    if not os.path.exists(LOCK):
        # The renders need a lock to fetch; the static inventory seeds it.
        unpinned = record_absent(write_lock(static), absent)
        if unpinned:
            print("blizzard-art: cannot pin:\n  " + "\n  ".join(unpinned), file=sys.stderr)
            return 1
    for round_no in range(1, 6):
        locked = {e["path"] for e in load_lock()["files"]} if os.path.exists(LOCK) else set()
        gone = {norm(p) for p in absent}
        if fetch(None):
            return 1
        dynamic = dynamic_inventory(catalog)
        missing, broken = texture_errors(logs)
        subprocess.run([os.path.join(ROOT, "scripts", "visual-test.sh"), "--client=" + CLIENT], stdout=sys.stderr)
        more_missing, more_broken = texture_errors(logs)
        missing |= more_missing
        broken |= more_broken
        if broken:
            print("blizzard-art: the simulator failed to decode:\n  " + "\n  ".join(sorted(broken)), file=sys.stderr)
            return 1
        missing = {p for p in missing if norm(p) not in gone}
        wanted = {catalog.texture(p) or p for p in dynamic | static | missing}
        wanted = {p for p in wanted if norm(p) not in gone}
        new = {p for p in wanted if p.lower() not in {l.lower() for l in locked}}
        print("blizzard-art: round %d: %d in the frame trees, %d named in code and templates, "
              "%d not found by the simulator, %d new" % (round_no, len(dynamic), len(static), len(missing), len(new)))
        if not new and not missing:
            print("blizzard-art: %d textures pinned, %d absent (see the lock); no texture missing"
                  % (len(locked), len(absent)))
            return 0
        if not new:
            print("blizzard-art: still not found although pinned:\n  " + "\n  ".join(sorted(missing)), file=sys.stderr)
            return 1
        unpinned = record_absent(write_lock(locked | wanted), absent)
        if unpinned:
            print("blizzard-art: cannot pin:\n  " + "\n  ".join(unpinned), file=sys.stderr)
            return 1
    print("blizzard-art: no fixed point after 5 rounds", file=sys.stderr)
    return 1


def print_inventory():
    dynamic, static = inventory()
    for path in sorted(dynamic | static, key=str.lower):
        print("%s%s %s" % ("D" if path in dynamic else "-", "S" if path in static else "-", path))
    return 0


def main(argv):
    if argv[:1] and argv[0].startswith("--client="):
        name = argv[0].split("=", 1)[1]
        if name not in CLIENTS:
            print("blizzard-art: unknown client %s" % name, file=sys.stderr)
            return 2
        use_client(name)
        argv = argv[1:]
    if argv[:1] == ["fetch"] and len(argv) <= 2:
        return fetch(argv[1] if len(argv) == 2 else None)
    if argv == ["lock"]:
        return relock()
    if argv == ["inventory"]:
        return print_inventory()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
