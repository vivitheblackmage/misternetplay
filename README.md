# NES, SNES, Game Boy, GBA and arcade netplay for MiSTer

Play NES, Super NES, Game Boy link-cable games and Bubble Bobble (arcade)
together on two [MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki) boards over the
internet or a LAN. Both MiSTers run the real core in lockstep: each frame's controller input is sent to the other side, and both
run exactly the same frames with the same input. A checksum of the game state
is compared all the time, so a desync stops the session instead of going on
silently.

GBA games that use Nintendo's **GBA Wireless Adapter** work differently: each
MiSTer runs its own game, and the adapter is emulated, so the two GBAs talk to
each other over the internet as they would over the air.

It comes in these parts:

- **NES core** (`NES_netplay.rbf`) and **SNES core** (`SNES_netplay.rbf`): the
  MiSTer NES and SNES cores with a netplay module added to the FPGA design.
- **Game Boy 2P core** (`GAMEBOY2P_netplay.rbf`): a core with two Game Boys
  joined by a link cable inside the FPGA, with the same netplay module. Each
  MiSTer runs both Game Boys; the host plays Game Boy 1, the other player Game
  Boy 2, so link-cable games (Tetris, Tennis, Dr. Mario, trading and battles)
  work over the network.
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
- GBA Wireless Adapter on hardware: two MiSTers over the internet through the
  lobby server (on a Raspberry Pi), Pokémon FireRed/LeafGreen battles and a
  trade in the Union Room, and gba-link-connection's `LinkUniversal_stress` test ROM
  (packet loss and packet sync: 65,534 packets without a loss). In simulation:
  the core's serial port and adapter against Pokémon's own wireless library
  (librfu), with the Main binary's answers late and out of order.
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
| Arcade core (FPGA) | [github.com/jotego/jtcores](https://github.com/jotego/jtcores) (jtbubl and jtframe) | `15d60ca` (2026-10-23) | [`patches/jtcores/`](patches/jtcores) |
| Main binary (ARM) | [github.com/MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | `0827165` (2026-10-30) | [`patches/Main_MiSTer/`](patches/Main_MiSTer) |

The NES and SNES cores are the work of the MiSTer-devel contributors and of the
authors credited in their own READMEs; Main_MiSTer likewise. The Game Boy 2P
core is pomstazlesa's two-player fork of the MiSTer-devel Game Boy core. The
arcade core and jtframe are Jotego's (jtcores). All are licensed GPL-3.0, and
so are our patches.

`./setup.sh` clones the six upstream repositories next to it and applies the
patches on a branch called `netplay`.

Everything else here is our own: the lobby server (`server/`), the tools
(`tools/`) and the NetPong test game (`netpong/`). The Quartus Docker setup in
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
| Game | The same ROM file on both MiSTers (same md5), or the server's copy. NetPong, a free two-player NES test game, is included. Game Boy 2P needs the SDRAM board, as the original core. Bubble Bobble: the ROM set the MiSTer updater installs for Jotego's core (`games/mame/bublbobl.zip`), the same on both MiSTers; arcade games never come from the server. |
| Server (optional) | Windows 10/11, or Linux on x86-64, ARM64 or ARMv7, such as Raspberry Pi OS (32- or 64-bit), Debian or Ubuntu. The binaries have no dependencies; the installer needs systemd (without it, run the binary by hand). Tested on Windows 10; Linux x86-64 in the automated tests. One forwarded port (7845, UDP and TCP) on the server's router. |
| Building (developers) | Linux, tested on Ubuntu 24.04 (also in WSL2 on Windows 10). Docker for Quartus Prime Lite 17.0.2, Verilator 5, g++, Python 3, Go 1.22 (or Docker). See [Building](#building). |

## Installing on the MiSTer

Download `mister-netplay-<version>.zip` from the releases and unzip it on a
computer. Then on **each** MiSTer:

1. Copy everything in the folder `SD card` to the root of the MiSTer's SD card
   (where `_Console` is), over the network share or with the card in a
   computer. None of your files is overwritten:
   - `_Console/NES_netplay.rbf`, `_Console/SNES_netplay.rbf`,
     `_Console/GAMEBOY2P_netplay.rbf` and `_Console/GBA_netplay.rbf`: the
     cores, next to the normal ones
   - `_Arcade/cores/jtbubl-netplay.rbf` and
     `_Arcade/Bubble Bobble (US, Ver 5.1) [netplay].mra`: the arcade core and
     its MRA, next to Jotego's (which are not changed)
   - `MiSTer_online`: the netplay main binary
   - `Scripts/netplay_on.sh`, `Scripts/netplay_off.sh`
   - `netplay.ini`: the settings (keep yours if you already have one)
   - `games/NES/NetPong/NetPong.nes`
2. On the MiSTer: **Scripts → netplay_on**. Your binary is saved as
   `MiSTer_offline`, `MiSTer_online` becomes `MiSTer`, and the MiSTer
   reboots. **Scripts → netplay_off** switches back.
3. NES: start **Console → NES_netplay**. In the OSD: **Advanced → RAM Clear → $00**,
   then **Save settings** at the bottom of the menu (both players need the
   same settings).
4. SNES: start **Console → SNES_netplay**. Nothing to set up; both players need
   the same OSD settings.
5. Game Boy 2P: start **Console → GAMEBOY2P_netplay**. Put the games
   (`.gb`, `.gbc`) in `games/GAMEBOY2P`. Nothing to set up.
6. Arcade: start **Arcade → Bubble Bobble (US, Ver 5.1) [netplay]**. Nothing
   to set up; the DIP switches are the host's during a session.
7. GBA: start **Console → GBA_netplay**. In the OSD: **Hardware → Link Port →
   Wireless Adapter**. See [GBA Wireless Adapter](#gba-wireless-adapter).

**Switching between the netplay cores:** reboot from the MiSTer's menu first,
then start the other core. Jumping straight from one core to the
other can leave netplay without the ROM reload at the start of a session.

### Playing directly (no server)

- The host forwards **UDP port 7845** in its router to its MiSTer, then picks
  **Netplay → Host** in the OSD (NES_netplay, SNES_netplay,
  GAMEBOY2P_netplay or GBA_netplay) and loads a game.
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
| `Different core build` | different `NES_netplay.rbf`, `SNES_netplay.rbf` or `GAMEBOY2P_netplay.rbf` files: use the same release on both |
| `Different save (.sav) file` | the game has battery saves and they differ; copy one player's `.sav` to the other, or remove both |
| `Set RAM Clear to $00 or $FF` | OSD → Advanced → RAM Clear, then Save settings |
| `Different core settings` | an OSD setting differs (NES: system type, PPU reset, extra sprites, mask edges, overscan; SNES: region, ROM header, blending, audio clock, initial WRAM/ARAM, GSU slow ROM, Sufami swap): make them the same before loading the game |
| `Game chip not supported in netplay` | SNES: MSU-1, BS-X/Satellaview, a game with a clock (S-RTC, SPC7110 RTC) or a competition cart |
| `The other player runs another console` | the two players are in different netplay cores (NES, SNES, Game Boy 2P, arcade) |
| `Different netplay version` | use the same release on both MiSTers |
| `Different core version` | arcade: different `jtbubl-netplay.rbf` files: use the same release on both |
| `server: 2 rooms with this game: pick one` | more than one room with your game is open: pick one in _Netplay/Rooms (arcade: OSD *Join room*) |
| `rooms need server= in netplay.ini` | arcade *Join room* without a server: use *Netplay → Join* with `peer=` |
| `cannot reach server` | wrong `server=`, or the server is not running |
| `server: wrong key` | `key=` does not match the server's |
| `connection lost` | nothing arrived from the other player for 5 seconds |
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
./setup.sh                                   # NES_MiSTer/, SNES_MiSTer/, Gameboy2P_MiSTer/, jtcores/ and Main_MiSTer/ with the patches
make -C NES_MiSTer/sim lint test             # RTL lint and testbench
make -C SNES_MiSTer/sim                      # whole SNES core in Verilator (GHDL in Docker): snes_sim
make -C Main_MiSTer/support/netplay/test     # netplay engine tests, host + join over UDP
tools/quartus_build.sh                       # the NES core, Quartus 17.0.2 in Docker (10-30 min)
CORE=SNES tools/quartus_build.sh             # the SNES core (about 40 min)
(cd Main_MiSTer && source setup_default_toolchain.sh && make)   # MiSTer_online
tools/jt_build.sh bubl                       # the arcade core, Quartus 20.1 in Docker (jotego/jtcore20, about 15 min)
server/build.sh                              # netplay-server, Go in Docker
tools/make_release.sh v0.4                   # releases/v0.4/ and mister-netplay-v0.4.zip
```

The Quartus image: [`tools/quartus-docker/README.md`](tools/quartus-docker/README.md).
Deploy to a MiSTer over ssh: `tools/deploy.sh <ip> all`.
The design and the protocols are specified in [`SPEC.md`](SPEC.md).

## Licence

GPL-3.0 (see `LICENSE`), as the upstream NES_MiSTer, SNES_MiSTer, Gameboy2P, jtcores and Main_MiSTer.
`tools/quartus-docker` is MIT (see `tools/quartus-docker/LICENSE.ebraminio`).
Only put games on a server that you are allowed to share.
