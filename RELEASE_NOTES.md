# Release notes

## v0.7: ao486 (PC) network games, the Netplay folder

### Changed: the netplay cores have their own folder

- The cores are now in **`_Netplay`**, shown as **Netplay** in the main menu,
  with their build date in the name as MiSTer's own cores have it
  (`NES_netplay_20261118.rbf`).
- Why: up to v0.6 they were in `_Console` next to the normal cores. A game
  shortcut (an `.mgl` file, MiSTer_SAM, a favourite) names its core without the
  date, such as `_Console/NES`, and the MiSTer takes the file whose name sorts
  last: `NES_netplay.rbf`. So those shortcuts started the netplay core instead
  of your normal one. Starting a core from the menu was not affected.
- **Updating from v0.6 or older:** copy the new `SD card` folder, then run
  **Scripts → netplay_on**. It removes the old `_Console/*_netplay.rbf` once
  their new copies are in `_Netplay`, older versions in `_Netplay` and the old
  `_Arcade/cores/jtbubl-netplay.rbf`.
- **Staying on v0.6 or older for now:** delete `_Console/NES_netplay.rbf`,
  `SNES_netplay.rbf`, `GAMEBOY2P_netplay.rbf`, `GBA_netplay.rbf` and
  `NeoGeo_netplay.rbf` when you do not play netplay, or rename them so that
  they do not start with the core's name (`Netplay-NES.rbf`): netplay works
  with any file name.

### Fixed: netplay_off when MiSTer_offline is a netplay binary

- `netplay_on` before v0.5 saved the netplay binary as `MiSTer_offline` when it
  updated one netplay binary with another, so your normal binary was gone and
  `netplay_off` refused. `update_all` does not bring it back: downloader trusts
  its list of installed files and never sees that `MiSTer` was changed.
- Now `netplay_on` and `netplay_off` see it and fetch the official `MiSTer`
  binary from the MiSTer database (the one in your `downloader.ini`), check it
  against the database's MD5 and put it in `MiSTer_offline`. Nothing to do by
  hand: copy the new `SD card` folder and run **Scripts → netplay_on** as
  usual. The MiSTer needs the network for this; without it, downloader's own
  backup `.MiSTer.old` is used when it is a normal binary, or `netplay_off`
  tries again next time.

### New: a network card for the ao486 core

- **`_Netplay/ao486_netplay_<date>.rbf`**: the MiSTer ao486 core with an NE2000
  network card (from ao486_MiSTer pull request #238 by georgemog), next to the
  normal ao486 core, which is not changed. Up to eight MiSTers in a room share
  one small network: DOS games with IPX network play see each other as on a
  LAN (Doom, Duke Nukem 3D, Warcraft II, Command & Conquer, Blood ...). Each
  MiSTer runs its own PC; only the network frames cross, so there is no
  lockstep and nothing to desync.
- In the OSD's Hardware page: **Netplay → Host** on one MiSTer and **Join** on
  the others. That turns **Network** on as well; reset the PC once. With a
  server the room takes up to eight, and the OSD lists who is in it; without
  one, two MiSTers play directly with `peer=`, as on the other cores.
- **The DOS kit** (`games/AO486/NETPLAY.IMG`): Scripts → **ao486_netplay_install**
  puts it on every DOS hard disk in `games/AO486` at once (the ready-made
  disks work; Windows 95/98 disks are left alone), and copies your DOS game
  shortcuts (such as `_DOS Games`) to **Netplay → DOS Games**, where they
  start the netplay core; **ao486_netplay_uninstall** takes it all off again. Then, with the network on,
  the PC asks at boot: **1 Online** loads the drivers and opens the network
  game menu, **2 Single player** (or no key for 10 seconds) boots the disk as
  before.
- **The menu** shows the network games on the disk and the other players in
  the room. Doom-style games get the players, mode and skill from the menu;
  the others start and show how their own menus set up network play. Press
  **J** to follow another player's game with the same settings.
- **NPIPX**, our own IPX driver on the packet driver: Intel's PDIPX passes no
  received packet on with the NE2000 driver, so Doom never found the other
  player.
- With **Netplay Off** and Network On, the card is on the MiSTer's own network
  instead (DHCP and the internet from DOS; needs an Ethernet cable).

### Credits: the network card is georgemog's

The NE2000 network card in the ao486 core is not ours. It comes from
**georgemog**'s pull request #238 to MiSTer-devel/ao486_MiSTer, "Add NE2000
network card" (github.com/georgemog/ao486_MiSTer, branch `ne2000-nic`), which
is not merged upstream. It brought the card itself in the FPGA, its wiring to
the ao486's I/O and interrupts, the shared-memory window in DDR3 through which
the ARM side moves the frames, its test benches and DOS test tools. The card's
core is the RTL8019AS/NE2000 from **apolkosnik**'s Minimig-AGA_MiSTer
(Ethernet_shmem2), which the pull request adapted. The card is their work,
not ours; what we changed is listed below.

We took the pull request as it is (`patches/ao486_MiSTer/0001`) and fixed what
the hardware showed, since it had not been built in Quartus or run on a MiSTer
before:

- The OSD's Network option used a status bit that has been the core's
  Low-Res option since 2020, so turning the network on changed the video
  mode; it moved to free bits, and the status wire carries all 128 bits (only
  64 were connected).
- The card now keeps the MAC address it took from the MiSTer through its own
  reset: a DOS driver read the PROM right after the reset and got the
  built-in address, and the replies to it were filtered away.
- On the ARM side, our Main binary moves the frames in place of the pull
  request's Python daemon, reading the core's eight-slot transmit ring (the
  daemon still read the earlier single buffer, so nothing was sent).

The rooms between MiSTers, the server's switch, the DOS menu and our IPX
driver (NPIPX) are new in this release. Details: SPEC.md section 15.

### Server

- ao486 rooms of up to eight, with the server as the room's network switch.
  The key is checked as before, and the rooms of all other cores are not
  changed. Update the server for rooms of more than two (an older Main
  works with it too, without the list of names).

### Known limits

- Rooms of three or more and the direct link have been tested in the
  automated tests only (three MiSTer programs through a real server); Doom,
  the menu and the boot question on two MiSTers through the server.
- Of the games in the menu's list (`GAMES.INI`), only Doom has been played
  between MiSTers so far. The others are set up from how each game starts its
  network play, and have not been played over the network on MiSTers yet. A
  game that does not start right can be changed in `C:\NETPLAY\GAMES.INI`.
- Only one ao486 room per server can be joined without picking it: with two
  open, Join waits ("pick one"), and there is no room folder for ao486 yet.
- Games that only play over a serial cable or modem, or with two players on
  one PC, cannot use the network card. The ao486 has no maths coprocessor
  (no Quake).

## v0.6: Neo Geo

### New: Neo Geo netplay

- **`NeoGeo_netplay.rbf`**: the MiSTer Neo Geo core with lockstep netplay, for
  cartridge games in Console (AES) mode, two players. Both MiSTers run the
  same frames, and only the controllers cross the network. It goes in
  `_Console` next to the normal NeoGeo core, which is not changed.
- In the OSD: **Netplay → Host** on one MiSTer and **Join** on the other, then
  both load the same game. With a server, Join takes the open room with that
  game; without one, `peer=` in `netplay.ini` as on the other cores.
- Both need the same BIOS files in `games/NeoGeo` (`uni-bios.rom`, or
  `neo-epo.sp1` with BIOS Original; `sfix.sfix`, `000-lo.lo`) and the same
  System Type, BIOS and Video Mode settings. All of this is checked.
- A game matches by its program, its sound CPU ROM and its cartridge
  configuration, not by its files: the same game from a Darksoft folder, a
  MAME zip or a `.neo` file finds the other player's room. The server never
  hands out Neo Geo games.
- A session needs a freshly started machine. If a game was played in the core
  before, the core loads itself again first, and the game follows by itself.
- With Netplay on, the core starts only once a game is loaded: there is no
  BIOS screen before that, even when the SD card has `bootrom/neogeo.rom`.
- The memory card, multitap, spinner and mouse are off during a session; the
  OSD's Reset and the user button do nothing.

What was changed in the core so that two MiSTers run it exactly alike (details
in SPEC.md section 14):

- The sound CPU's ROM (M1) is read from the SDRAM instead of DDR3. DDR3 is
  shared with the ARM and the scaler, and the Z80 waited a different time for
  it on every MiSTer.
- The YM2610 no longer stops when a sample byte from DDR3 is late (sound
  only: the late byte is the one before it).
- The machine leaves reset at a fixed point of the picture, after the game's
  save file has been read. The sound chip's and the video chip's counters and
  the Z80's clock start with the reset instead of running free.
- Timing constraints that hold on the hardware for the paths the Z80's bus
  feeds on every clock.

Built on the MiSTer-devel Neo Geo core (github.com/MiSTer-devel/NeoGeo_MiSTer),
the work of its contributors credited in its README.

Tested on hardware: two MiSTers over the internet through the lobby server,
nine sessions with different games and no desync, among them Over Top, Double
Dragon, Pulstar, Art of Fighting, Shock Troopers 2nd Squad and Aero Fighters 3.
A recorded Neo Turf Masters session replayed with identical results over 9,000
frames. In simulation (Verilator): the whole core makes the same writes with
both CPUs, at the same clocks, in every frame, with the DDR3's timing, the clock
phase, the session's start, the save file's read and the input's arrival all
varied, and with a boot ROM at the core's start.

### Known limits

- Neo Geo CD is not supported, and nor are the memory card, multitap, spinner
  and mouse during a session. Arcade (MVS) mode has not been tested.
- Neo Geo has no room folder: with a server, Join takes the oldest open room
  with the game you load.
- Update both MiSTers: the core and `MiSTer_online` must come from this
  release on both.

## v0.5: GBA Wireless Adapter

### New: GBA wireless games

- **`GBA_netplay.rbf`**: the MiSTer GBA core with an emulated **GBA Wireless
  Adapter** on the link port. Games that use Nintendo's adapter play over the
  internet: Apotris, Pokémon FireRed, LeafGreen and Emerald (the Union Room:
  battles and trades), and homebrew built on gba-link-connection.
- This is not lockstep: each MiSTer runs its own game, and the two adapters
  talk to each other over the network. The players may run different games
  that talk to each other (FireRed and LeafGreen).
- In the OSD: **Hardware → Link Port → Wireless Adapter**, then **Netplay →
  Host** on one MiSTer and **Join** on the other, and load the game. Then use
  the game's own wireless menu, as on real GBAs.
- The core handles the adapter's handshake and words; the Main binary answers
  each command (ported from gpSP's adapter emulation, GPL-2.0-or-later) and
  carries the adapter's packets over a reliable, ordered link between the two
  MiSTers, directly or through the lobby server.
- Loading the game again keeps the room: the other player's MiSTer follows
  without loading its own game again.
- A lost packet is sent again after about 1.5 round trips, so the game's data
  is held up for tens of milliseconds, not 100.
- `netplay.log` shows the link's round trip, resends, and how fast the
  adapter's commands are answered, every 10 seconds.
- To try it: **Apotris**, a free game by akouzoukos with 2-player battles over
  the adapter, from https://akouzoukos.com/apotris/downloads (put
  `Apotris.gba` in `games/GBA`).

Built on the work of others: the adapter emulation is ported from **gpSP** by
David Guillen Fandos (github.com/libretro/gpsp), the protocol is as documented
by afska and davidgfnet in **gba-link-connection**
(github.com/afska/gba-link-connection), and Pokémon's link handling was read in
**pret/pokefirered**. Details in the README, "Where the GBA Wireless Adapter
comes from".

Tested on hardware: two MiSTers over the internet through the lobby server on a
Raspberry Pi: Pokémon FireRed/LeafGreen battles and a trade in the Union Room, and
gba-link-connection's `LinkUniversal_stress` ROM (packet loss and packet sync,
65,534 packets each without a loss; ping 26 to 47 ms with a 20 ms network round
trip). In simulation: the core's serial port and adapter against Pokémon's own
wireless library, with the Main binary's answers late and out of order.

### Scripts

- `netplay_on` no longer saves an older netplay binary as `MiSTer_offline`
  when you update: your normal binary stays there. `netplay_off` says so when
  `MiSTer_offline` is a netplay binary (from an older `netplay_on`); then
  `update_all` or `downloader` brings the normal binary back.

### Server

- GBA rooms accept any GBA game, so FireRed and LeafGreen find each other.
  Update the server too.

### Known limits

- Two players (the adapter allows five). No wireless multiboot (one cartridge
  for both). Savestates and rewind are off while the adapter is on.
- Each command the game sends to the adapter is answered by the Main binary,
  usually in 0.2 to 0.5 ms; about 1 in 100 takes 1 to 3 ms. The games tested
  handle this. Moving the answers for the data commands into the core is
  planned.
- When the host loads the core again (not just the game), the other player
  loads their game again too.
- Through a server on the same network as one of the players, the link goes
  through the server; the extra step is about a millisecond.

## v0.4: Arcade netplay (Bubble Bobble)

### New: arcade netplay

- **`jtbubl-netplay.rbf`**: Jotego's Bubble Bobble core (jtbubl) with lockstep
  netplay. The netplay module is in his framework, jtframe, so other jtframe
  arcade cores can get it the same way later. The core goes in
  `_Arcade/cores` next to the normal `jtbubl.rbf`, which is not changed, and is
  started from its own MRA, **Bubble Bobble (US, Ver 5.1) [netplay]**. It uses
  the ROM set the MiSTer updater installs for Jotego's core.
- **Host:** OSD **Netplay → Host**. **Join:** in the game's OSD, **Join room**
  lists the open rooms; picking one joins it without reloading the game. The
  same rooms are in the Arcade list, folder **_Netplay**, also from the main
  menu. Without a server: `peer=` and **Netplay → Join**.
- Both players need the same ROM set (checked) and the same core version. The
  host's DIP switches are used during a session, and each player's own come
  back afterwards. The game's RAM is cleared at the start of a session.
- The checksum covers the game state (every CPU write), so a desync is caught
  in the frame it happens.
- The CPUs read their ROMs from block RAM in the netplay core: SDRAM timing
  differs between two MiSTers and must not decide the game's timing.
- When an input is late, HDMI repeats the last picture without a glitch.

Tested on hardware: two MiSTers over the internet through the lobby server on a
Raspberry Pi, 33 levels in 20 minutes without a desync. In simulation: the whole
core on two simulated MiSTers in sync, with the same order of every clock
enable.

### Server

- A join without a picked room (**Netplay → Join** and load the game) only goes
  into a room when exactly one room with that game is open. With several, the
  OSD says `<n> rooms with this game: pick one`, so nobody ends up with a
  stranger by chance. This applies to NES, SNES and Game Boy 2P too.
- The status page has an **Arcade** tab with the open arcade rooms. It is
  public by default (no key in the address); `public_page=no` asks for the key.
- Lighter page (no endless animations).
- Raspberry Pi: `sudo sh install-linux.sh` in the release's `Server` folder
  installs or updates the server as a service; settings, key and games stay.

### Known limits

- With `mode=join` in `netplay.ini`, or the OSD on **Join**, a game load joins
  by itself when exactly one room with the game is open. Keep `mode=off` (the
  OSD on `netplay.ini`) to pick rooms yourself.
- Only Bubble Bobble so far. During netplay the pause, test and service
  switches are off. Analog video may flicker for a moment when an input is late.

## v0.3: Game Boy link-cable netplay

### New: Game Boy 2P

- **`GAMEBOY2P_netplay.rbf`**: pomstazlesa's Game Boy 2P core (two Game Boys
  joined by a link cable inside the FPGA) with lockstep netplay. Each MiSTer
  runs both Game Boys; the host plays Game Boy 1, the other player Game Boy 2.
  Only the controller input goes over the network, so the link cable's timing
  is the same as on one MiSTer.
- Link-cable games such as Tetris, Tennis and Dr. Mario, with one game for
  both, or two different games (load game 1 with *Rom for second GB* Off, then
  game 2 with it On).
- **Show → My screen** shows only your own Game Boy, centred at the right
  aspect ratio; **Audio select → Own GB** plays your own Game Boy's sound.
- Both Game Boys run on one shared clock enable, which also keeps them in step
  without netplay; the SDRAM serves both from one read when they read the same
  word, so the core runs at full speed with clean sound.
- The Game Boys' RAM and the cartridge clock (MBC3, HuC3, TAMA) are cleared at
  the start of a session, so a MiSTer that ran other games before starts like a
  freshly loaded one. The cartridge clock runs on emulated time from the host's
  start time.
- Same lobby as NES and SNES: **OSD → Netplay → Host** in GAMEBOY2P_netplay,
  the other player joins from **_Netplay/Rooms** (a room with two games holds
  both files). The server's Game Boy games go in `roms/GB`.
- Battery saves as on NES: the same `.sav` on both sides, or none. Not
  supported: MegaDuck (`.bin`). Needs the SDRAM board.

Tested on hardware: a Tetris link match between two MiSTers through the lobby
server; Tennis with clean sound at full speed. In simulation: two MiSTers in
sync over 1,800 frames of Tetris, and after one of them ran another game.

### Other changes

- The lobby folder is created on a MiSTer that has no games folder for the core
  yet.
- Main_MiSTer build: changed headers now rebuild the files that use them.

## v0.2: SNES netplay

### New: Super NES

- **`SNES_netplay.rbf`**: the MiSTer SNES core with lockstep netplay. Both
  MiSTers run the same frames with the same input, and a checksum of every
  frame is compared, so a desync stops the session instead of going on silently.
- All 12 buttons of both controllers (D-pad, A B X Y, L R, Select, Start).
- The core's coprocessors stay on: SA-1, Super FX, the DSP chips, Cx4, S-DD1,
  SPC7110 (without its clock) and Sufami Turbo. Tested on hardware so far:
  SA-1, Super FX 2 and DSP-1.
- The SNES core has no pause, so netplay stops the emulated machine's clock
  when the other player's input is late. The picture holds on HDMI; analog
  video goes black for that moment.
- Same lobby as NES: **OSD → Netplay → Host** in SNES_netplay, the other player
  joins from **_Netplay/Rooms**. Rooms and server games are per core.
- No settings to change before playing. Both players need the same OSD settings
  (region, ROM header, blending, audio clock, initial WRAM/ARAM, GSU slow ROM,
  Sufami swap); the session tells you when one differs.
- Not supported (they depend on wall-clock time or on files streamed from the SD
  card): MSU-1, BS-X/Satellaview, S-RTC, SPC7110 with its clock, the competition
  carts (Campus Challenge '92, PowerFest '94) and SPC files. During netplay
  cheats, savestates, multitap, mouse, light guns, turbo and SNAC are off.

Tested on hardware: replays of 37,000+ frames identical on Super Mario World,
Donkey Kong Country, Kirby Super Star (SA-1), Yoshi's Island (Super FX 2) and
Pilotwings (DSP-1); two MiSTers (a DE10-Nano and a MiSTer Pi) over the internet
through the lobby server.

### Fixed before release

- **Desync after playing other games.** A ROM load left the SNES sound chip's
  registers from the previous game, so a game could run differently on a MiSTer
  that had played something else first (Contra III desynced early). The core
  now clears them on every load.
- **SDRAM timing.** A path in the SNES core (DMA from ROM to WRAM) was wrongly
  allowed two clocks in the timing constraints. It is a real one-clock path and
  the core now meets it. Before, it could go wrong on some boards and not on
  others, a likely cause of desyncs seen between a DE10-Nano and a MiSTer Pi.

### Main binary and server

- One `MiSTer_online` for both cores. NES keeps protocol version 1 unchanged
  (NES play with Mesen still works); SNES uses version 2.
- New messages: `The other player runs another console` (one player in NES, the
  other in SNES), `Game chip not supported in netplay` (SNES), and
  `Different core build` for both cores.
- Server: games in `roms/NES` (or `roms` itself) and `roms/SNES`, up to 8 MB per
  SNES game. A new status page with a library per core, room cards and live
  updates.

### Good to know

- **Switching between NES_netplay and SNES_netplay: reboot from the MiSTer's
  menu first**, then start the other core. Jumping straight from one core to the
  other can leave netplay without the ROM reload at the start of a session.
- Both players need the **same release**: a different `NES_netplay.rbf` or
  `SNES_netplay.rbf` gives `Different core build`.
- If the host waits at `waiting for player 2` while the server already shows
  the other player as joined, the joining MiSTer stopped on an error of its own
  (on NES often RAM Clear): read the message there.
- The easiest way to get the same game file on both sides is the server: load
  it from `_Netplay/Server games` (host) and `_Netplay/Rooms` (join).

### Upgrading from v0.1.x

Copy the new `SD card` folder onto both MiSTers (it replaces `MiSTer_online`
and adds `_Console/SNES_netplay.rbf`), run **Scripts → netplay_on** again, and
replace the server's binary. `netplay.ini` and `netplay-server.ini` stay as
they are.

## v0.1.x

- NES netplay: the NES core, the Main binary and the lobby server.
