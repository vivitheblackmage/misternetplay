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

# the cores carry their build date, as MiSTer's own: NES_netplay_20261118.rbf
dated() { echo "$1_$(date -r "$2" +%Y%m%d).rbf"; }

rm -rf "$kit" "$root/dist/netplay-kit.zip"
mkdir -p "$kit/_Netplay" "$kit/Scripts" "$kit/games/NES/NetPong" "$kit/games/GAMEBOY2P"
cp "$rbf" "$kit/_Netplay/$(dated NES_netplay "$rbf")"
cp "$srbf" "$kit/_Netplay/$(dated SNES_netplay "$srbf")"
cp "$grbf" "$kit/_Netplay/$(dated GAMEBOY2P_netplay "$grbf")"
cp "$bin" "$kit/MiSTer_online"
cp "$root"/tools/mister-scripts/netplay_on.sh "$root"/tools/mister-scripts/netplay_off.sh "$kit/Scripts/"
mkdir -p "$kit/Scripts/.config/netplay"
cp "$root"/tools/mister-scripts/normal_main.py "$kit/Scripts/.config/netplay/"
cp "$rom" "$kit/games/NES/NetPong/NetPong.nes"
chmod +x "$kit/MiSTer_online" "$kit"/Scripts/*.sh
# GBA with the wireless adapter (SPEC.md 13), when it is built
gbarbf="$root/GBA_MiSTer/output_files/GBA.rbf"
if [ -f "$gbarbf" ]; then
  cp "$gbarbf" "$kit/_Netplay/$(dated GBA_netplay "$gbarbf")"
fi
# Neo Geo (SPEC.md 14), when it is built
neorbf="$root/NeoGeo_MiSTer/output_files/NeoGeo.rbf"
if [ -f "$neorbf" ]; then
  cp "$neorbf" "$kit/_Netplay/$(dated NeoGeo_netplay "$neorbf")"
fi
# arcade (SPEC.md 12): next to Jotego's jtbubl.rbf, never over it
arbf="$root/jtcores/release/mister/jtbubl.rbf"
if [ -f "$arbf" ]; then
  mkdir -p "$kit/_Arcade/cores"
  cp "$arbf" "$kit/_Arcade/cores/$(dated jtbubl-netplay "$arbf")"
  cp "$root"/tools/arcade/*.mra "$kit/_Arcade/"
fi

# ao486 with the network card (SPEC.md 15), when it is built: next to the
# normal ao486 core; the DOS kit floppy (tools/ao486/dos/netplay/build.sh, which
# make_release.sh runs into dist/ao486-dos) and the Scripts that put its menu
# on all DOS disks
aorbf="$root/ao486_MiSTer/output_files/ao486.rbf"
aoimg="$root/dist/ao486-dos/NETPLAY.IMG"
if [ -f "$aorbf" ]; then
  [ -f "$aoimg" ] || { echo "missing $aoimg: tools/ao486/dos/netplay/build.sh dist/ao486-dos"; exit 1; }
  mkdir -p "$kit/games/AO486"
  cp "$aorbf" "$kit/_Netplay/$(dated ao486_netplay "$aorbf")"
  cp "$aoimg" "$kit/games/AO486/NETPLAY.IMG"
  cp "$root"/tools/mister-scripts/ao486_netplay_install.sh "$root"/tools/mister-scripts/ao486_netplay_uninstall.sh "$kit/Scripts/"
  chmod +x "$kit"/Scripts/*.sh
fi

cat > "$kit/$ini" <<EOF
; NES, SNES, Game Boy 2P, GBA, Neo Geo, arcade and ao486 netplay. The OSD option "Netplay"
; of the *_netplay cores picks Off/Host/Join;
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
NES, SNES, GAME BOY 2P, GBA, NEO GEO, ARCADE AND AO486 NETPLAY - GETTING STARTED

1. Unzip everything into the root of the SD card (where the _Console folder is).
   None of your own files is overwritten: the netplay cores are in their own
   folder, _Netplay (NES_netplay, SNES_netplay, GAMEBOY2P_netplay, GBA_netplay,
   NeoGeo_netplay and ao486_netplay, each with its build date, as
   NES_netplay_20261118.rbf), shown as "Netplay" in the MiSTer's main menu;
   the binary is MiSTer_online,
   NetPong goes to games/NES/NetPong/.
   From v0.6 or older: netplay_on (step 2) removes the old copies in _Console
   and _Computer, and older versions in _Netplay. Without that, game shortcuts (MGL files, MiSTer_SAM) would
   start the netplay core instead of your normal one.
   If you already have a netplay.ini, keep yours and change peer= or server= in it.
   (A kit made with --keep-ini has netplay.ini.example instead: rename it to
   netplay.ini only if you have none.)

2. Scripts menu -> netplay_on. The MiSTer restarts with the netplay binary.
   Your normal binary is kept as MiSTer_offline; netplay_off brings it back.
   If an older netplay_on (before v0.5) saved a netplay binary there instead,
   netplay_on and netplay_off fetch the official binary from the MiSTer
   database (checked against its MD5) and put it there; the MiSTer needs the
   network for that.

3. Start NES_netplay (under Netplay). In the OSD:
     Advanced -> RAM Clear -> $00
     Netplay  -> Host on one MiSTer, Join on the other
     Save settings (at the bottom of the menu), or RAM Clear is lost at restart.

SNES: start SNES_netplay (under Netplay). OSD Netplay -> Host or Join, the
   same as NES; no other settings needed (both must have the same OSD settings).
   Games come from your own games/SNES folder (both need the same file) or from
   the server. Not supported: MSU-1, BS-X/Satellaview, games with a clock
   (S-RTC, SPC7110 RTC) and SPC music files.

GAME BOY 2P: start GAMEBOY2P_netplay (under Netplay). It runs two Game Boys
   linked by cable; the host plays Game Boy 1, the join Game Boy 2, and both
   screens are shown. Games go in games/GAMEBOY2P (.gb/.gbc). OSD Netplay ->
   Host or Join, then load a game (same file on both, same file extension).
   Two different games (e.g. two Pokemon versions): load game 1 with
   "Rom for second GB" Off, then set it On and load game 2; the join does the
   same, or opens the room in _Netplay/Rooms (both files are in it).
   Needs the SDRAM board. Not supported: MegaDuck (.bin).

NEO GEO (NeoGeo_netplay): the MiSTer Neo Geo core with netplay, cartridge
   games in Console (AES) mode. It goes next to the normal NeoGeo core, which
   is not changed. Both MiSTers need the same BIOS files in games/NeoGeo
   (uni-bios.rom or neo-epo.sp1, sfix.sfix, 000-lo.lo) and the same game. A
   game matches by its program, so a Darksoft folder, a MAME zip and a .neo
   file of the same game find each other.
   Start NeoGeo_netplay on both with the same System Type (Console), BIOS and
   Video Mode settings. OSD Netplay -> Host on one MiSTer, Join on the other,
   then both load the game. With a server, Join takes the open room with that
   game; without one, peer= as below. If a game was played in the core before,
   the core loads itself again first and the game follows by itself. With
   Netplay on, the BIOS screen shows only once a game is loaded.
   The memory card, multitap, spinner and mouse are off during a session.
   Not supported: Neo Geo CD.

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

AO486 (PC) NETWORK GAMES (_Netplay/ao486_netplay.rbf): the MiSTer ao486 core
   with an NE2000 network card. Up to eight MiSTers in a room share a small
   network, so DOS games with IPX network play see each other as on a LAN:
   Doom, Duke Nukem 3D, Warcraft II, Command & Conquer, Blood ... Each MiSTer
   runs its own PC; only the network frames cross (no lockstep).
   Once: Scripts menu -> ao486_netplay_install (with the ao486 core closed).
   It puts the network game menu on every DOS hard disk in games/AO486, from
   games/AO486/NETPLAY.IMG; Windows 95/98 disks are skipped.
   ao486_netplay_uninstall takes it off again.
   It also copies your DOS game shortcuts (MGL files that start the ao486
   core with a disk, such as _DOS Games) to Netplay -> DOS Games, where they
   start ao486_netplay; your own shortcuts still start the normal core.
   Play: start a game from Netplay -> DOS Games (or ao486_netplay with a
   game disk). OSD, Hardware page: Netplay ->
   Host on one MiSTer, Join on the others (this turns Network On too), then
   OSD Reset. At "How do you want to play?" press 1 (Online): the drivers
   load and the menu shows the network games on that disk and who is in the
   room. Pick the game and start it; the others press J to follow with the
   same settings. Single player starts by itself after 10 seconds.
   More than two players need the server (ao486 rooms of up to eight); with
   peer= two MiSTers play directly. More in games/AO486/NETPLAY.IMG
   (README.TXT on the floppy).

SWITCHING CORES: to go from one netplay core to another (NES_netplay to
   SNES_netplay, say), reboot from
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
  cd /media/fat && md5sum MiSTer_online _Netplay/*_netplay_*.rbf _Arcade/cores/jtbubl-netplay_*.rbf
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
  "...runs another console"  you are in different cores (NES, SNES, Game Boy 2P, Neo Geo, arcade)
  "Different ROM set (MRA or zip)"  arcade: not the same zip or MRA
  "Different ROM set"        Neo Geo: not the same game (program)
  "Different BIOS files"     Neo Geo: not the same uni-bios.rom/sp1, sfix.sfix, 000-lo.lo
  "Different core version (update both)"  arcade: different jtbubl-netplay.rbf
  no connection              the host's router must forward UDP 7845
EOF

(cd "$kit" && find . -type f ! -name md5sums.txt | sort | xargs -d '\n' md5sum > md5sums.txt)
(cd "$root/dist" && rm -f netplay-kit.zip && python3 -I -m zipfile -c netplay-kit.zip netplay-kit/*)
echo "dist/netplay-kit.zip ($(du -h "$root/dist/netplay-kit.zip" | cut -f1)), peer=${peer:-<empty>} server=${server:-<empty>} name=${name:-<default>}"
(cd "$kit" && find . -type f | sort)
