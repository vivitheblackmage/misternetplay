#!/usr/bin/env bash
# Builds the folder that moves netplay-server to a Raspberry Pi (or any Linux
# machine with systemd), to send over with FileBridge or copy on a USB stick:
#
#   tools/make_pi_server.sh <from-folder> <to-folder>
#
#   from-folder  the server's folder so far (e.g. on Windows), whose
#                netplay-server.ini (the key), catalog.txt and roms/ go along
#   to-folder    the folder to build (created if missing)
#
# On the Pi, in that folder, the same command installs and updates:
#   sudo sh install-linux.sh
# The server then starts by itself at every boot and after a crash.
# The folder holds the server's key: keep it to yourself (it is not a release).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
from="${1:?usage: $0 <from-folder> <to-folder>}"
to="${2:?usage: $0 <from-folder> <to-folder>}"
b="$root/server/build"
for f in netplay-server-linux-arm64 netplay-server-linux-armv7 install-linux.sh; do
	[ -f "$b/$f" ] || { echo "missing $b/$f: run server/build.sh"; exit 1; }
done
for g in "$root"/server/*.go "$root/server/install-linux.sh"; do
	[ "$b/netplay-server-linux-arm64" -nt "$g" ] || { echo "server/build is older than $g: run server/build.sh"; exit 1; }
done

mkdir -p "$to"
cp "$b/netplay-server-linux-arm64" "$b/netplay-server-linux-armv7" "$b/install-linux.sh" "$to/"
chmod +x "$to"/netplay-server-linux-*
for f in netplay-server.ini catalog.txt; do [ -f "$from/$f" ] && cp "$from/$f" "$to/"; done
[ -d "$from/roms" ] && { mkdir -p "$to/roms"; cp -r "$from/roms/." "$to/roms/"; }
cp "$root/server/README.md" "$to/"

cat > "$to/README-pi.txt" <<'EOF'
NETPLAY-SERVER ON A RASPBERRY PI

1. Send this whole folder to the Pi (FileBridge, scp or a USB stick).
2. On the Pi, in this folder:

     sudo sh install-linux.sh

   That is all. The server runs as a service: it starts by itself at every
   boot and again after a crash. The same command updates it: send the new
   folder over and run it again (settings, key and games on the Pi stay).

   netplay-server.ini in this folder (the key of the server you had before)
   and catalog.txt are used only when the Pi has none yet, so the MiSTers keep
   their key= and only server= changes to the Pi's address. The games in
   roms/ are copied to the Pi (nothing there is deleted).

3. In the router, forward port 7845 (UDP and TCP) to the Pi.
   On each MiSTer, in /media/fat/netplay.ini: server=<the Pi's address>:7845

Useful on the Pi:
  systemctl status netplay-server        is it running
  journalctl -u netplay-server -f        its log
  sudo systemctl restart netplay-server  restart (normally never needed)
  sudo sh install-linux.sh remove        stop and remove the service
Settings and games on the Pi: /opt/netplay-server
Status page: http://<the Pi's address>:7845/
EOF
echo "$to: $(ls "$to" | tr '\n' ' ')"
echo "roms: $(find "$to/roms" -type f 2>/dev/null | wc -l) files"
