# Release notes

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
