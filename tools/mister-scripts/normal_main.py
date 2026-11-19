#!/usr/bin/env python3
"""Puts the official MiSTer binary in /media/fat/MiSTer_offline when that file
is missing or is a netplay binary. netplay_on before v0.5 saved the active
netplay binary there when it updated one netplay binary with another, so
netplay_off had nothing normal to go back to. netplay_on and netplay_off run
this (from Scripts/.config/netplay/) when they find it so.

The binary comes from the MiSTer distribution database that downloader and
update_all use: the db_url of [distribution_mister] in downloader.ini, or
MiSTer-devel's. It is installed only when its MD5 matches the database. When
the MiSTer is offline, downloader's own backup .MiSTer.old is used if it is a
normal binary (an older official one; update_all brings the newest later).

  python3 normal_main.py [--check]    --check: fetch and verify, change nothing
Exit 0: MiSTer_offline is a normal binary (already, or now). 1: it is not.
NP_FAT and NP_DB_URL override /media/fat and the database (for the tests).
"""
import configparser, hashlib, io, json, os, ssl, sys, urllib.request, zipfile

FAT = os.environ.get("NP_FAT", "/media/fat")
DEFAULT_DB = "https://raw.githubusercontent.com/MiSTer-devel/Distribution_MiSTer/main/db.json.zip"
OFFLINE = os.path.join(FAT, "MiSTer_offline")


def is_normal(data):
    # the netplay binary has netplay.ini in it, the normal one does not
    return data[:4] == b"\x7fELF" and b"netplay.ini" not in data


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return b""


def db_url():
    if os.environ.get("NP_DB_URL"):
        return os.environ["NP_DB_URL"]
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    try:
        cp.read(os.path.join(FAT, "downloader.ini"))
        for s in cp.sections():
            if s.lower() == "distribution_mister" and cp.get(s, "db_url", fallback="").strip():
                return cp.get(s, "db_url").strip()
    except (configparser.Error, UnicodeDecodeError):
        pass
    return DEFAULT_DB


def get(url):
    kw = {}
    if url.startswith("https:"):
        ca = [p for p in (os.path.join(FAT, "Scripts/.config/downloader/cacert.pem"),
                          "/etc/ssl/certs/cacert.pem") if os.path.isfile(p)]
        kw["context"] = ssl.create_default_context(cafile=ca[0] if ca else None)
    req = urllib.request.Request(url, headers={"User-Agent": "mister-netplay"})
    with urllib.request.urlopen(req, timeout=60, **kw) as r:
        return r.read()


def official():
    """The official binary from the database, MD5-checked, or None."""
    url = db_url()
    try:
        raw = get(url)
        if raw[:2] == b"PK":
            z = zipfile.ZipFile(io.BytesIO(raw))
            raw = z.read([n for n in z.namelist() if n.endswith(".json")][0])
        db = json.loads(raw)
        entry = db["files"]["MiSTer"]
        furl = entry.get("url") or (db.get("base_files_url") or "") + "MiSTer"
        data = get(furl)
    except Exception as e:  # network, format: all mean "not now"
        print("Could not get the official MiSTer binary (%s): %s" % (url, e))
        return None
    if hashlib.md5(data).hexdigest() != entry.get("hash") or not is_normal(data):
        print("The downloaded MiSTer binary does not match the database; not used.")
        return None
    return data


def install(data):
    tmp = OFFLINE + ".new"
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o755)
    os.replace(tmp, OFFLINE)


def main():
    check = "--check" in sys.argv[1:]
    if is_normal(read(OFFLINE)) and not check:
        return 0
    data = official()
    how = "the official one from the MiSTer database"
    if data is None:
        data = read(os.path.join(FAT, ".MiSTer.old"))
        how = "downloader's backup .MiSTer.old (update_all brings a newer one)"
        if not is_normal(data):
            return 1
    if check:
        print("OK: %s, %d bytes, MD5 %s." % (how, len(data), hashlib.md5(data).hexdigest()))
        return 0
    install(data)
    print("MiSTer_offline is your normal MiSTer binary again: %s." % how)
    return 0


if __name__ == "__main__":
    sys.exit(main())
