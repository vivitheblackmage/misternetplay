#!/usr/bin/env bash
# Builds dist/netplay-kit.zip for another MiSTer (a friend's): unzip it into
# the root of the SD card (/media/fat). Contains exactly the builds in this
# workspace, so both MiSTers run the same core, binary and NetPong ROM.
#
#   tools/make_kit.sh [host-address]
#   tools/make_kit.sh --server host[:port] --key KEY [--name NAME]
#
# host-address goes into the kit's netplay.ini as peer= (the friend joins you).
# With --server the kit uses a netplay-server lobby (server/), no port
# forwarding at the players; key is the one in netplay-server.ini, name the
# friend's player name.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
peer="" server="" key="" name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --server) server="$2"; shift 2 ;;
    --key)    key="$2"; shift 2 ;;
    --name)   name="$2"; shift 2 ;;
    -*)       echo "unknown option $1"; exit 1 ;;
    *)        peer="$1"; shift ;;
  esac
done
if [ -n "$server" ] && [ -z "$key" ]; then echo "--server needs --key"; exit 1; fi
kit="$root/dist/netplay-kit"
rbf="$root/NES_MiSTer/output_files/NES.rbf"
bin="$root/Main_MiSTer/bin/MiSTer"
rom="$root/netpong/netpong.nes"

for f in "$rbf" "$bin" "$rom"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

rm -rf "$kit" "$root/dist/netplay-kit.zip"
mkdir -p "$kit/_Console" "$kit/Scripts" "$kit/games/NES/NetPong"
cp "$rbf" "$kit/_Console/NES_netplay.rbf"
cp "$bin" "$kit/MiSTer_online"
cp "$root"/tools/mister-scripts/netplay_on.sh "$root"/tools/mister-scripts/netplay_off.sh "$kit/Scripts/"
cp "$rom" "$kit/games/NES/NetPong/NetPong.nes"
chmod +x "$kit/MiSTer_online" "$kit"/Scripts/*.sh

cat > "$kit/netplay.ini" <<EOF
; NES netplay. The NES_netplay core's OSD option "Netplay" picks Off/Host/Join;
; this file gives the address, port and delay.

[netplay]
mode=off            ; used only when the OSD option says "netplay.ini"
peer=$peer          ; Join: the host's address (IP or name)
port=7845           ; UDP port; the host forwards it in the router
delay=4             ; frames of input delay, 2-15; the host's value is used. Internet: 3-6
server=$server          ; netplay-server host[:port]; when set, peer= is unused
key=$key          ; server: the server's key
name=$name          ; your name in the lobby (empty = MiSTer-xxxx)
file=               ; record/replay: empty = one file per game
EOF

cat > "$kit/README-netplay.txt" <<'EOF'
NES NETPLAY - GETTING STARTED

1. Unzip everything into the root of the SD card (where the _Console folder is).
   None of your own files is overwritten: the core is NES_netplay.rbf, the
   binary MiSTer_online, NetPong goes to games/NES/NetPong/.
   If you already have a netplay.ini, keep yours and change peer= or server= in it.

2. Scripts menu -> netplay_on. The MiSTer restarts with the netplay binary.
   Your normal binary is kept as MiSTer_offline; netplay_off brings it back.

3. Start NES_netplay (under Console). In the OSD:
     Advanced -> RAM Clear -> $00
     Netplay  -> Host on one MiSTer, Join on the other
     Save settings (at the bottom of the menu), or RAM Clear is lost at restart.

WITHOUT A SERVER (server= is empty in netplay.ini)
4. The host forwards UDP port 7845 in its router to the MiSTer.
   The join puts the host's address in /media/fat/netplay.ini: peer=...

5. Both load NetPong (games/NES/NetPong/NetPong.nes). The OSD shows
   "Netplay: connecting to host", then "Netplay: playing (delay 4)".
   The join plays the right paddle. SYNC at the bottom must be the same on
   both TVs.

WITH A SERVER (server= and key= are set in netplay.ini)
   No peer= and no port forwarding at the players.
   Open a room: OSD Netplay -> Host, load a game.
   Join: in the file browser, folder _Netplay/Rooms, open a room
     ("Sam - NetPong") and pick the game in it. Leave and re-open the folder
     to see new rooms.
   The server's games are in _Netplay/Server games (in RAM only).
   Set name= in netplay.ini to show your name in the room list.
   "playing with X (delay 4, direct)"   you play directly with each other
   "... through the server"             relayed by the server (a bit more lag)
   "cannot reach server"                wrong server=, or the server is not running
   "server: wrong key"                  key= does not match the server's
   "... (missing game)" in Rooms        you do not have that game (same md5)

Check: the files must have the md5 sums in md5sums.txt. Over ssh on the MiSTer:
  cd /media/fat && md5sum MiSTer_online _Console/NES_netplay.rbf
Always pass on the zip file, not loose files: some transfers (FTP in ASCII
mode, git) change line endings in binaries, and MiSTer_online then does not
start (black screen). To recover, put the SD card in a computer: delete
MiSTer, rename MiSTer_offline to MiSTer.

OSD errors:
  "Different ROM file"       you do not have the same game file
  "Different NES core build" you have different NES_netplay.rbf files
  "Set RAM Clear to $00..."  step 3
  no connection              the host's router must forward UDP 7845
EOF

(cd "$kit" && find . -type f ! -name md5sums.txt | sort | xargs md5sum > md5sums.txt)
(cd "$root/dist" && rm -f netplay-kit.zip && python3 -I -m zipfile -c netplay-kit.zip netplay-kit/*)
echo "dist/netplay-kit.zip ($(du -h "$root/dist/netplay-kit.zip" | cut -f1)), peer=${peer:-<empty>} server=${server:-<empty>} name=${name:-<default>}"
(cd "$kit" && find . -type f | sort)
