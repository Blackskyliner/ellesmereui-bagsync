#!/usr/bin/env python3
"""Blizzard UI textures for the visual tests, from Blizzard's CDN.

  blizzard-art.py fetch [DEST]   download the files of the lock into a
                                 minimal WoW install at DEST (default
                                 .tools/blizzard-art/<version>), skipping
                                 files already there and intact
  blizzard-art.py lock           re-pin: the textures the last visual test run
                                 missed plus those of the lock, against the
                                 current retail build

The lock (sim/visual/blizzard-art.lock.json) holds keys and archive offsets
only: Blizzard's art is not ours to redistribute, so the repository never
carries it. Each file is a byte range of a CDN archive, BLTE-encoded; it is
decoded and checked against its content key (MD5) before it is written.
DEST looks like a WoW install to the simulator: Data/data marks it as one
(asset-resolver), and the textures sit in _retail_/BlizzardInterfaceArt,
the extracted tree it reads besides CASC. With WOW_INSTALL_PATH=DEST and
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
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, "sim", "visual", "blizzard-art.lock.json")
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


ART_DIR = os.path.join("_retail_", "BlizzardInterfaceArt")


def fetch_one(entry, dest):
    path = os.path.join(dest, ART_DIR, entry["path"])
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


def relock():
    paths = set()
    for log in glob.glob(os.path.join(ROOT, ".tools", "visual-out", "*", "*.log")):
        with open(log, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = re.search(r"\[TexMgr\] Not found: (.+)$", line.rstrip("\n"))
                if m:
                    paths.add(m.group(1))
    if os.path.exists(LOCK):
        paths.update(e["path"] for e in load_lock()["files"])
    tool = os.path.join(ROOT, "scripts", "blizzard-art")
    target = os.path.join(ROOT, ".tools", "blizzard-art-target")
    env = dict(os.environ, CARGO_HOME=os.path.join(ROOT, ".tools", "cargo"), CARGO_TARGET_DIR=target)
    subprocess.run(["cargo", "build", "--release", "--quiet"], cwd=tool, env=env, check=True)
    listing = os.path.join(ROOT, ".tools", "blizzard-art-paths.txt")
    with open(listing, "w", encoding="utf-8") as fh:
        fh.write("\n".join(sorted(paths)) + "\n")
    subprocess.run([
        os.path.join(target, "release", "blizzard-art"),
        "--listfile", os.path.join(ROOT, ".tools", "vendor", "wow-ui-sim", "data", "wow-ui-sim-listfile.csv"),
        "--paths", listing, "--out", LOCK, "--cache", os.path.join(ROOT, ".tools", "blizzard-cdn"),
    ], check=True)
    return 0


def main(argv):
    if argv[:1] == ["fetch"] and len(argv) <= 2:
        return fetch(argv[1] if len(argv) == 2 else None)
    if argv == ["lock"]:
        return relock()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
