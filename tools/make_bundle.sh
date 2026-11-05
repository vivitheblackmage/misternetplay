#!/usr/bin/env bash
# Packs a release folder into one ready-to-use zip:
#
#   tools/make_bundle.sh releases/v0.1   ->  releases/v0.1/mister-netplay-v0.1.zip
#
#   mister-netplay-v0.1/
#     README.txt        quick start
#     SD card/          copy onto the MiSTer's SD card (root, where _Console is)
#     Server/           netplay-server for Windows, Linux, Raspberry Pi
#     SOURCE.txt, md5sums.txt
# make_release.sh runs it. File modes are kept (Linux binaries stay executable).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
rel="$(cd "${1:?usage: $0 releases/<version>}" && pwd)"
ver="$(basename "$rel")"
name="mister-netplay-$ver"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
b="$work/$name"

mkdir -p "$b/SD card" "$b/Server"
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$rel/netplay-kit.zip" "$b/SD card"
chmod +x "$b/SD card/MiSTer_online" "$b/SD card"/Scripts/*.sh
cp "$rel"/server/* "$b/Server/"
chmod +x "$b"/Server/netplay-server-linux-* "$b/Server/install-linux.sh"
cp "$rel/SOURCE.txt" "$b/"
[ -f "$rel/RELEASE_NOTES.md" ] && cp "$rel/RELEASE_NOTES.md" "$b/"

cat > "$b/README.txt" <<EOF
NES AND SNES NETPLAY $ver - EVERYTHING IN ONE

Two MiSTers play NES or SNES together over the network. SOURCE.txt says where
the code comes from (MiSTer-devel's NES and SNES cores and Main_MiSTer, plus
our patches). RELEASE_NOTES.md says what is new.

1. THE MISTER (do this on both)
   Copy the contents of the folder "SD card" to the root of the SD card (where
   _Console is). None of your files is overwritten. Then: Scripts -> netplay_on.
   More in "SD card/README-netplay.txt".

2a. WITHOUT A SERVER (one player forwards a port in the router)
   Host: forward UDP 7845 in the router. OSD in NES_netplay or SNES_netplay:
   Netplay -> Host.
   Join: put the host's address in /media/fat/netplay.ini, peer=..., and
   Netplay -> Join. Load the same game (NetPong is included).

2b. WITH A SERVER (no ports at the players, a room list in the OSD)
   On a computer that is always on (Windows PC or Raspberry Pi):
     Windows: double-click Server/netplay-server.exe.
     Raspberry Pi / Linux: copy the Server folder there and run
       sudo sh install-linux.sh
   The first start creates netplay-server.ini with a key (key=). Forward port
   7845, UDP and TCP, in the router to that computer.
   On each MiSTer, in /media/fat/netplay.ini:
     server=<the server's address>:7845
     key=<the key>
     name=<your name>
   One player: Netplay -> Host and load a game. The other: the file browser,
   folder _Netplay/Rooms, open the room and pick the game in it.
   More in Server/README.md.

Switching between NES_netplay and SNES_netplay: reboot from the MiSTer's menu
first (or pick the other core after a reboot). Jumping straight from one core
to the other can leave netplay without the ROM reload at the start.

Check: md5sums.txt. Always pass on the zip file, not loose files (FTP in ASCII
mode breaks the binaries).
EOF

(cd "$b" && find . -type f ! -name md5sums.txt | sort | xargs -d '\n' md5sum > md5sums.txt)

out="$rel/$name.zip"
rm -f "$out"
python3 -I - "$work" "$name" "$out" <<'PY'
import os, sys, zipfile
work, name, out = sys.argv[1:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, files in sorted(os.walk(os.path.join(work, name))):
        for f in sorted(files):
            p = os.path.join(d, f)
            info = zipfile.ZipInfo.from_file(p, os.path.relpath(p, work))
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(p, "rb") as fh:
                z.writestr(info, fh.read())
PY
echo "$out ($(du -h "$out" | cut -f1))"
