#!/usr/bin/env python3
"""T3e-o: netplay_on.sh, netplay_off.sh and normal_main.py on a fake /media/fat.

netplay_on before v0.5 saved the active netplay binary as MiSTer_offline on an
update; normal_main.py puts the official binary there (MD5 from the
distribution database, or downloader's .MiSTer.old when offline). A local HTTP
server stands in for the database; reboot and sleep are stubs.

  python3 -I tools/mister-scripts/test_netplay_onoff.py
"""
import atexit, hashlib, http.server, io, json, os, shutil, subprocess, sys, tempfile, threading, zipfile

HERE = os.environ.get("NP_SCRIPTS") or os.path.dirname(os.path.abspath(__file__))
fails = []


def check(name, ok, info=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  " + info))
    if not ok:
        fails.append(name)


def elf(tag, netplay):
    return b"\x7fELF" + tag.encode() + (b"\0/media/fat/netplay.ini\0" if netplay else b"\0") + b"x" * 64


OFFICIAL = elf("official-new", False)
OLDBACKUP = elf("official-old", False)
NP_OLD = elf("netplay-0040", True)
NP_NEW = elf("netplay-v0.7", True)
USER = elf("users-own", False)


class Srv(http.server.BaseHTTPRequestHandler):
    files = {}
    hits = []

    def do_GET(self):
        Srv.hits.append(self.path)
        body = Srv.files.get(self.path)
        if body is None:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def serve(db_hash=None, zipped=True, url_field=False):
    db = {"db_id": "distribution_mister", "base_files_url": BASE + "/files/",
          "files": {"MiSTer": {"hash": db_hash or hashlib.md5(OFFICIAL).hexdigest(),
                               "size": len(OFFICIAL)}}}
    if url_field:
        db["base_files_url"] = ""
        db["files"]["MiSTer"]["url"] = BASE + "/elsewhere/MiSTer"
    raw = json.dumps(db).encode()
    if zipped:
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("db.json", raw)
        raw = b.getvalue()
    Srv.files = {"/db.json.zip": raw, "/files/MiSTer": OFFICIAL, "/elsewhere/MiSTer": OFFICIAL}
    Srv.hits = []


httpd = http.server.HTTPServer(("127.0.0.1", 0), Srv)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % httpd.server_port
DOWN = "http://127.0.0.1:1/db.json.zip"  # nothing listens there


def tree(mister=None, offline=None, online=None, backup=None, ini=None):
    fat = tempfile.mkdtemp(prefix="npfat")
    atexit.register(shutil.rmtree, fat, True)
    d = os.path.join(fat, "Scripts/.config/netplay")
    os.makedirs(d)
    for s in ("netplay_on.sh", "netplay_off.sh"):
        shutil.copy(os.path.join(HERE, s), os.path.join(fat, "Scripts", s))
    shutil.copy(os.path.join(HERE, "normal_main.py"), d)
    for name, data in (("MiSTer", mister), ("MiSTer_offline", offline), ("MiSTer_online", online),
                       (".MiSTer.old", backup)):
        if data is not None:
            with open(os.path.join(fat, name), "wb") as f:
                f.write(data)
    if ini is not None:
        with open(os.path.join(fat, "downloader.ini"), "w") as f:
            f.write(ini)
    stub = os.path.join(fat, ".stub")
    os.makedirs(stub)
    for c, body in (("reboot", 'echo rebooted > "$NP_FAT/.rebooted"'), ("sleep", "true")):
        with open(os.path.join(stub, c), "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(os.path.join(stub, c), 0o755)
    return fat


def env(fat, db=None):
    e = dict(os.environ, NP_FAT=fat, PATH=os.path.join(fat, ".stub") + ":/usr/bin:/bin")
    e.pop("NP_DB_URL", None)
    if db:
        e["NP_DB_URL"] = db
    return e


def run(fat, what, db=None, *args):
    cmd = ["python3", os.path.join(fat, "Scripts/.config/netplay/normal_main.py")] + list(args) \
        if what == "fix" else ["bash", os.path.join(fat, "Scripts", what)]
    p = subprocess.run(cmd, env=env(fat, db), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.returncode, p.stdout


def get(fat, name):
    try:
        with open(os.path.join(fat, name), "rb") as f:
            return f.read()
    except OSError:
        return None


def rebooted(fat):
    return os.path.exists(os.path.join(fat, ".rebooted"))


# normal_main.py
serve()
fat = tree(mister=NP_NEW, offline=NP_OLD)
rc, out = run(fat, "fix", BASE + "/db.json.zip")
check("fix: netplay MiSTer_offline -> the official binary", rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL, out)
check("fix: MiSTer itself untouched", get(fat, "MiSTer") == NP_NEW)
check("fix: executable", os.access(os.path.join(fat, "MiSTer_offline"), os.X_OK))
check("fix: no MiSTer_offline.new left", get(fat, "MiSTer_offline.new") is None)

serve(db_hash="0" * 32)
fat = tree(mister=NP_NEW, offline=NP_OLD, backup=elf("x", True))
rc, out = run(fat, "fix", BASE + "/db.json.zip")
check("fix: MD5 mismatch -> nothing installed, exit 1",
      rc == 1 and get(fat, "MiSTer_offline") == NP_OLD and "does not match" in out, out)

fat = tree(mister=NP_NEW, offline=NP_OLD, backup=OLDBACKUP)
rc, out = run(fat, "fix", DOWN)
check("fix: offline -> downloader's .MiSTer.old", rc == 0 and get(fat, "MiSTer_offline") == OLDBACKUP, out)

fat = tree(mister=NP_NEW, offline=NP_OLD)
rc, out = run(fat, "fix", DOWN)
check("fix: offline, no backup -> exit 1, unchanged", rc == 1 and get(fat, "MiSTer_offline") == NP_OLD, out)

fat = tree(mister=NP_NEW)
rc, out = run(fat, "fix", DOWN)
check("fix: MiSTer_offline missing, offline, no backup -> exit 1", rc == 1 and get(fat, "MiSTer_offline") is None, out)

serve()
fat = tree(mister=NP_NEW)
rc, out = run(fat, "fix", BASE + "/db.json.zip")
check("fix: MiSTer_offline missing -> the official binary", rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL, out)

serve()
fat = tree(mister=NP_NEW, offline=USER)
rc, out = run(fat, "fix", BASE + "/db.json.zip")
check("fix: a normal MiSTer_offline is kept, nothing fetched",
      rc == 0 and get(fat, "MiSTer_offline") == USER and Srv.hits == [], str(Srv.hits))

serve()
fat = tree(mister=NP_NEW, offline=NP_OLD,
           ini="[mister]\nfoo = 1\n\n[distribution_mister]\ndb_url = %s/db.json.zip\n\n[jtcores]\ndb_url = x\n" % BASE)
rc, out = run(fat, "fix")
check("fix: database from downloader.ini [distribution_mister]",
      rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL and Srv.hits[:1] == ["/db.json.zip"], out + str(Srv.hits))

serve(zipped=False, url_field=True)
Srv.files["/db.json"] = Srv.files.pop("/db.json.zip")
fat = tree(mister=NP_NEW, offline=NP_OLD)
rc, out = run(fat, "fix", BASE + "/db.json")
check("fix: plain db.json, the file's own url", rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL, out)

serve()
fat = tree(mister=NP_NEW, offline=NP_OLD)
rc, out = run(fat, "fix", BASE + "/db.json.zip", "--check")
check("fix --check: verifies, changes nothing", rc == 0 and "OK" in out and get(fat, "MiSTer_offline") == NP_OLD, out)

# netplay_off.sh
serve()
fat = tree(mister=NP_NEW, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_off.sh", BASE + "/db.json.zip")
check("off: bad MiSTer_offline -> fetched, MiSTer is the official binary, reboot",
      rc == 0 and get(fat, "MiSTer") == OFFICIAL and rebooted(fat), out)

fat = tree(mister=NP_NEW, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_off.sh", DOWN)
check("off: bad MiSTer_offline, offline, no backup -> exit 1, nothing changed, no reboot",
      rc == 1 and get(fat, "MiSTer") == NP_NEW and not rebooted(fat) and "network" in out, out)

fat = tree(mister=NP_NEW, offline=USER, online=NP_NEW)
rc, out = run(fat, "netplay_off.sh", DOWN)
check("off: the usual case -> MiSTer_offline back", rc == 0 and get(fat, "MiSTer") == USER and rebooted(fat), out)

fat = tree(mister=USER, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_off.sh", DOWN)
check("off: netplay not active -> nothing", rc == 0 and get(fat, "MiSTer") == USER and not rebooted(fat), out)

# netplay_on.sh
serve()
fat = tree(mister=NP_OLD, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_on.sh", BASE + "/db.json.zip")
check("on: update with a bad MiSTer_offline -> fixed, new netplay binary, reboot",
      rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL and get(fat, "MiSTer") == NP_NEW and rebooted(fat), out)

fat = tree(mister=NP_OLD, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_on.sh", DOWN)
check("on: update, offline -> still switches, says netplay_off tries again",
      rc == 0 and get(fat, "MiSTer") == NP_NEW and get(fat, "MiSTer_offline") == NP_OLD and rebooted(fat)
      and "tries again" in out, out)

serve()
fat = tree(mister=NP_NEW, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_on.sh", BASE + "/db.json.zip")
check("on: already active with a bad MiSTer_offline -> fixed, no reboot",
      rc == 0 and get(fat, "MiSTer_offline") == OFFICIAL and not rebooted(fat), out)

serve()
fat = tree(mister=USER, offline=NP_OLD, online=NP_NEW)
rc, out = run(fat, "netplay_on.sh", BASE + "/db.json.zip")
check("on: first time -> your binary saved, nothing fetched",
      rc == 0 and get(fat, "MiSTer_offline") == USER and get(fat, "MiSTer") == NP_NEW and Srv.hits == [], out)

serve()
fat = tree(mister=NP_OLD, offline=USER, online=NP_NEW)
rc, out = run(fat, "netplay_on.sh", BASE + "/db.json.zip")
check("on: update, good MiSTer_offline -> kept, nothing fetched",
      rc == 0 and get(fat, "MiSTer_offline") == USER and get(fat, "MiSTer") == NP_NEW and Srv.hits == [], out)

print("ALL PASS" if not fails else "%d FAILED: %s" % (len(fails), ", ".join(fails)))
sys.exit(1 if fails else 0)
