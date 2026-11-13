#!/usr/bin/env bash
# Builds dist/netplay-kit.zip for another MiSTer (a friend's): unzip it into
# the root of the SD card (/media/fat). Contains exactly the builds in this
# workspace, so both MiSTers run the same core, binary and NetPong ROM.
#
#   tools/make_kit.sh [host-address]
#   tools/make_kit.sh --server host[:port] --key KEY [--name NAME]
#   tools/make_kit.sh --keep-ini
#
# --keep-ini: the settings go in as netplay.ini.example, so a friend's own
# netplay.ini (with server= and key=) stays when the kit is unzipped over it.
# The arcade core (jtcores/release/mister/jtbubl.rbf, tools/jt_build.sh) goes in
# as _Arcade/cores/jtbubl-netplay.rbf with its MRA, when it is built.
#
# host-address goes into the kit's netplay.ini as peer= (the friend joins you).
# With --server the kit uses a netplay-server lobby (server/), no port
# forwarding at the players; key is the one in netplay-server.ini, name the
# friend's player name.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
peer="" server="" key="" name="" ini=netplay.ini
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-ini) ini=netplay.ini.example; shift ;;
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
srbf="$root/SNES_MiSTer/output_files/SNES.rbf"
grbf="$root/Gameboy2P_MiSTer/output_files/Gameboy.rbf"
bin="$root/Main_MiSTer/bin/MiSTer"
rom="$root/netpong/netpong.nes"

for f in "$rbf" "$srbf" "$grbf" "$bin" "$rom"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

rm -rf "$kit" "$root/dist/netplay-kit.zip"
mkdir -p "$kit/_Console" "$kit/Scripts" "$kit/games/NES/NetPong" "$kit/games/GAMEBOY2P"
cp "$rbf" "$kit/_Console/NES_netplay.rbf"
cp "$srbf" "$kit/_Console/SNES_netplay.rbf"
cp "$grbf" "$kit/_Console/GAMEBOY2P_netplay.rbf"
cp "$bin" "$kit/MiSTer_online"
cp "$root"/tools/mister-scripts/netplay_on.sh "$root"/tools/mister-scripts/netplay_off.sh "$kit/Scripts/"
cp "$rom" "$kit/games/NES/NetPong/NetPong.nes"
chmod +x "$kit/MiSTer_online" "$kit"/Scripts/*.sh
# GBA with the wireless adapter (SPEC.md 13), when it is built
gbarbf="$root/GBA_MiSTer/output_files/GBA.rbf"
if [ -f "$gbarbf" ]; then
  cp "$gbarbf" "$kit/_Console/GBA_netplay.rbf"
fi
# arcade (SPEC.md 12): next to Jotego's jtbubl.rbf, never over it
arbf="$root/jtcores/release/mister/jtbubl.rbf"
if [ -f "$arbf" ]; then
  mkdir -p "$kit/_Arcade/cores"
  cp "$arbf" "$kit/_Arcade/cores/jtbubl-netplay.rbf"
  cp "$root"/tools/arcade/*.mra "$kit/_Arcade/"
fi

cat > "$kit/$ini" <<EOF
; NES, SNES and Game Boy 2P netplay. The OSD option "Netplay" of NES_netplay, SNES_netplay and
; GAMEBOY2P_netplay picks Off/Host/Join;
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
NES, SNES, GAME BOY 2P AND ARCADE NETPLAY - GETTING STARTED

1. Unzip everything into the root of the SD card (where the _Console folder is).
   None of your own files is overwritten: the cores are NES_netplay.rbf,
   SNES_netplay.rbf and GAMEBOY2P_netplay.rbf, the binary MiSTer_online,
   NetPong goes to games/NES/NetPong/.
   If you already have a netplay.ini, keep yours and change peer= or server= in it.
   (A kit made with --keep-ini has netplay.ini.example instead: rename it to
   netplay.ini only if you have none.)

2. Scripts menu -> netplay_on. The MiSTer restarts with the netplay binary.
   Your normal binary is kept as MiSTer_offline; netplay_off brings it back.

3. Start NES_netplay (under Console). In the OSD:
     Advanced -> RAM Clear -> $00
     Netplay  -> Host on one MiSTer, Join on the other
     Save settings (at the bottom of the menu), or RAM Clear is lost at restart.

SNES: start SNES_netplay (under Console). OSD Netplay -> Host or Join, the
   same as NES; no other settings needed (both must have the same OSD settings).
   Games come from your own games/SNES folder (both need the same file) or from
   the server. Not supported: MSU-1, BS-X/Satellaview, games with a clock
   (S-RTC, SPC7110 RTC) and SPC music files.

GAME BOY 2P: start GAMEBOY2P_netplay (under Console). It runs two Game Boys
   linked by cable; the host plays Game Boy 1, the join Game Boy 2, and both
   screens are shown. Games go in games/GAMEBOY2P (.gb/.gbc). OSD Netplay ->
   Host or Join, then load a game (same file on both, same file extension).
   Two different games (e.g. two Pokemon versions): load game 1 with
   "Rom for second GB" Off, then set it On and load game 2; the join does the
   same, or opens the room in _Netplay/Rooms (both files are in it).
   Needs the SDRAM board. Not supported: MegaDuck (.bin).

ARCADE (Bubble Bobble): needs Bubble Bobble from the MiSTer updater
   (update_all), i.e. games/mame/bublbobl.zip; both players need the same zip.
   The netplay core is _Arcade/cores/jtbubl-netplay.rbf, next to the normal
   jtbubl.rbf, which stays as it is: the normal Bubble Bobble is not changed.
   Start "Bubble Bobble (US, Ver 5.1) [netplay]" in the Arcade list.
   Host: OSD Netplay -> Host. Join, with a server: in the game's OSD,
   "Join room", pick the room ("Sam - Bubble Bobble (US, Ver 5.1) [netplay]");
   the same rooms are in the Arcade list in the folder _Netplay. Or OSD
   Netplay -> Join: joins only when exactly one room with the game is open.
   The DIP switches are the host's during the session.

GBA WIRELESS ADAPTER (GBA_netplay): games that use Nintendo's GBA Wireless
   Adapter (Apotris, Pokemon FireRed/LeafGreen/Emerald, Mario Golf ...). Each
   MiSTer plays its own game, no picture sync. In GBA_netplay's OSD:
   Hardware -> Link Port: Wireless Adapter (then Reset), and Hardware ->
   Netplay: Host on one MiSTer, Join on the other, then load the game. In the
   game's wireless menu one hosts and the other joins, as on real GBAs.
   The two players may use different games that talk to each other
   (FireRed and LeafGreen). Savestates and rewind are off with the adapter on.
   Apotris, a free game with 2-player battles over the adapter, is by
   akouzoukos: download it from https://akouzoukos.com/apotris/downloads and
   put Apotris.gba in games/GBA (2 player battle -> wireless).

SWITCHING CORES: to go from NES_netplay to SNES_netplay (or back), reboot from
   the MiSTer's menu first and then start the other core. Jumping straight from
   one core to the other can leave netplay without the ROM reload at the start.

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
  cd /media/fat && md5sum MiSTer_online _Console/*_netplay.rbf _Arcade/cores/jtbubl-netplay.rbf
Always pass on the zip file, not loose files: some transfers (FTP in ASCII
mode, git) change line endings in binaries, and MiSTer_online then does not
start (black screen). To recover, put the SD card in a computer: delete
MiSTer, rename MiSTer_offline to MiSTer.

OSD errors:
  "Different ROM file"       you do not have the same game file
  "Different core build"     you have different *_netplay.rbf files
  "Different core settings"  set the same OSD options on both MiSTers
  "Set RAM Clear to $00..."  step 3 (NES)
  "Game chip not supported"  SNES: MSU-1, BS-X or a game with a clock
  "...runs another console"  you are in different cores (NES, SNES, Game Boy 2P, arcade)
  "Different ROM set (MRA or zip)"  arcade: not the same zip or MRA
  "Different core version (update both)"  arcade: different jtbubl-netplay.rbf
  no connection              the host's router must forward UDP 7845
EOF

(cd "$kit" && find . -type f ! -name md5sums.txt | sort | xargs -d '\n' md5sum > md5sums.txt)
(cd "$root/dist" && rm -f netplay-kit.zip && python3 -I -m zipfile -c netplay-kit.zip netplay-kit/*)
echo "dist/netplay-kit.zip ($(du -h "$root/dist/netplay-kit.zip" | cut -f1)), peer=${peer:-<empty>} server=${server:-<empty>} name=${name:-<default>}"
(cd "$kit" && find . -type f | sort)
