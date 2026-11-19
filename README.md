# NES, SNES, Game Boy, GBA, Neo Geo, arcade and PC (ao486) netplay for MiSTer

Play NES, Super NES, Game Boy link-cable games, Neo Geo (AES) and Bubble Bobble (arcade)
together on two [MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki) boards over the
internet or a LAN. Both MiSTers run the real core in lockstep: each frame's controller input is sent to the other side, and both
run exactly the same frames with the same input. A checksum of the game state
is compared all the time, so a desync stops the session instead of going on
silently.

GBA games that use Nintendo's **GBA Wireless Adapter** work differently: each
MiSTer runs its own game, and the adapter is emulated, so the two GBAs talk to
each other over the internet as they would over the air.

The **ao486** PC core gets a network card instead: up to eight MiSTers in a
room share one small network, so DOS games with network play (Doom, Duke
Nukem 3D, Warcraft II, Command & Conquer, Blood ...) see each other as on a
LAN. Each MiSTer runs its own PC, and only the network frames cross. A menu
on the PC's hard disk loads the network drivers and starts the games with the
right settings.

It comes in these parts:

- **NES core** (`NES_netplay.rbf`) and **SNES core** (`SNES_netplay.rbf`): the
  MiSTer NES and SNES cores with a netplay module added to the FPGA design.
- **Game Boy 2P core** (`GAMEBOY2P_netplay.rbf`): a core with two Game Boys
  joined by a link cable inside the FPGA, with the same netplay module. Each
  MiSTer runs both Game Boys; the host plays Game Boy 1, the other player Game
  Boy 2, so link-cable games (Tetris, Tennis, Dr. Mario, trading and battles)
  work over the network.
- **Neo Geo core** (`NeoGeo_netplay.rbf`): the MiSTer Neo Geo core with the
  netplay module, for cartridge games in Console (AES) mode. Both CPUs (68000
  and Z80) were made to run exactly alike on any two MiSTers; the changes are
  in SPEC.md section 14.
- **Arcade core** (`jtbubl-netplay.rbf`, Bubble Bobble): Jotego's jtbubl core
  with the netplay module added to his jtframe framework, so other jtframe
  arcade cores can follow. It goes next to the normal `jtbubl.rbf`, which stays
  as it is, and is started from its own MRA,
  `Bubble Bobble (US, Ver 5.1) [netplay]`.
- **GBA core** (`GBA_netplay.rbf`): the MiSTer GBA core with an emulated GBA
  Wireless Adapter on the link port, for Apotris, Pokémon FireRed, LeafGreen
  and Emerald, and other games that use the adapter. The adapter's commands
  are answered by the Main binary (ported from gpSP's adapter emulation), and
  its packets travel between the two MiSTers.
- **ao486 core** (`ao486_netplay.rbf`): the MiSTer ao486
  core with an NE2000 network card (from ao486_MiSTer pull request #238 by
  georgemog, not merged upstream). The card's frames go to the room, or to the
  MiSTer's own network (DHCP and internet from DOS).
- **ao486 DOS kit** (`games/AO486/NETPLAY.IMG`, a floppy image): the network
  game menu (`NPMENU`), our IPX driver (`NPIPX`) and the Crynwr NE2000 packet
  driver. A script in the MiSTer's Scripts menu puts the menu on every DOS
  hard disk at once; with the network on, the PC then asks at boot: online or
  single player.
- **Main binary** (`MiSTer_online`): the MiSTer main program (menu, file
  browser, input) with the netplay engine and the UDP networking added. Your
  normal MiSTer binary is kept, and you can switch back from the Scripts menu.
- **netplay-server** (optional): a small lobby and relay server for Windows,
  Linux and Raspberry Pi. With it, players need no port forwarding: a host
  opens a room, and the others see it in the MiSTer's file browser and join by
  picking it. The MiSTers then connect directly to each other (UDP hole
  punching) and fall back to relaying through the server when that is not
  possible.

This is an unofficial modification. It is not part of, or endorsed by, the
MiSTer-devel project.

## Tested

- Two MiSTers playing over the internet, both directly (port forwarding) and
  through the lobby server, with the server running on Windows 10. SNES between
  a DE10-Nano and a MiSTer Pi, among others Contra III, Street Fighter II and
  Super Mario Kart.
- Games stay in sync: recorded and replayed frame by frame with identical
  results over 38,000+ frames each on NROM, MMC1, MMC3, MMC5 and UNROM games
  (Super Mario Bros., The Legend of Zelda, Super Mario Bros. 3, Castlevania III,
  Gun.Smoke).
- SNES, recorded and replayed the same way over 37,000+ frames each: Super Mario
  World (LoROM), Donkey Kong Country (HiROM), Kirby Super Star (SA-1), Yoshi's
  Island (Super FX 2) and Pilotwings (DSP-1).
- The whole SNES core in simulation (Verilator): stopping and restarting its
  clock changes no output on any cycle, two simulated MiSTers stay in sync, and
  a game started after another one runs exactly as on a freshly loaded core.
- Game Boy 2P on hardware: a Tetris link match between two MiSTers through the
  lobby server; Tennis with clean sound at full speed. In simulation
  (Verilator): two simulated MiSTers stay in sync over 1,800 frames of a Tetris
  link match, and also when one of them ran another game first; the test ROMs dmg-acid2, cgb-acid2,
  instr_timing and cpu_instrs pass.
- Bubble Bobble on hardware: two MiSTers over the internet through the lobby
  server (on a Raspberry Pi), 33 levels in 20 minutes without a desync, and
  without picture glitches. In simulation (Verilator): the whole jtbubl core on
  two simulated MiSTers stays in sync, with the same order of every clock
  enable, and a changed input is caught as a desync in the frame it happens.
- Neo Geo on hardware: two MiSTers over the internet through the lobby server,
  nine sessions with different games and no desync (among them Over Top, Double Dragon,
  Pulstar, Art of Fighting, Shock Troopers 2nd Squad and Aero Fighters 3), and
  a recorded Neo Turf Masters session replayed with identical results over
  9,000 frames. In simulation (Verilator): the whole core makes the same writes
  with both CPUs, at the same clocks, in every frame, with the DDR3's timing,
  the clock phase, the start and the input's arrival all varied.
- GBA Wireless Adapter on hardware: two MiSTers over the internet through the
  lobby server (on a Raspberry Pi), Pokémon FireRed/LeafGreen battles and a
  trade in the Union Room, and gba-link-connection's `LinkUniversal_stress` test ROM
  (packet loss and packet sync: 65,534 packets without a loss). In simulation:
  the core's serial port and adapter against Pokémon's own wireless library
  (librfu), with the Main binary's answers late and out of order.
- ao486 on hardware: Doom between two MiSTers over the internet through the
  lobby server (on a Raspberry Pi), with our IPX driver; the boot question,
  the game menu and its uninstall; DHCP and ping from DOS on the MiSTer's own
  network. Rooms of three to eight players and the direct link without a
  server so far only in the automated tests (three Main programs through a
  real server). The DOS kit in QEMU: two PCs see each other in the menu's room
  and start a game with the same settings; Doom reaches its first level with
  two players.
- Automated tests for the core (Verilator testbench) and for the netplay engine,
  host and join over real UDP, with and without the server.

## Where the cores and the Main binary come from

Both are the official MiSTer-devel projects. This repository does not copy
them; it holds our changes as patches on top of exact upstream commits:

| Part | Upstream repository | Base commit | Our changes |
| --- | --- | --- | --- |
| NES core (FPGA) | [github.com/MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer) | `49a0a66` (2026-09-30) | [`patches/NES_MiSTer/`](patches/NES_MiSTer) |
| SNES core (FPGA) | [github.com/MiSTer-devel/SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer) | `4c2b746` (2026-10-31) | [`patches/SNES_MiSTer/`](patches/SNES_MiSTer) |
| Game Boy 2P core (FPGA) | [github.com/pomstazlesa/Gameboy2PUW_MiSTer](https://github.com/pomstazlesa/Gameboy2PUW_MiSTer) (branch `Gameboy2P`) | `83e167f` (2025-10-05) | [`patches/Gameboy2P_MiSTer/`](patches/Gameboy2P_MiSTer) |
| GBA core (FPGA) | [github.com/MiSTer-devel/GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer) | `93790a0` | [`patches/GBA_MiSTer/`](patches/GBA_MiSTer) |
| Neo Geo core (FPGA) | [github.com/MiSTer-devel/NeoGeo_MiSTer](https://github.com/MiSTer-devel/NeoGeo_MiSTer) | `ffaab14` | [`patches/NeoGeo_MiSTer/`](patches/NeoGeo_MiSTer) |
| ao486 core (FPGA) | [github.com/MiSTer-devel/ao486_MiSTer](https://github.com/MiSTer-devel/ao486_MiSTer) | `628ddbc` | [`patches/ao486_MiSTer/`](patches/ao486_MiSTer) (the first is pull request #238's NE2000 card by georgemog) |
| Arcade core (FPGA) | [github.com/jotego/jtcores](https://github.com/jotego/jtcores) (jtbubl and jtframe) | `15d60ca` (2026-10-23) | [`patches/jtcores/`](patches/jtcores) |
| Main binary (ARM) | [github.com/MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | `0827165` (2026-10-30) | [`patches/Main_MiSTer/`](patches/Main_MiSTer) |

The NES, SNES, GBA, Neo Geo and ao486 cores are the work of the MiSTer-devel contributors and of the
authors credited in their own READMEs; Main_MiSTer likewise. The Game Boy 2P
core is pomstazlesa's two-player fork of the MiSTer-devel Game Boy core. The
arcade core and jtframe are Jotego's (jtcores). All are licensed GPL-3.0, and
so are our patches. The ao486 network card itself (the NE2000 in the FPGA and
its shared-memory window) is georgemog's, from ao486_MiSTer pull request #238
(not merged upstream), built on apolkosnik's RTL8019AS core from
Minimig-AGA_MiSTer. We took it as it is and fixed what the hardware showed
(an OSD bit it shared with Low-Res, the MAC address after a reset, the
transmit ring on the ARM side), and added the rooms and the DOS side; the
release notes for v0.7 list it.

`./setup.sh` clones the eight upstream repositories next to it and applies the
patches on a branch called `netplay`.

Everything else here is our own: the lobby server (`server/`), the tools
(`tools/`), the NetPong test game (`netpong/`) and the ao486 DOS kit's menu and
IPX driver (`tools/ao486/dos/netplay`). The DOS kit also carries the Crynwr
NE2000 packet driver (GPL-1.0, its source in `tools/ao486/dos/crynwr`). The Quartus Docker setup in
`tools/quartus-docker/` is based on
[ebraminio/mister-docker-build](https://github.com/ebraminio/mister-docker-build) (MIT).

### Where the GBA Wireless Adapter comes from

The adapter is not our invention; it stands on the work of others:

- **gpSP** by David Guillen Fandos (davidgfnet),
  [github.com/libretro/gpsp](https://github.com/libretro/gpsp), GPL-2.0-or-later.
  Its adapter emulation (`rfu.c`) is the base of the Main binary's adapter
  (`support/netplay/rfu.cpp`, ported with its copyright notice: the command
  handling, the packets between adapters and the timeouts), and its link port
  (`serial.c`) is the model for the core's serial port in Normal mode and the
  SI/SO handshake.
- **gba-link-connection** by afska,
  [github.com/afska/gba-link-connection](https://github.com/afska/gba-link-connection):
  the adapter's protocol as documented by afska and davidgfnet
  ([`docs/wireless_adapter.md`](https://github.com/afska/gba-link-connection/blob/master/docs/wireless_adapter.md)),
  and its `LinkUniversal_stress` test ROM, which we test against.
- **pret/pokefirered** ([github.com/pret/pokefirered](https://github.com/pret/pokefirered)):
  the decompiled librfu showed how Pokémon drives the adapter (its timers and
  handshakes). The core's serial test bench imitates that behaviour; no code
  is copied from it.

What is ours: the core's side (`gba_rfu.sv`: the handshake, the command words
and a mailbox to the ARM), the link between two MiSTers (`rfu_link.cpp`:
reliable, ordered packets over UDP, directly or through the server), the
pairing through the lobby, and the fixes Pokémon needed over the internet
(SPEC.md section 13).

## What you need

| | Needed |
| --- | --- |
| MiSTer | Two MiSTers (DE10-Nano) with SDRAM, a network connection (Ethernet is best) and the current MiSTer Linux. Tested on kernel `6.18.38-MiSTer` (glibc 2.31). `MiSTer_online` needs glibc 2.29 or newer, so a MiSTer kept up to date with the official updater (`update_all` or `downloader`) is fine. Check with `uname -r` over ssh. |
| Game | The same ROM file on both MiSTers (same md5), or the server's copy. NetPong, a free two-player NES test game, is included. Game Boy 2P needs the SDRAM board, as the original core. Bubble Bobble: the ROM set the MiSTer updater installs for Jotego's core (`games/mame/bublbobl.zip`), the same on both MiSTers; arcade games never come from the server. Neo Geo: the same game and the same BIOS files (`uni-bios.rom` or `neo-epo.sp1`, `sfix.sfix`, `000-lo.lo`) on both; Neo Geo games never come from the server either. |
| ao486 | DOS hard disk images in `games/AO486` (the ready-made ones work: the menu goes in front of their own game start). The game itself on that disk, with its network play: DOS games with IPX. More than two players need the server. |
| Server (optional) | Windows 10/11, or Linux on x86-64, ARM64 or ARMv7, such as Raspberry Pi OS (32- or 64-bit), Debian or Ubuntu. The binaries have no dependencies; the installer needs systemd (without it, run the binary by hand). Tested on Windows 10; Linux x86-64 in the automated tests. One forwarded port (7845, UDP and TCP) on the server's router. |
| Building (developers) | Linux, tested on Ubuntu 24.04 (also in WSL2 on Windows 10). Docker for Quartus Prime Lite 17.0.2, Verilator 5, g++, Python 3, Go 1.22 (or Docker). See [Building](#building). |

## Installing on the MiSTer

Download `mister-netplay-<version>.zip` from the releases and unzip it on a
computer. Then on **each** MiSTer:

1. Copy everything in the folder `SD card` to the root of the MiSTer's SD card
   (where `_Console` is), over the network share or with the card in a
   computer. None of your files is overwritten:
   - `_Netplay/`: the netplay cores in their own folder, shown as **Netplay**
     in the MiSTer's main menu: `NES_netplay`, `SNES_netplay`,
     `GAMEBOY2P_netplay`, `GBA_netplay`, `NeoGeo_netplay` and `ao486_netplay`,
     each with its build date as MiSTer's own cores have it
     (`NES_netplay_20261118.rbf`). Your normal cores are not changed.
   - `_Arcade/cores/jtbubl-netplay_<date>.rbf` and
     `_Arcade/Bubble Bobble (US, Ver 5.1) [netplay].mra`: the arcade core and
     its MRA, next to Jotego's (which are not changed)
   - `MiSTer_online`: the netplay main binary
   - `Scripts/netplay_on.sh`, `Scripts/netplay_off.sh` (with
     `Scripts/.config/netplay/normal_main.py`),
     `Scripts/ao486_netplay_install.sh`, `Scripts/ao486_netplay_uninstall.sh`
   - `games/AO486/NETPLAY.IMG`: the ao486 DOS kit
   - `netplay.ini`: the settings (keep yours if you already have one)
   - `games/NES/NetPong/NetPong.nes`
2. On the MiSTer: **Scripts → netplay_on**. Your binary is saved as
   `MiSTer_offline`, `MiSTer_online` becomes `MiSTer`, and the MiSTer
   reboots. **Scripts → netplay_off** switches back. If an older netplay_on
   (before v0.5) saved a netplay binary as `MiSTer_offline`, netplay_on and
   netplay_off fetch the official binary from the MiSTer database (checked
   against its MD5) and put it there; the MiSTer needs the network for that.
   netplay_on also removes
   older netplay cores: see [Updating from v0.6 or older](#updating-from-v06-or-older).
3. NES: start **Netplay → NES_netplay**. In the OSD: **Advanced → RAM Clear → $00**,
   then **Save settings** at the bottom of the menu (both players need the
   same settings).
4. SNES: start **Netplay → SNES_netplay**. Nothing to set up; both players need
   the same OSD settings.
5. Game Boy 2P: start **Netplay → GAMEBOY2P_netplay**. Put the games
   (`.gb`, `.gbc`) in `games/GAMEBOY2P`. Nothing to set up.
6. Arcade: start **Arcade → Bubble Bobble (US, Ver 5.1) [netplay]**. Nothing
   to set up; the DIP switches are the host's during a session.
7. GBA: start **Netplay → GBA_netplay**. In the OSD: **Hardware → Link Port →
   Wireless Adapter**. See [GBA Wireless Adapter](#gba-wireless-adapter).
8. Neo Geo: start **Netplay → NeoGeo_netplay** with **System Type → Console
   (AES)**. See [Neo Geo](#neo-geo).
9. ao486: **Scripts → ao486_netplay_install** once (with the ao486 core
   closed). See [ao486 (PC)](#ao486-pc).

### Updating from v0.6 or older

Up to v0.6 the netplay cores went into `_Console` (`NES_netplay.rbf` next to
`NES_20260823.rbf`). That has a side effect: a game shortcut (an `.mgl` file,
MiSTer_SAM, a favourite) names its core without the date, `_Console/NES`, and
the MiSTer then takes the file whose name sorts last, which is
`NES_netplay.rbf`. Such shortcuts started the netplay core instead of your
normal one. Starting a core from the menu was never affected.

Since v0.7 the cores are in `_Netplay`, where no shortcut to `_Console` finds
them. After copying the new `SD card` folder, run **Scripts → netplay_on**: it
removes the old `_Console/NES_netplay.rbf`, `SNES_netplay.rbf`,
`GAMEBOY2P_netplay.rbf`, `GBA_netplay.rbf`, `NeoGeo_netplay.rbf` (and
`_Computer/ao486_netplay.rbf` from a test kit) once their new copy is in
`_Netplay`, older versions in `_Netplay`, and `_Arcade/cores/jtbubl-netplay.rbf`.

If you stay on v0.6 or older for now, delete those files in `_Console` by hand
when you are not using netplay, or rename them so they do not start with the
core's name (for example `Netplay-NES.rbf`); netplay works the same with any
file name.

**Switching between the netplay cores:** reboot from the MiSTer's menu first,
then start the other core. Jumping straight from one core to the
other can leave netplay without the ROM reload at the start of a session.

### Playing directly (no server)

- The host forwards **UDP port 7845** in its router to its MiSTer, then picks
  **Netplay → Host** in the OSD (NES_netplay, SNES_netplay,
  GAMEBOY2P_netplay, GBA_netplay or NeoGeo_netplay) and loads a game.
- The other player puts the host's address in `/media/fat/netplay.ini`
  (`peer=<address>`), picks **Netplay → Join** and loads the same game.
- The OSD shows `Netplay: playing (delay 4)`. Player 1 is the host.

### Playing through a server

Start the server (below), then on each MiSTer set in `/media/fat/netplay.ini`:

```ini
[netplay]
server=myserver.example.net:7845
key=<the key from netplay-server.ini>
name=Alex            ; your name in the room list, at most 16 characters
delay=4
```

- **Open a room:** OSD **Netplay → Host**, load a game.
- **Join:** in the file browser open **_Netplay/Rooms**, open a room
  (`Alex - NetPong`) and pick the game in it. Leave and re-open the folder to
  see new rooms. The server's own games are in **_Netplay/Server games**.
  Rooms and games are per core: SNES rooms show in SNES_netplay only.
- **Join without picking a room:** OSD **Netplay → Join** and load the game.
  This joins only when exactly one room with that game is open; with more the
  OSD says `2 rooms with this game: pick one`. Note: with `mode=join` in
  `netplay.ini` (or the OSD on Join) this happens on every game load; keep
  `mode=off` and the OSD on `netplay.ini` to pick rooms yourself.
- The OSD says `playing with Alex (delay 4, direct)` or `... through the server`.

All settings are described in [`tools/netplay.ini.example`](tools/netplay.ini.example).

### Game Boy 2P

- The host plays Game Boy 1, the other player Game Boy 2; the link cable
  between them is inside the core, so its timing never meets the network.
- **One game for both** (Tetris, Tennis, Dr. Mario): both load the same file
  (same file extension too: `.gb` and `.gbc` start the Game Boy in different
  modes).
- **Two different games** (for example two Pokémon versions): load game 1 with
  **Rom for second GB** Off, then switch it On and load game 2. The other
  player does the same, or opens the room in **_Netplay/Rooms**, where both
  files are.
- **Show → My screen** shows only your own Game Boy, in the middle of the
  screen; **Both screens** shows both. **Audio select → Own GB** (the default)
  plays your own Game Boy's sound.
- Battery saves work as on NES: both players need the same `.sav` file, or
  none. Playing with each player's own save is planned for a later version.
- Not supported: MegaDuck games (`.bin`). OSD reset, *Reload Backup RAM* and
  *Sync Video* are off during netplay.

### Neo Geo

- Both start **NeoGeo_netplay** with the same **System Type** (Console),
  **BIOS** and **Video Mode** settings, and the same BIOS files in
  `games/NeoGeo` (`uni-bios.rom`, or `neo-epo.sp1` with BIOS Original;
  `sfix.sfix`, `000-lo.lo`). The BIOS files are checked.
- One picks **Netplay → Host**, the other **Join**, and both load the same
  game. With a server, Join takes the open room with that game; without one,
  `peer=` as above. There is no room folder for Neo Geo.
- A game matches by its program and sound CPU ROM, not by its files: the same
  game from a Darksoft folder, a MAME zip or a `.neo` file finds the other
  player's room.
- A session needs a freshly started machine. If a game was played in the core
  before, the core loads itself again first, and the game follows by itself.
  With Netplay on, the core starts only once a game is loaded, so there is no
  BIOS screen before that.
- The memory card, multitap, spinner and mouse are off during a session.
  Not supported: Neo Geo CD.

### Arcade (Bubble Bobble)

- Start **Bubble Bobble (US, Ver 5.1) [netplay]** in the Arcade list on both
  MiSTers. The host is player 1.
- **Host:** OSD **Netplay → Host**.
- **Join with a server:** in the game's OSD, **Join room**, and pick the room
  (`Alex - Bubble Bobble (US, Ver 5.1) [netplay]`); the game is not reloaded.
  The same rooms are in the Arcade list, folder **_Netplay**, also from the
  main menu before any core is loaded. Or **Netplay → Join** (exactly one open
  room, as above).
- **Join without a server:** `peer=` in `netplay.ini`, then **Netplay → Join**.
- Both need the same ROM set (checked) and the same core. The host's DIP
  switches are used during the session; yours come back afterwards. The RAM is
  cleared at the start of a session, so high scores from before do not count.
- Pause, test and service switches are off during netplay. While the game waits
  for the other player's input, HDMI repeats the last picture; analog video
  may flicker for that moment.

### GBA Wireless Adapter

- Both start **GBA_netplay** with **Hardware → Link Port → Wireless Adapter**.
- One picks **Hardware → Netplay → Host**, the other **Join**, and both load
  their game. With a server, Join finds the open GBA room by itself; without
  one, `peer=` as above. The OSD says `wireless adapter linked with Alex`.
- Then play as on real GBAs: in the game's own wireless menu one player hosts
  and the other joins ([Apotris](https://akouzoukos.com/apotris/downloads), a
  free game by akouzoukos: 2 player battle → wireless; Pokémon: the Union
  Room or the wireless club).
- The two players may run different games that talk to each other, such as
  Pokémon FireRed and LeafGreen.
- No lockstep and no desync check here: each GBA runs at its own speed, and
  the network only delays the packets. Round trips over the internet add to
  what the game sees as the adapter's delay.
- Loading the game again keeps the room, and the other player's MiSTer
  follows. If the host loads the core again, the other player loads their game
  again too.
- Savestates and rewind are off while the adapter is on. Two players for now
  (the adapter itself allows five). Wireless multiboot (playing with one
  cartridge) is not supported.

### ao486 (PC)

- **Once:** Scripts → **ao486_netplay_install**, with the ao486 core closed.
  It puts the network game menu on every DOS hard disk image in
  `games/AO486` (from `games/AO486/NETPLAY.IMG`): `C:\NETPLAY`, `C:\NP.BAT` and
  two lines in `C:\AUTOEXEC.BAT` (the old one is kept as `C:\AUTOEXEC.NPB`).
  Windows 95/98 disks, disks without DOS and CD images are left alone. Run it
  again after an update. **ao486_netplay_uninstall** takes it off all disks;
  changes you made to `AUTOEXEC.BAT` since stay. The script also copies your
  DOS game shortcuts (`.mgl` files that start the ao486 core with one of those
  disks, such as the ready-made `_DOS Games`) to **Netplay → DOS Games**, where
  they start `ao486_netplay`; the originals keep the normal ao486 core. One
  disk by hand: mount `NETPLAY.IMG` as floppy A: and type `A:\INSTALL`
  (`A:\UNINSTALL`).
- **Play:** start the game from **Netplay → DOS Games** (or **Netplay →
  ao486_netplay** with a game disk). OSD,
  Hardware page: **Netplay → Host** on one MiSTer and **Join** on the others
  (this turns **Network** on too), then **Reset**. The OSD says
  `Netplay: network linked with the room`, and `Netplay: 3 in the room: ...`
  as players come.
- At **How do you want to play?** press **1** (Online): the drivers load and
  the menu shows the network games on that disk and who is in the room. Pick
  the game: games with an IPX starter (Doom, Heretic) take the players, mode
  and skill in the menu; the others start and show how their own menus set up
  network play. The others press **J** to follow with the same settings.
  **2**, or no key for 10 seconds, starts the disk as usual without drivers.
  With Network off nothing is asked.
- **Players:** with a server, up to eight in a room, all through the server
  (the server passes the frames on like a network switch). Without one,
  `peer=` as above, two players directly.
- The menu finds a game by its files (`GAMES.INI` on the disk, add your own).
  Each ready-made disk holds one game, so the menu shows that one as ready.
  Doom needs id's `DOOM.EXE`/`DOOM2.EXE` and `IPXSETUP.EXE`; FastDoom has no
  network play. The ao486 has no maths coprocessor, so Quake does not run.
- **Netplay → Off** with **Network → On** puts the card on the MiSTer's own
  network instead (NE2000 Mode Shared needs an Ethernet cable): DHCP and the
  internet from DOS with a packet driver and mTCP.

## Running the server

- **Windows:** double-click `netplay-server.exe`.
- **Raspberry Pi / Linux:** copy the `Server` folder from the release zip to
  the machine and run `sudo sh install-linux.sh`. It picks the right binary,
  installs it as a service that starts at boot, and prints the key.

The first start writes `netplay-server.ini` with a random key. Forward port
**7845, UDP and TCP**, to that computer. Open rooms show in a browser at
`http://<server>:7845/` (no key needed; `public_page=no` in `netplay-server.ini` asks for `?key=`). The server's games go in `roms/NES` (or
`roms` itself), `roms/SNES` and `roms/GB`. Details: [`server/README.md`](server/README.md).

## Troubleshooting

### Black screen after netplay_on

The MiSTer boots, but the screen stays black and there is no menu. The new
`MiSTer_online` did not start. Two known causes:

1. **The file was damaged on the way.** Copying with FTP in ASCII mode (for
   example FileZilla with files without an extension), or through git with line
   ending conversion, changes bytes in the binary. Check it over ssh:

   ```sh
   md5sum /media/fat/MiSTer_online
   ```

   It must match `md5sums.txt` in the release. Copy the files again from the
   zip, in binary mode (FileZilla: *Transfer → Transfer type → Binary*), or
   through the Samba share or the SD card.
2. **The MiSTer's Linux is too old** (glibc older than 2.29). Update the
   MiSTer with `update_all` or `downloader` first.

**Getting the menu back:**
- Over ssh (user `root`, password `1`): `cd /media/fat && cp MiSTer_offline MiSTer && reboot`
- Or with the SD card in a computer: delete `MiSTer` and rename
  `MiSTer_offline` to `MiSTer`.

### OSD messages

| Message | Meaning |
| --- | --- |
| `Different ROM file` | the two players do not have the same game file (md5) |
| `Different core build` | different netplay cores (`NES_netplay`, `SNES_netplay`, `GAMEBOY2P_netplay` ...): use the same release on both |
| `Different save (.sav) file` | the game has battery saves and they differ; copy one player's `.sav` to the other, or remove both |
| `Set RAM Clear to $00 or $FF` | OSD → Advanced → RAM Clear, then Save settings |
| `Different core settings` | an OSD setting differs (NES: system type, PPU reset, extra sprites, mask edges, overscan; SNES: region, ROM header, blending, audio clock, initial WRAM/ARAM, GSU slow ROM, Sufami swap): make them the same before loading the game |
| `Game chip not supported in netplay` | SNES: MSU-1, BS-X/Satellaview, a game with a clock (S-RTC, SPC7110 RTC) or a competition cart |
| `The other player runs another console` | the two players are in different netplay cores (NES, SNES, Game Boy 2P, Neo Geo, arcade) |
| `Different netplay version` | use the same release on both MiSTers |
| `Different ROM set` | Neo Geo: not the same game (its program) |
| `Different BIOS files` | Neo Geo: not the same system ROM, `sfix.sfix` or `000-lo.lo` |
| `Different core version` | arcade: different `jtbubl-netplay.rbf` files: use the same release on both |
| `server: 2 rooms with this game: pick one` | more than one room with your game is open: pick one in _Netplay/Rooms (arcade: OSD *Join room*) |
| `rooms need server= in netplay.ini` | arcade *Join room* without a server: use *Netplay → Join* with `peer=` |
| `cannot reach server` | wrong `server=`, or the server is not running |
| `server: wrong key` | `key=` does not match the server's |
| `connection lost` | nothing arrived from the other player for 5 seconds |
| `Netplay: network card on. Reset the PC` | ao486: Netplay Host or Join turned Network on; reset so DOS finds the card |
| `Netplay: alone in the room, looking again` | ao486: the others left the room (or the host loaded the core again); Join finds the host's new room |
| no connection at all (direct) | the host's router must forward UDP 7845 to the MiSTer |
| `(missing game)` in Rooms | you do not have that game with the same md5 |
| host stays at `waiting for player 2` although the server shows you joined | the joining player stopped on an error of its own: look at the message on that MiSTer (often RAM Clear on NES) |
| connected, but the game does not reload | see *Switching between the netplay cores* above: reboot from the menu, then start the core |

Not supported on NES: FDS, NSF, Vs. System and Dendy games; cheats, savestates
and multitap are switched off during netplay.

Not supported on SNES: MSU-1, BS-X/Satellaview, S-RTC, SPC7110 with its clock,
the competition carts and SPC files. During netplay cheats, savestates,
multitap, mouse, light guns, turbo and SNAC are off. While the SNES waits for
the other player's input the picture holds on HDMI; analog video goes black
for that moment.

## Building

Linux (Ubuntu 24.04 tested, WSL2 works; keep the work folder in the Linux file
system, not under `/mnt/c`):

```sh
sudo apt install -y git make g++ verilator python3 rsync
./setup.sh                                   # NES_MiSTer/, SNES_MiSTer/, Gameboy2P_MiSTer/, GBA_MiSTer/, NeoGeo_MiSTer/, ao486_MiSTer/, jtcores/ and Main_MiSTer/ with the patches
make -C NES_MiSTer/sim lint test             # RTL lint and testbench
make -C SNES_MiSTer/sim                      # whole SNES core in Verilator (GHDL in Docker): snes_sim
make -C Main_MiSTer/support/netplay/test     # netplay engine tests, host + join over UDP
tools/quartus_build.sh                       # the NES core, Quartus 17.0.2 in Docker (10-30 min)
CORE=SNES tools/quartus_build.sh             # the SNES core (about 40 min)
CORE=NeoGeo tools/quartus_build.sh           # the Neo Geo core (about 20 min)
CORE=ao486 tools/quartus_build.sh            # the ao486 core with the network card (about 40 min)
tools/ao486/dos/netplay/build.sh dist/ao486-dos   # the DOS kit floppy, Open Watcom in Docker
tools/ao486/dos/netplay/qemu_test.sh <DOS disk image> dist/ao486-dos   # the kit in QEMU
make -C NeoGeo_MiSTer/npsim det ROM=<romset> BIOS=<bios folder>   # whole Neo Geo core in Verilator, six timings compared
(cd Main_MiSTer && source setup_default_toolchain.sh && make)   # MiSTer_online
tools/jt_build.sh bubl                       # the arcade core, Quartus 20.1 in Docker (jotego/jtcore20, about 15 min)
server/build.sh                              # netplay-server, Go in Docker
tools/make_release.sh v0.7                   # releases/v0.7/ and mister-netplay-v0.7.zip
```

The Quartus image: [`tools/quartus-docker/README.md`](tools/quartus-docker/README.md).
Deploy to a MiSTer over ssh: `tools/deploy.sh <ip> all`.
The design and the protocols are specified in [`SPEC.md`](SPEC.md).

## Licence

GPL-3.0 (see `LICENSE`), as the upstream NES_MiSTer, SNES_MiSTer, Gameboy2P, ao486_MiSTer, jtcores and Main_MiSTer.
The ao486 DOS kit's menu and IPX driver are GPL-2.0-or-later; the Crynwr NE2000
packet driver on its floppy is GPL-1.0 (source in `tools/ao486/dos/crynwr`).
`tools/quartus-docker` is MIT (see `tools/quartus-docker/LICENSE.ebraminio`).
Only put games on a server that you are allowed to share.
