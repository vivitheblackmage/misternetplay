# NES_MiSTer Netplay — SPEC v1

Status: v1 against NES_MiSTer `49a0a66` and Main_MiSTer `0827165`. Built in
Quartus (timing OK) and tested on hardware: replay determinism (T5) and lockstep
over the internet between two MiSTers, directly and through the lobby server
(server on Windows 10). Hole punching and the relay fallback are also covered in T3.
This document is the definition of "done". Code that differs from the spec is a
bug in the code or in the spec — never change one without the other.

## 1. Goals and scope

**Goal v1:** two MiSTer boards play the same NES game, one player per board,
over UDP. Delay-based lockstep: both run exactly the same emulation; only
controller data is sent.

**In scope v1**
- 2 players, standard controller (8 buttons) on ports 1 and 2.
- Direct IP (LAN or port forwarding), configured in `netplay.ini`, and an
  optional lobby/relay server with UDP hole punching (`server/`).
- Desync detection (a CRC per frame) that stops the session with a clear error.
- Record/replay of local input (a determinism test without a network).

**Out of scope v1**
- Rollback, more than 2 players, Multitap, Zapper, Power Pad, microphone, SNAC,
  Famicom keyboard, FDS, NSF, Vs. System.
- Sending the ROM or the `.sav` from one player to the other (both must have
  the same file locally; a server may hand out games it is allowed to share).

### 1.1 Where the files go on the MiSTer (since v0.7)

- The netplay cores are in their own folder, `_Netplay` (the main menu shows
  it as "Netplay"), named `<CORE>_netplay_<build date>.rbf` like MiSTer's own
  (`NES_netplay_20261118.rbf`); the arcade core is
  `_Arcade/cores/jtbubl-netplay_<date>.rbf`. Never in `_Console` or
  `_Computer`: a game shortcut (MGL, MiSTer_SAM) names a core without its
  date (`_Console/NES`), and Main takes the file whose name sorts last among
  `NES.*` and `NES_*` (`support/arcade/mra_loader.cpp`, `get_rbf`), which was
  `NES_netplay.rbf` up to v0.6. Netplay finds its system by the core's name
  in its configuration string and its build by the `V,` entry, never by the
  file name or folder; a core reload uses the loaded file's own path.
- `Scripts/netplay_on.sh` removes the netplay cores older releases left in
  `_Console`/`_Computer` (only when a copy is in `_Netplay`), older dated
  versions in `_Netplay`, and `_Arcade/cores/jtbubl-netplay.rbf`.
- `MiSTer_offline` is the user's normal Main binary (a netplay binary has the
  string `netplay.ini` in it, the normal one does not). netplay_on before v0.5
  saved the active netplay binary there on an update, and update_all does not
  bring it back (downloader trusts its own list of installed files). When
  `MiSTer_offline` is missing or a netplay binary, netplay_on (if the netplay
  binary is active) and netplay_off run `Scripts/.config/netplay/normal_main.py`:
  it fetches `MiSTer` from the distribution database (the `db_url` of
  `[distribution_mister]` in `downloader.ini`, or MiSTer-devel's) and installs
  it only when its MD5 matches the database; offline it takes downloader's
  `.MiSTer.old` if that is a normal binary. netplay_on switches anyway when it
  cannot; netplay_off then stops without changing anything (T3e-o).
- `ao486_netplay_install.sh` (15.5) copies the menu's game shortcuts that
  start `_computer/ao486` with a disk that has the netplay menu to
  `_Netplay/_DOS Games`, with the core `_Netplay/ao486_netplay`; the
  originals keep the normal core. The uninstall removes only those copies.

## 2. Architecture

```
NES core (FPGA)                         Main_MiSTer (ARM, Linux)
 rtl/netplay.sv  <-- DDR3 mailbox -->   support/netplay/netplay.cpp (own thread)
   frame tick, gate, input mux,           UDP, handshake, combining input,
   CRC, mailbox sequencer                 CRC comparison, record/replay
```

Ethernet is only on the HPS side. All communication between the FPGA and the ARM
goes through a mailbox in DDR3, the same pattern upstream already uses for the
Sun/HP9000/SGI Ethernet bridges (`support/sun/sun_enet.cpp`) and that the
RetroAchievements fork uses for NES.

## 3. Frame model (normative)

- **Frame tick** = the emulated moment the PPU's scanline counter
  (`scanline_ppu`, not the paused video copy) enters the VBlank start line
  (241 for NTSC/PAL). Detected as an edge on the emulated scanline, which is
  immune to `pausecore` because the counter stands still during a pause.
- **Frame 0** starts when the netplay module releases reset (SNES: when `RESET_N`
  rises, at the PPU's next `HVCNT_ATZERO`, see 10.2). **Frame k** (k ≥ 1)
  starts at tick number k.
- **Input for frame k**, `INPUT[k] = {p1, p2}`, applies from the start of frame k
  to the start of frame k+1. The game reads the controller through the normal
  strobe/shift logic in `NES.sv`; netplay only switches the source of
  `nes_joy_A`/`nes_joy_B`.
- **Lookahead:** the FPGA holds two fetched entries, slot 0 = `INPUT[base]` and
  slot 1 = `INPUT[base+1]`, where `base` = the first frame not started yet
  (0 in PRIME, `frame+1` in RUN). The fetch engine always fills the first empty one.
- At the start of frame k:
  1. `cur ← slot0` (= `INPUT[k]`), `slot0 ← slot1`, `slot1` is emptied.
  2. The FPGA samples the local controller and posts `LOCAL[k]`.
  3. The FPGA posts `CRC[k-1]` (for k ≥ 1).
- **Gate:** if `INPUT[k+1]` (slot 0) is missing when frame k starts, netplay
  requests `pausecore`. The pause enters VBlank right after the tick, at an
  instruction boundary, and releases only when the free-running video copy of
  the PPU has gone a full round: **every stall costs at least one whole frame**
  (a repeated picture). That is why input is fetched one frame ahead, and a
  pause is requested only when the data is really missing. If a tick still
  happens without slot 0, it is an **underrun error**: the module goes to ERROR
  and holds the pause.
- **PRIME** needs both `INPUT[0]` and `INPUT[1]` before releasing reset, because
  there is no VBlank (and so no chance to pause) between reset and the first tick.
- **Delay D** (frames, 2–15, default 2): the HPS writes
  `INPUT[k+D] = combine(LOCAL[k] here, LOCAL[k] from the peer)`.
  `INPUT[0..D-1]` are prefilled with 0 (no buttons) before the start. D = 1 is
  impossible (PRIME would wait for `LOCAL[0]`, which is posted only after PRIME).
- **Network budget without a stall** ≈ (D−1) frames from the peer posting
  `LOCAL[k]` until `INPUT[k+D]` is written here. More than that gives occasional
  stalls, not a desync.

## 4. Mailbox in DDR3 (normative)

Base: physical address **`0x3C000000`**, size `0x4000`. (Savestates use
`0x3E000000`, the RetroAchievements fork `0x3D000000`.) The FPGA reaches it
through a new channel 2 in `rtl/ddram.sv` (word address `ch2_addr[27:1]` =
`(0x0C000000 + off) >> 1`).

All fields are 64-bit little-endian words. Rings have 256 slots of 8 bytes,
slot = `frame & 0xFF`.

| Offset | Name | Written by | Contents |
| --- | --- | --- | --- |
| `0x0000` | `MAGIC` | FPGA | `0x313030504E53454E` ("NESNP001") after every core reset |
| `0x0008` | `STATUS` | FPGA | `[63:32]` frame, `[31:24]` state, `[23:16]` error, `[15:0]` stall counter |
| `0x0010` | `CTRL` | HPS (the FPGA clears it at power-on) | `[63:32]` = `0x4C525443` ("CTRL"), `[0]` enable, `[1]` run, `[15:8]` session id. Without the magic the word means "off". |
| `0x1000` | `LOCAL[256]` | FPGA | local input sampled at the start of frame f |
| `0x1800` | `CRC[256]` | FPGA | CRC-32 of the finished frame f |
| `0x2000` | `INPUT[256]` | HPS | input to apply in frame f |

**Tearing protection:** ARMv7 on the Cortex-A9 does not guarantee that a 64-bit
write becomes visible atomically. So *both* 32-bit halves carry the frame tag:

- `LOCAL`: `hi = {f[15:0], sess[7:0], joy[7:0]}`, `lo = {f[15:0], sess[7:0], joy[7:0]}`
- `INPUT`: `hi = {f[15:0], sess[7:0], p2[7:0]}`, `lo = {f[15:0], sess[7:0], p1[7:0]}`
- `CRC`:   `hi = {f[15:0], crc[31:16]}`, `lo = {f[15:0], crc[15:0]}`

An entry is valid only if the tag of both halves (and sess where present)
matches the expected value. The HPS fills all rings with `0xFFFF000000000000`
(the tags in the two halves differ, so the word never decodes) before setting
`enable` — not with 0, because 0 decodes as a valid `CRC[0]`.

**Power-on:** the FPGA first writes `CTRL = 0`, then `MAGIC`. DDR3 is not cleared
between cores; when Main_MiSTer sees `MAGIC` it knows `CTRL` is clean. An old
word from another core can never arm netplay (that needs the CTRL magic).

The `joy` byte has the same bit order as `nes_joy_A` in `NES.sv`:
`{Right, Left, Down, Up, Start, Select, B, A}` (bit 7 → bit 0).

### STATUS.state

| Value | Name | Meaning |
| --- | --- | --- |
| 0 | IDLE | netplay off, the core behaves as upstream |
| 1 | ARMED | enable=1, the core is held in reset, waiting for run |
| 2 | PRIME | run=1, fetching `INPUT[0]` |
| 3 | RUN | lockstep running |
| 4 | ERROR | error, the pause is held until enable=0 |

### STATUS.error (bits)

- bit 0 `UNDERRUN` — a tick happened without `INPUT[k+1]`.
- bit 1 `CTRL_DROP` — enable fell during RUN (a normal end, not an error for the HPS).
- bit 2 `RELOAD` — a ROM load started during PRIME/RUN.

### Session start (normative order)

The core's RAM is not deterministic after a normal reset (the CPU RAM is in
SDRAM and keeps its contents). So every session starts with a new ROM load with
RAM Clear = `$00` or `$FF`:

1. HPS: handshake with the peer (HELLO/HELLO_ACK) accepted.
2. HPS: clear the rings, write `CTRL.enable=1, run=0, session=s` → the FPGA goes
   to ARMED and holds the core in reset.
3. HPS: load the same ROM file again (`user_io_file_tx`). The loader clears RAM.
   The netplay module's state is not affected by the load in ARMED.
4. HPS: wait until the load is done + 1000 ms (so a `.sav` has time to load).
5. HPS: prefill `INPUT[0..D-1]` with 0, send/receive START, set `run=1`.
6. FPGA: PRIME → fetches `INPUT[0]` → releases reset → RUN, frame 0.

The netplay module is reset only at power-on (`init`), not on a ROM load.
A ROM load during PRIME/RUN gives the `RELOAD` error.

## 5. FPGA module `rtl/netplay.sv`

Ports (all on `clk`):

| Port | Direction | Description |
| --- | --- | --- |
| `reset` | in | power-on reset (`~init_reset_n` is *not* right — use the PLL's `locked`) |
| `downloading` | in | a ROM load is in progress |
| `scanline_emu[8:0]` | in | emulated PPU scanline (new port from `nes.v`) |
| `ppu_ce_emu` | in | emulated PPU clock enable (new port from `nes.v`) |
| `color[5:0]` | in | PPU pixel |
| `vbl_line[8:0]` | in | 241 (NTSC/PAL), 291 Dendy (Main_MiSTer refuses Dendy/Vs. in v1 anyway; an NES 2.0 header with "multiple regions" counts as NTSC, like the core's Auto) |
| `core_paused` | in | the core's `corepaused`, for the stall counter |
| `local_joy[7:0]` | in | local controller 1, raw (without the paddle masking of A), same bit order as `nes_joy_A` |
| `active` | out | 1 in ARMED/PRIME/RUN/ERROR |
| `hold_reset` | out | 1 in ARMED/PRIME |
| `pause_req` | out | 1 when slot 0 is missing in RUN, and always in ERROR |
| `joy_p1[7:0]`, `joy_p2[7:0]` | out | input for the current frame |
| `ddr_*` | — | ch2 to `ddram.sv` (addr, din, dout, req, rnw, be, ready) |

Rules:
- Everything on `clk`, no new clocks. The DDR arbiter already runs on `clk`.
- The fetch engine polls at most every `POLL_INTERVAL` clock cycles (parameter, default 256).
- `CTRL` is read at least once per frame in RUN and continuously (throttled) in IDLE/ARMED.
- CRC-32 (reflected, polynomial `0xEDB88320`, init `0xFFFFFFFF`, no final XOR)
  is fed with `p1` and `p2` at the frame start and with `{2'b00, color}` on every
  `ppu_ce_emu` from the **first tick** on. So frame 0 hashes only its inputs:
  right after reset the PPU stays in reset for a number of clocks that depends on
  where PRIME ended in wall-clock time. Cleared at every tick.
- When the module goes to IDLE, pending `LOCAL`/`CRC` writes are dropped.

## 6. Changes to existing files (minimal)

- `rtl/nes.v`: two new output ports, `scanline_emu = scanline_ppu`, `ppu_ce_emu = ppu_ce`.
  PAL's 5-cycle counter (`cpu_tick_count`) is cleared during reset, so the
  CPU/PPU phase after reset does not depend on when reset was released.
- `rtl/ddram.sv`: new channel 2 (channel 1, savestates, has priority). Read data
  is now also taken when `DDRAM_BUSY` is high in the same cycle (Avalon allows
  it; upstream lost the word and hung — this affects savestates too).
- `NES.sv`: instantiate `netplay`, OR `pause_req` into `pausecore` and
  `hold_reset` into `reset_nes`, mux ports 1/2. While `active`: cheats,
  savestates, OSD pause, multitap, Miracle Piano, OSD reset and the user button's
  reset are off; bits D1–D4 on both ports (microphone, SNAC, Zapper, paddle,
  Power Pad, Famicom keyboard) read as idle — they are local hardware the other
  player does not see.
- `files.qip`: add `rtl/netplay.sv`.
- `sys/` is **never** changed.

## 7. HPS side `support/netplay/`

- `netplay_proto.{h,cpp}` — packet format, mailbox words, settings checks.
- `netplay_session.{h,cpp}` — the session engine (host/join/record/replay):
  handshake, arming, combining into `INPUT[k]`, CRC comparison. No OS calls: the
  mailbox is a pointer and the network is behind `Transport`, so everything is
  tested on x86.
- `netplay.{h,cpp}` — MiSTer integration: `netplay_start/stop/poll`, own
  pthread, `shmem_map(0x3C000000, 0x4000)`, UDP socket, reading the ini file,
  the lobby.
- `fpga_io.cpp`: `netplay_stop()` first in `fpga_load_rbf()`, before the FPGA is
  reprogrammed (the next core may use the DDR3 where the mailbox is), and first
  in `app_restart()`, before the process exits. It is the stop that saves a recording.
- `user_io.cpp`: `netplay_start()` when a core named `NES` or `SNES` starts,
  `netplay_stop()` on a core change, `netplay_poll()` in the main loop and
  `netplay_note_file(name, index, opensave)` in `user_io_file_tx`. Only OSD index
  1 (the game slot) starts a session; BIOS (0, 2) and palette (3) are ignored.
  The reload at the session start uses the same `opensave`, so the `.sav` is loaded.
- A new session waits until the FPGA reports IDLE (and writes CTRL=0 meanwhile),
  so an immediate restart cannot arm before the core has seen CTRL=0.

### Configuration `/media/fat/netplay.ini`

```ini
[netplay]
mode=host          ; host | join | record | replay | off
peer=192.168.1.20  ; join: the host's IP. host: empty = accept the first peer
port=7845
delay=2
file=              ; record/replay: empty = one file per game, netplay/<ROM name>.npr
server=            ; optional netplay-server host[:port], see "Server and lobby"
key=               ; the server's key
name=              ; player name in the lobby
direct=yes         ; no = everything through the server, no hole punching
```

The host plays port 1, the join plays port 2.

The OSD option **Netplay** in the NES core (status `[89:88]`): `netplay.ini` (0,
default: `mode=` applies), `Off`, `Host`, `Join`. It is read when a game is
loaded, so it can be changed without reloading the core. IP, port and delay
always come from the ini file; it is not needed for Host (default: port 7845,
delay 2), but Join needs `peer=`. The netplay thread starts only when a game is
loaded with a mode other than Off.

### Server and lobby (`server/`, `netplay-server`)

An optional meeting point. With `server=host[:port]` and `key=` in `netplay.ini`,
Host/Join get a room list instead of an IP address. The server pairs the
players, and they then try to talk to each other directly (UDP hole punching);
when that does not work, the server forwards the session packets. Only the
server's computer needs an open port. `peer=` is not used then. Without
`server=` everything is as before (direct IP).

**Names.** `name=` in `netplay.ini` (default `MiSTer-` + the last four hex
digits of the network card's MAC). Allowed: `A-Z a-z 0-9`, space and `-_.`, at
most 16 characters. Common Latin letters with accents (å ä ö à á â é è ü ø and
their capitals) become the letter without the accent; anything else is
dropped. The name shows in the room list, in the OSD ("Netplay: Alex joined",
"Netplay: direct connection to Alex", "Netplay: playing with Alex (delay 4,
direct)" or "... through the server") and on the server's web page.

**The folder.** At core load a tmpfs is mounted at `<games folder>/_Netplay`
(48 MB, `noexec,nosuid,nodev`), with two subfolders. On the SD card only the
empty mount point `_Netplay` (and `netplay/index-<core>.txt`) is created; games
and rooms are in RAM.
- `Server games/`: the server's games, fetched with an md5 check, at most 32 MB in total.
- `Rooms/`: one folder per waiting room, `<name> - <game>/`, with the game in it
  under the host's file name, `<game>.nes`. So the `.sav` is
  `saves/NES/<game>.sav` on both sides (the session needs the same `.sav` on
  both). Refreshed every 3 seconds (the file browser re-reads a folder when it
  is opened). The game comes from `Server games/` or an own copy with the same
  md5 (searched in the games folder, `.nes` up to 4 MB, not in zip files; cached
  in `netplay/index-<core>.txt`, only entries whose file has the same size and
  time are used). Rooms whose game is missing, or does not fit, show as an empty
  folder `<name> - <game> (missing game)`. The room one has picked is not removed
  until the session is over (the ROM reload needs the file). One's own room is
  not listed.

**What happens when a game is loaded** (mode = the OSD option, else `mode=`):

| Loaded from | Mode | Result |
| --- | --- | --- |
| `_Netplay/Rooms/<room>/` | anything but OSD `Off` | joins that room |
| anywhere else | Host | opens a room with the game (host) |
| anywhere else | Join | joins the waiting room with the same game (md5) when there is exactly one; with several the server answers `ERR <n> rooms with this game: pick one` (the player picks a room, nobody is matched with a stranger by chance), with none `ERR no room with this game` |

**Control protocol (UDP, same port).** Packets starting with `NPS1` are for the
server; fields are separated by tabs (`\t`). Everything from the server and from
other players is untrusted: lengths and characters are checked, anything
invalid is dropped.
- `NPS1 REG` key room role name local-address core md5 game → `NPS1 OK` role
  `waiting|paired` room-id, or `NPS1 ERR` text. `room` is the host's random id
  (8 hex digits) or `*` for a join without a room (match on md5, only when
  exactly one room waits with it); after OK the
  join sends the room's id instead of `*`. REG is sent every second until OK,
  then every 3 seconds. A role is free after 15 s of silence; when a new address
  takes over the place, the old one no longer counts.
- `NPS1 PEER` name public-address local-address token: the server sends it to
  both when the room is paired, and on every REG after that. The local address
  is the other player's own claim and is used only if it is private (10/8,
  172.16/12, 192.168/16, 127/8, 169.254/16); multicast and broadcast never.
  Once a session packet has arrived, the token no longer changes (a new PEER
  then belongs to someone else's session).
- `NPS1 PUNCH` token / `NPS1 PUNCHACK` token: between the players, to the
  candidate addresses, every 100 ms for 5 s, then every second; once the direct
  path exists, every 500 ms to it. A PUNCH is answered with a PUNCHACK to the
  sender. Only a PUNCHACK with the right token (the path works both ways) makes
  the address it came from the direct path; it may differ from what the server
  saw. Session packets go through the server until then, and back through the
  server if nothing has arrived on the direct path for 2 s (hole punching goes
  on). Session packets are accepted from the server, the direct path and the
  candidate addresses (not the latter with `direct=no`).
- `NPS1 BYE` key room role: the room/place is freed at once when a session ends.
- No hole punching: `direct=no` in `netplay.ini` (everything through the server).

**HTTP (TCP, same port number), all with `?key=` except the status page `/`
while `public_page=yes` (the default; `no` asks for the key there too):** `/roms` (`md5 size name`),
`/rom?name=`, `/catalog` (`md5 name`: versions everyone brings themselves; a
game loaded in server mode that is neither there nor among the server's games
gives the OSD message "not the server's version of this game"), `/rooms?core=`
(one line per room, tab-separated: id state core md5 name game opponent), `/`
(web page with rooms and games).

- The HTTP fetches wait in 200 ms steps that are interrupted by a core change
  (2 s to connect, 5 s without data); the server's address is looked up once per
  core load.
- Test (T3): `run_udp_test.sh` against a real server: the host loads one of the
  server's games with Host, the join picks the room in `_Netplay/Rooms/`; a direct
  path and the names are required. The same with `direct=no` (relay), with
  Join + the same game (matching on md5), and with the same `.sav` on both sides.

### UDP protocol (version 1)

All integers little-endian. Every packet starts with
`magic u32 = 0x31504E4E ("NNP1")`, `type u8`, `session u8`.

| Type | Name | Contents |
| --- | --- | --- |
| 1 | HELLO | `version u8` (=1), `core_build[16]`, `rom_md5[16]`, `sav_md5[16]` (zeros if none), `settings u32`, `delay u8` |
| 2 | HELLO_ACK | the same fields + `accept u8`, `reason u8` |
| 3 | START | — (no data; an INPUT packet also counts as START) |
| 4 | INPUT | `first_frame u32`, `count u8` (≤ 16), `joy[count]` — redundant history |
| 5 | CRC | `frame u32`, `crc u32` |
| 6 | BYE | `reason u8` |

- Every INPUT packet carries the latest up to 16 local samples, so an occasional
  lost packet needs no resend. The latest window is sent again every 15 ms even
  without new frames — otherwise two stalled machines could wait for each other
  forever after a network outage.
- No traffic from the peer for 5 s during play → "connection lost", both cores
  go back to local play (CTRL=0). While waiting for START the limit is 30 s.
- A CRC from the peer is accepted already while waiting for START (the peer may
  start first).
- `settings` is a bitmask of the OSD options that matter for determinism
  (system type, RAM clear, PPU reset, extra sprites, mask edges, overscan, debug
  dots). Cheats are not included: the core forces cheats off during netplay,
  and the OSD option is hidden (left at On) when the game has no cheat file.
  A difference → `accept=0`. Read when the ROM is loaded.
- The host picks `session` (random, ≠ 0) and `delay`; the join takes them over.

### Recordings (`.npr`)

Little endian: `"NPR2"`, `rom_md5[16]`, `delay u8`, `u32 frames`, `joy[frames]`,
`u32 crcs`, `crc[crcs]`. Replay uses the recording's delay, not the ini file's.
Every OSD message from netplay is also written, with the time, to
`/media/fat/netplay/netplay.log` (for automatic tests).
Without `file=` every game gets its own file: `/media/fat/netplay/<ROM file name
without extension>.npr`, so replay finds the recording of the game being loaded.
The recording is saved when the session ends, on a core change and when a new
ROM is loaded, but only if it has frames: a session refused at the start does not
overwrite the last file, and the OSD shows the reason.

## 8. Determinism (requirements)

Must be the same on both sides, checked in HELLO:
the same core build, ROM md5, `.sav` md5 (or no file on both sides), system type
(NTSC or PAL), RAM Clear = `$00` or `$FF` (not No, not Random), PPU Reset
Behavior, Extra Sprites, Mask Edges. The core itself blocks savestate loading,
cheats and the OSD pause while netplay is active.

## 9. Acceptance tests

| # | Test | Where | Passes when |
| --- | --- | --- | --- |
| T1 | `make -C sim lint` | x86 | Verilator lint without warnings on `netplay.sv`, `ddram.sv` |
| T2 | `make -C sim test` | x86 | the testbench prints `PASS` (gate, mux, rings, tag tearing, underrun, CRC) |
| T3 | `make -C Main_MiSTer/support/netplay/test` | x86 | engine tests `PASS`, and host + join over real UDP (`PASS udp`, also through a server) |
| T4 | Quartus build | Windows/Linux with Quartus | exit code 0, no negative slack |
| T5 | Replay determinism | 1 MiSTer | `mode=record` ≥ 36000 frames, then `mode=replay`: the OSD shows "replay OK", on NROM, MMC1, MMC3 and MMC5 games. `tools/npr.py diff` compares two recordings |
| T6 | LAN lockstep | 2 MiSTers | 30 min without a CRC mismatch |
| T7 | Network faults | 2 MiSTers + netem | 30 min, 2 % loss, 30±10 ms, without a desync; an unplugged peer → error message, no lock-up |

## 10. SNES (v2, released in v0.2)

Status: built (Quartus `TIMING OK`, seed 9) against SNES_MiSTer `4c2b746`, with
Main_MiSTer patches 0013-0016 and the server's per-core folders. Tested in
simulation of the whole core (T2s, two machines with `snes_sim --netplay`, a game
after another one with `--dirty`), in T3, and on hardware: T5s PASS (LoROM, HiROM,
SA-1, GSU2, DSP-1) and two MiSTers (a DE10-Nano and a MiSTer Pi) over the
internet through the server. Known: after jumping straight from one netplay core
to the other (without a reboot from the menu) a session may not reload the ROM;
the README tells players to reboot first. Not yet investigated.
Sections 2–9 apply to SNES as well, except where this section says otherwise.
NES keeps protocol version 1 unchanged (Mesen crossplay depends on it).

### 10.1 Freeze instead of pause

The SNES core has no pause. Netplay **stops the emulated machine's clock**:
`SNES.sv` feeds `main` (CPU, PPU, DSP, SMP, all coprocessors), the joypad ports,
the block RAMs and the registers between them (`READ_PULSE`,
`VRAM_OE_N_DELAYED`) from `clk_emu`, which is `clk_sys` through Cyclone V's
glitch-free clock gate (`ALTCLKCTRL`, `ena` latched on the falling edge).
`FREEZE=1` removes rising edges of `clk_emu`; nothing else changes. The SDRAM
controller, video output, HPS interface and netplay module stay on `clk_sys`.

Clock structure (timing, T4): `clk_emu` comes from its own PLL output
(`outclk_3`, identical to `clk_sys`'s `outclk_2`), so the gate gets the same
short path from the PLL as `clk_sys`'s buffer and the two trees line up
(gating `clk_sys` itself left ~0.9 ns skew and failed setup and hold on the
crossings to `clk_mem`). The savestate channel crosses between `main` and
`ddram` through registers on `clk_sys`, with `req`/`ack` one clock later than
the data; `SNES.sdc` gives those data paths more than one clock and no hold
on the way in. Upstream's `sdram rbuf -> din` path (SDRAM read data through
`main` into write data) is a real single `clk_mem` path (DMA from ROM to WRAM
through the `dout0` bypass), so it keeps its one clock; `rbuf` sits in the IO
cell, and the fitter alone gets 1 ns less on it so the data mux stays near the
pins. `SNES.qsf` fixes the fitter `SEED` at 9.

Why not clock enables: the core's own `ENABLE` input (tied to 1) is not
bit-exact (the CPU's clock enables keep running at the DMA rate, `CPU.vhd`
~321), and holding only the clock-enable generators is not enough either.
Many registers update on every clock, for example the NMI flag and
`P65_NMI_N` (`CPU.vhd` ~598, ~633). During a freeze they take their next value
early, and the CPU then sees NMI one cycle too soon (found in simulation,
`sim/`: one byte of WRAM differed). The requirement is that **no register and
no RAM of the emulated machine changes during a freeze**. Only a stopped
clock gives that for every coprocessor without patching hundreds of processes.

- **Requirement (normative):** a run with any number of freezes of any length
  gives bit-identical outputs of the core on every emulated cycle, compared with
  a run without freezes. Proven in simulation of the whole core (T2s below,
  `snes_sim --compare`).
- SDRAM refresh continues during a freeze through a new `sdram.sv` input
  `rfs_req` (edges of `RESET_REFRESH`, about every 4 `clk_sys`), starting 32
  `clk_sys` after the freeze begins (a read in flight completes first) and
  ending 32 `clk_sys` before it ends. It only refreshes, from the controller's
  idle state, in the clocked logic: `rd0` (= `~ROM_OE_N`, frozen) makes no edge,
  so no read is issued, the latched address stays, and the first access after
  the freeze behaves as without one. Kept out of the combinational path from
  the CPU's address to the SDRAM command, which is timing-critical. (Not
  modelled in `sim/`, which treats SDRAM as ideal memory.)
- **Video:** the PPU's sync stops with the clock. `HDMI_FREEZE` is the freeze:
  the framework's `video_freezer` keeps sync going (learnt from the frames
  before) and the scaler stops writing its frame buffer, so HDMI shows the last
  picture. The freeze ends as soon as the input is there, at any raster
  position, as the framework allows for a pause; a stall costs only the wait.
  Analog video is black during a freeze.
- Outside netplay `FREEZE=0` and the core behaves as upstream (shown in
  simulation: identical per-frame hashes with the gate in place).

### 10.2 Frame tick and input

- **Frame tick** = main's `VBLANKn` falling (the PPU's start of VBlank, after
  line 224, or 239 with overscan), seen in emulated time: `rtl/netplay.sv` updates
  its copies of emulated signals only when `emu_en` (the gate's `enaout`) is 1,
  which makes them behave like `clk_emu` registers. Frame k starts on the first
  emulated edge after the tick; on that edge INPUT[k] is applied, LOCAL[k] and
  CRC[k-1] are posted.
- **Freeze at the tick:** if INPUT[k] is not in hand when the tick is seen,
  `freeze` goes high in the same `clk_sys` cycle and the gate removes that
  edge, so the machine waits exactly before frame k. There is no underrun
  error on SNES. `ERROR` holds the freeze.
- **Input** is 12 bits per player, `joy0[11:0]` as the framework delivers it
  (`J1` line of `CONF_STR`): bit 0 Right, 1 Left, 2 Down, 3 Up, 4 A, 5 B, 6 X,
  7 Y, 8 L, 9 R, 10 Select, 11 Start. Bit 12 (the savestate button) is never
  sent. Netplay switches
  the `JOYSTICK1` inputs of `ioport port1/port2` only at the tick and holds them
  constant until the next one.
- **Ticks count only after reset:** after PRIME the core leaves reset at the
  PPU's next `HVCNT_ATZERO`, up to two frames later, while the PPU's counters
  and VBlank keep running. `rtl/netplay.sv` counts ticks only while `RESET_N`
  (`machine_run`) is 1; `RESET_N` rises on that emulated event, so frame 0
  starts at the same emulated moment on both sides. (Found by review; `snes_sim
  --netplay` starts the two sides up to 2.5 frames apart and fails without it.)
- While netplay is active: multitap, mouse, lightgun, Miracle piano, SNI (also
  its SDRAM/BSRAM access), `raw_serial` (SNAC), cheats/Game Genie, savestates,
  turbo and GSU turbo are off; OSD reset and *Load Backup RAM* are ignored. Any
  download (game, SPC, MSU data, savestate file) during PRIME/RUN gives `RELOAD`.
  In `ERROR` the machine stays frozen except while a ROM loads.
- Refused (non-deterministic, they depend on wall-clock time or HPS streaming):
  MSU-1, S-RTC, SPC7110 with RTC, BS-X, Satellaview, the competition carts
  (Campus Challenge '92, PowerFest '94: their timers run on wall-clock time),
  and the SPC player.
- The DSP's register RAM is written to zero while `RST_N` is low (a ROM load
  resets the core): upstream kept the last game's registers, the SPC driver
  reads them, and CPU/SMP timing then differed between a MiSTer that ran other
  games and one freshly loaded (Contra III desynced). `snes_sim --dirty` with
  `DIRTY_COMPARE` checks a game after another one against a fresh machine.
- Risk, not verified: RAMs inside `main` that the ROM load does not clear
  (SA-1 I-RAM, GSU cache, DSPn data RAM, OAM) start with whatever the last game
  left. Both sides load the same ROM after a core load, but a game that reads
  them before writing could differ after different histories. T5s/T6s on
  hardware with SA-1/GSU games must cover it.

### 10.3 Mailbox

As section 4, with these differences:

- Base **`0x3FC00000`** (SNES savestates use `0x3F800000`–`0x3FBFFFFF`, MSU-1
  data up to `0x3F7FFFFF`). Reached through a new channel 3 in `rtl/ddram.sv`:
  single 64-bit words, toggle handshake (the controller runs on `clk_mem`), no
  read cache (channels 1 and 2 cache two words, which would hide the HPS's
  writes), read data taken even when `DDRAM_BUSY` is high in the same cycle.
- `MAGIC` = `"SNESNP01"`.
- `LOCAL`: `hi = lo = {f[11:0], sess[7:0], joy[11:0]}`.
- `INPUT`: `hi = {f[11:0], sess[7:0], p2[11:0]}`, `lo = {f[11:0], sess[7:0], p1[11:0]}`.
  The 12-bit frame tag is enough: the rings have 256 slots.
- `CRC`: as NES, a CRC-32 of the frame's pixels (RGB at the emulated dot
  enable), seeded with the frame's input.

### 10.4 HPS, protocol and server

- One Main_MiSTer for both cores: the core name selects NES or SNES (file
  extensions `.sfc`/`.smc`, `saves/SNES/`, the SNES OSD bits for `settings`).
- OSD *Netplay: netplay.ini/Off/Host/Join* is `O[59:58]` in the SNES core.
  `settings` for HELLO: Video Region `[15:14]`, ROM Header `[3:1]`, Pseudo
  Transparency `[16]`, Audio Clock `[30]`, Initial WRAM `[22:21]` and ARAM
  `[45:44]` (any pattern: each is fixed), SuperFX FastROM `[46]`, Sufami swap `[31]`.
  Turbo, SuperFX turbo, cheats, savestates, multitap, mouse, Super Scope,
  Miracle piano, SNAC and swapped joysticks are forced off by the core.
- UDP: for SNES the protocol version is 2: HELLO has a `system u8` (1 = SNES)
  right after `version`, and every input sample in INPUT is a `u16` (12 bits
  used). NES packets stay version 1, byte for byte. A peer of the other
  console is refused with "another console" (`REJ_OTHER_SYSTEM`, 12), sent in the
  peer's own format so a version 1 peer (an older build, Mesen) can read it (it
  shows a generic "Rejected" if it does not know code 12); a game that needs MSU-1, BS-X, a real-time clock (S-RTC, SPC7110 with RTC) or the
  competition carts' timers with `REJ_CHIP` (11). Checked when the ROM is loaded:
  a `.bs` file, a `<rom>.msu` next to it, the ROM type from `snes_get_header()`.
- The mailbox is mapped at `0x3FC00000`; `MAGIC` is "SNESNP01".
- Recordings: `NPR3` = `"NPR3"`, rom md5[16], u8 delay, u8 system (1),
  u32 frames, u16 joy[frames], u32 crcs, crc[crcs]. NES keeps `NPR2`.
- Server: one lobby for both systems. `/roms` and `/rom` take `&core=`:
  `roms/<core>/`, for NES also `roms/` itself (and without `core`, as older
  clients and Mesen ask). Rooms already carry the core; a MiSTer lists only
  rooms of the loaded core. SNES games up to 8 MB, the server reads up to 16 MB.
- Lobby on the MiSTer: game files `.sfc`/`.smc` (up to 16 MB), room files
  `<game>.sfc` (or the extension of the copy found), `.sav` under
  `saves/<core>/`.

### 10.5 Tests (SNES)

| # | Test | Passes when |
| --- | --- | --- |
| T2s | Whole SNES core in Verilator (VHDL through GHDL, `make -C SNES_MiSTer/sim`), a real ROM; `snes_sim --compare SEED` runs a frozen and an unfrozen machine side by side | no output differs on any emulated cycle for ≥ 200 frames with random freezes, on LoROM, HiROM, SA-1 and GSU games; also identical per-frame hashes (video, audio, WRAM, VRAM, ARAM) with and without the gate |
| T2n | The SNES netplay module with the real core: `snes_sim ROM --netplay SEED [--delay D] [--latency CYCLES]`, two machines, a fake HPS each, a network with random latency, the sides starting up to 2.5 frames apart | `PASS netplay`: the same CRC for every frame and the same WRAM at the end, also with stalls |
| T3 | as section 9: engine tests with SNES (words, wide packets, HELLO v2, a lossy SNES session, SNES vs NES refused, settings), and `NP_SYSTEM=snes` UDP runs: direct, OSD, server, server Join same game, server `.sav` | `PASS` |
| T4 | Quartus build of the SNES core | `TIMING OK` |
| T5s | Replay on one MiSTer, ≥ 36000 frames | "replay OK" on LoROM, HiROM, SA-1 and GSU games |
| T6s | Two MiSTers through the lobby | 30 min without a CRC mismatch |

## 11. Game Boy 2P (v3, in progress: the core (T2g, T2n, T4), Main_MiSTer and the server (T3) done; hardware (T5g, T6g) open)

**Goal:** two MiSTers play a Game Boy link-cable game, one player per board,
with the same lockstep as NES and SNES. Base: the split-screen core
Gameboy2PUW_MiSTer by pomstazlesa (branch `Gameboy2P`, `83e167f`, 2025-10-05,
GPL like the MiSTer-devel Game Boy core it forks), a new upstream
`Gameboy2P_MiSTer/` on branch `netplay` with its commits in
`patches/Gameboy2P_MiSTer/`. Release file `_Netplay/GAMEBOY2P_netplay_<date>.rbf` (section 1.1); the
core's name stays `GAMEBOY2P` (games and saves in `GAMEBOY2P/`). Needs the
SDRAM board, as the original.

**Why this core:** it has two complete Game Boys (`gb1`/`gb2`, each with its own
cart, cart RAM and speed control) in one FPGA and a link cable *inside* it
(`ser1_*` ↔ `ser2_*`, the user port is not used). Every MiSTer runs both
Game Boys; the host's controller drives `gb1`, the join's `gb2`. The network
only carries input, so the link cable's timing (a byte about every 1 ms at
8 kHz) never meets the network's latency. A link cable over UDP between two
one-player cores would need a round trip per byte and is not done.

**Phases:**
- **11.A** (v3): lockstep for one or two ROMs; the `.sav` as on NES (the same
  file or none on both sides).
- **11.B** (later): each player brings their own save (section 11.6).

**Out of scope:** more than two players (the core has two Game Boys; four
would need four cores, about 720 KB of block RAM against the DE10-Nano's
~700 KB, more SDRAM ports and the 4-player adapter DMG-07), spectators,
MegaDuck (refused: `REJ_SYSTEM` for System = MegaDuck or a `.bin` game), Super Game Boy (not in the core), a real
link cable on the user port.

### 11.1 One clock for both Game Boys

Today each Game Boy has its own `speedcontrol`. It skips clock enables while
that core's ROM read waits for the SDRAM (`romread`/`romack`), and `clkdiv`
is not reset. So the two cores drift against each other by a number of
`clk_sys` that depends on the SDRAM's refresh phase. The internal link
samples the other core's serial clock on its own `ce`, so the drift is
visible to the games. Without netplay it does no harm. With netplay the
drift differs between the two MiSTers (and after every stall), which gives a
desync.

- **Requirement (normative):** both Game Boys get the *same* `ce`, `ce_n` and
  `ce_2x` on every `clk_sys`. One `speedcontrol` drives both: it waits
  (`WAITRAM`) while a ROM read of *either* core is not acknowledged. After
  reset falls it gives no enable until its divider reaches its own `ce`
  phase, so the first enable after reset is always a `ce`; the divider is
  never restarted, so its phase mod 4 (and `ce_2x`) stays locked to the SDRAM
  controller's free-running divider as upstream (`rtl/speedcontrol_shared.sv`).
  A restart at reset fall put the ROM reads at a random SDRAM phase on every
  reset: the core ran slower than real time and the sound was bad, differently
  after every load (found on hardware).
- **SDRAM:** the controller (`rtl/sdram.sv`) serves one read per cycle, port
  1 first. On one clock enable the two Game Boys of one game read the same
  word at the same time, so port 2 takes port 1's data (the word it read last,
  or the read it starts in the same cycle) instead of a read of its own a cycle
  later; a write (ROM download) forgets the last addresses. Measured in record
  mode on hardware: 59.06 frames/s without this (bad sound), 59.66 with it,
  59.70 with upstream's per-core speed control. Two different games still
  collide more often. "Sync Video" (`pausevideo`, `O[5]`) is forced off while
  netplay is active.
- **Freeze:** netplay stops the machine with one more input to that
  `speedcontrol`, `hold`, which skips enables exactly like `WAITRAM` (no
  `ce`, `ce_n` or `ce_2x` while it is 1). The SDRAM, `lcd.v`, the video output
  and the HPS interface keep running. `lcd.v` double-buffers, so HDMI and
  analog video show the last picture during a freeze, with no blackout and no
  repeated frame beyond the wait.
- **Proof (normative):** a run with any number of freezes of any length gives
  bit-identical outputs of both cores on every emulated `ce`, compared with a
  run without freezes and with different SDRAM latencies (T2g). If skipping
  enables is not bit-exact (logic on `clk_sys` between enables, as found in the
  SNES core), the freeze becomes a gated clock as in 10.1, and the
  requirement stays the same.

### 11.2 Frame tick and input

- **Frame tick** = every 70224th `ce` after reset (one Game Boy frame at
  single speed: 154 lines × 456 dots; the shared enable runs in both speeds).
  It is not the LCD's vsync: a game may turn the LCD off, and the two cores
  have one each. Frame 0 starts at the first `ce` after `hold_reset` falls.
  Frame k starts at tick k. The tick, `LOCAL[k]`, `CRC[k-1]` and the input
  switch happen on that `ce`. Once the last `ce` of frame k-1 has passed,
  `hold` is 1 as long as `INPUT[k]` is missing, so no `ce`, `ce_n` or `ce_2x`
  follows until it is there: the machine waits exactly at the frame
  boundary; no underrun error (as SNES).
- **Input:** 8 bits per player, `joystick_N[7:0]` as the framework delivers it
  (`J1,A,B,Select,Start`): bit 0 Right, 1 Left, 2 Down, 3 Up, 4 A, 5 B,
  6 Select, 7 Start. `joy1_*` (gb1) take player 1, `joy2_*` (gb2) player 2.
  Both are switched only at the tick.
- **Reset:** `hold_reset` is ORed into `reset` (both cores, both carts, the
  speed control). The RAMs are not part of the upstream reset, so
  while netplay is active `gb2p_machine` clears them once when reset rises
  (the `rtc_clr` pulse of the RTC bullet below starts it): 2^17 `clk_sys`
  writing 0 through the savestate port of WRAM, HRAM, VRAM, OAM (both Game
  Boys) and the cart RAM (both carts); savestates are not used in this core.
  The clear's cart RAM writes are masked from `sav_pending` (no autosave of
  them). The ROM download and the `.sav` load of the session's reload come
  after it, so a MiSTer that ran other games before starts like a fresh one
  (the DSP-register lesson from 10.2). `sim --dirty` checks it as on SNES;
  it found the gap with Tennis (reads RAM before writing it), not with
  Tetris.
- While netplay is active: OSD reset, the user button, *Reload Backup RAM*
  (`R9`) and *Sync Video* are ignored; *Save Backup RAM* and autosave still
  write the file. Rumble only drives the local pad. A game download during
  PRIME/RUN gives `RELOAD`. The core has no cheats, savestates, OSD pause or
  fast forward, so nothing else needs to be turned off.
- **RTC:** the README says no RTC, but `gb1`'s cart (MBC3, HuC3, TAMA) runs
  one: it starts from the HPS's `TIMESTAMP` (wall-clock time) and counts a
  32768 Hz enable made from `clk_sys`, which keeps running during a freeze.
  While netplay is active the enable counts emulated cycles instead (every
  128th `ce`, `gb2p_machine` input `rtc_emu`) and `RTC_time` is the host's
  value, sent in HELLO, on both sides. `gb2`'s cart gets the same `RTC_time`
  and enable (only `gb1`'s saves its timestamp).
- **RTC start state:** the RTC registers of MBC3, HuC3 and TAMA are not part of
  the reset upstream, so a clock a game set before the session (and its
  sub-second phase) would carry over. While netplay is active they are
  cleared once when reset rises (`rtc_clr`, in both carts: sub-seconds,
  seconds, minutes, hours, days, flags, latched copies, the pending catch-up);
  a `.sav` loaded during that reset then sets them as usual. The catch-up of
  the time since the `.sav` was written (`diffSeconds`, MBC3 and HuC3) counts
  one second per emulated `ce` instead of per `clk_sys`, so it ends at the
  same emulated moment on both sides. Checked by `npsim/make_rtctest.py`
  (T2n with `--dirty rtcdirty.gb`).

### 11.3 Mailbox

As section 4, with these differences:

- The core does not use DDR3 (`DDRAM_*` were tied off), so a one-channel
  controller, `rtl/np_ddram.sv`, serves only the mailbox: single 64-bit
  words, toggle handshake, no read cache, read data taken even when
  `DDRAM_BUSY` is high. The module is `rtl/netplay.sv`, reset by `~pll_locked`.
- Base **`0x3C000000`** (as NES; a core uses one mailbox at a time and
  `MAGIC` tells them apart), `MAGIC` = `"GB2PNP01"`.
- `LOCAL`, `INPUT` and `CRC` words exactly as section 4 (8-bit input,
  16-bit frame tag).
- `CTRL[2]` = 1 on the join (it plays `gb2`). The module latches it when it
  arms; while netplay is active only the local pad rumbles, with the rumble
  of the Game Boy it plays (`gb1` on the host, `gb2` on the join), and the
  second pad not at all.
- **CRC** of frame k: CRC-32 as section 5, seeded with `p1` and `p2`, then fed
  on every emulated `ce` with `gb1`'s pixel (`lcd1_data`, 15 bits, low byte
  first) when `lcd1_clkena`, then `gb2`'s when `lcd2_clkena`, then with
  `{4'b0, ser2_data_out, ser2_clk_out, ser1_data_out, ser1_clk_out}` when
  those four link lines differ from their value at the previous `ce`. The
  link lines cover frames with both LCDs off. Unlike NES and SNES, frame 0 is
  hashed too: after reset everything starts at the first `ce`.

### 11.4 Loading one or two ROMs

The core loads two different games in two steps: a game loaded with *Rom for
second GB* (`O[6]`) Off goes into both Game Boys; one loaded with it On goes
only into `gb2`. Both reset on every game load.

- Main_MiSTer tracks the pair: a load (index 1) with `O[6]` Off sets ROM 1 =
  ROM 2 = that file, one with `O[6]` On sets ROM 2. Every game load starts or
  restarts the session with the current pair, as on NES. A load with `O[6]`
  On before any game 1 starts no session ("load game 1 with Rom for second GB
  Off").
- The session's reload does the same: first `UIO_TIMESTAMP` with the
  session's `rtc_time` (11.2), then ROM 1 with `O[6]` Off, then ROM 2 with
  `O[6]` On if it is another file. Main sets `O[6]` itself
  (`user_io_status_set`) and restores the player's setting afterwards. The
  `.sav` mounted is the one of the last loaded game, as the core does without
  netplay: with two games ROM 1 is sent without one, ROM 2 with it.
- Boot ROMs (OSD indexes 4, 5, 6, or `boot*.rom` at core load, index 0 with
  any extension bits): `boot_md5` in HELLO is the md5 over `{index u8,
  md5[16]}` of each loaded boot file, in order of the index byte, the last
  file per index; zeros when none was loaded since the core. This includes the
  boot ROMs Main reloads from `GAMEBOY2P.f4`–`.f6` when the core loads (before
  `netplay_start()`). A boot ROM loaded while a session exists starts the
  session again with the current pair. They change the boot and the fast-boot
  choice.

### 11.5 HPS, protocol and server

- `System` gets `SYS_GB2P = 2`, chosen by the core name `GAMEBOY2P`. Games
  `.gb`/`.gbc` up to 8 MB, saves under `saves/GAMEBOY2P/`. OSD *Netplay:
  netplay.ini/Off/Host/Join* is `O[47:46]` (free in the core's status map).
- UDP **version 3** for GB2P: as version 2 (a `system u8` = 2 after `version`,
  input samples `u16`, 8 bits used), and HELLO and HELLO_ACK carry, right after
  `sav_md5` and before `settings`: `rom2_md5[16]` (the same as `rom_md5` for one
  game), `boot_md5[16]` (11.4) and `rtc_time u32` (the sender's local time as
  Unix seconds, as Main sends `TIMESTAMP` at core load). Both sides use the
  host's `rtc_time` from HELLO_ACK. A different `rom2_md5` gives `REJ_ROM`, a
  different `boot_md5` `REJ_SETTINGS`. NES (v1) and SNES (v2) packets are
  unchanged. A peer of another console gets `REJ_OTHER_SYSTEM`, in the HELLO
  version the peer sent (1, 2 or 3), so older builds can read it. `CTRL[2]`
  is written by the join on every CTRL write while enabled.
- `settings` for HELLO: System `[15:14]`, Mapper `[41:39]`, Extra sprites
  `[44]`, GBC/GBA mode `[37]`, Fast boot `[42]`, Audio mode `[43]`, Dupe save to
  GB 2 `[11]`, and the extension number of game 1 and game 2 (bits 7:6 of the
  index byte: `.gbc` 0, `.gb` 1, `.bin` 2), because with System Auto the
  extension of the game loaded last picks GBC or DMG mode. Video and audio output options (palette, colors, inversion,
  scale, audio select, separator line, *Show*) and rumble are local.
- **Own Game Boy (local options):** *Show* `O[24]` = *Both screens* or *My
  screen*: the Game Boy this MiSTer plays (`gb2` on a join while netplay is
  active, `gb1` otherwise) as a 160x144 picture (aspect 10:9) in the middle
  of the 320-pixel line, 80 blank pixels on each side as upstream's SGB
  border; the pixel rate and line length do not change, only the visible
  width, so Main sees a new size and takes the new aspect ratio. Full
  height at 10:9 is the largest picture without losing lines or distorting
  it, so there is no zoom.
  *Audioselect* `O[17:16]` is *Own GB*, *Other GB*, *Mixed*, *Split own=L*,
  with "own" the same Game Boy, so the default plays the player's own sound.
  Without netplay both behave as upstream (GB 1 = own).
- Recordings: `NPR3` with system 2, and `rom2_md5[16]` and `rtc_time u32` after
  the system byte; a replay starts the cart RTC at the recorded `rtc_time`.
- **Server:** the core field in REG is `GB2P`; games in `roms/GB/` (`.gb`,
  `.gbc`, up to 8 MB). A room has one md5 for one game. For two games, `md5`
  is `rom_md5` + `rom2_md5` (64 hex digits) and the game name is
  `<game 1> + <game 2>` (up to 170 characters for `GB2P`, 80 for the others);
  GB2P game names keep the file extension, so a join's room files get the
  host's (GBC or DMG mode, above); a join without a room matches on both. On the MiSTer
  the room folder holds both files (named from the game name, split at its
  last ` + `), and loading either one joins the room, also with *Rom for
  second GB* On. Main then loads the
  pair itself (11.4); the `.sav` is that of game 2 (the last loaded). A
  64-digit md5 is accepted only with the core `GB2P`. The status page has a
  Game Boy 2P library (`roms/GB`).

### 11.6 Own saves (11.B, later)

The point of trading and battling (Pokémon and similar) is that each player
plays with their own save, and in lockstep both MiSTers need the same one.

- Each player's own save is the single-player `saves/GAMEBOY/<game>.sav` of
  the normal Game Boy core (at most 128 KB), or none.
- After HELLO the two sides exchange their saves in new packets `SAVE_DATA`
  (`offset u32`, `total u32`, up to 1024 bytes, also through the server's
  relay) and `SAVE_ACK`, checked against an md5 in HELLO. Each MiSTer builds
  the same 256 KB image {host's save, join's save} (the core's layout:
  `sd_lba[8]` selects the half) in RAM and mounts it instead of
  `saves/GAMEBOY2P/<game>.sav`.
- When the session ends without a desync, each side writes only *its own*
  half back to its own file, after a copy to `<game>.sav.bak`. The other
  player's half is never written to disk.

### 11.7 Tests (Game Boy 2P)

| # | Test | Passes when |
| --- | --- | --- |
| T2g | Both Game Boys in Verilator (VHDL through GHDL as for SNES), real ROMs; a frozen and an unfrozen machine side by side, the SDRAM model with random latency on both | no output of either core differs on any emulated `ce` for ≥ 600 frames, on a DMG game, a GBC game in double speed and Tetris in a two-player match (link every frame) |
| T2n | The netplay module with the real core, two machines, a fake HPS each, random network latency, sides starting at different times | `PASS netplay` (the same CRC every frame) |
| T3 | Engine tests (HELLO v3, two ROMs, boot md5, settings, GB2P vs NES/SNES refused) and `NP_SYSTEM=gb2p` UDP runs (direct, server, server with two games) | `PASS` |
| T4 | Quartus build of the GB2P core | `TIMING OK` |
| T5g | Replay on one MiSTer, ≥ 36000 frames | "replay OK" on Tetris (2P), Dr. Mario (2P) and a GBC link game |
| T6g | Two MiSTers through the lobby | 30 min of a two-player match without a CRC mismatch |
| T7g | 11.B: own saves | after a trade both `.sav` files hold the traded result, each only its own half changed |

## 12. Arcade (v4, in progress: Main_MiSTer and the server (T3), the core (T2a, T4) done; hardware (T5a, T6a) open)

Netplay for arcade cores, starting with Bubble Bobble. The protocol, the server
and the lockstep model are the same as for NES, SNES and Game Boy 2P. The
difference: there is no game file. A MiSTer arcade game is an MRA, from which
Main assembles the ROM out of the player's own zip, so nothing is reloaded or
sent. Both sides check instead that they assembled exactly the same ROM.

### 12.1 The core

- The arcade cores update_all installs for Bubble Bobble are Jotego's
  (`jtbubl` from `jotego/jtcores`, MRA `<rbf>jtbubl</rbf>`). Netplay is built
  into those, in their common framework **jtframe**, so the same work serves
  the other jtframe cores later.
- **The netplay core sits next to Jotego's, it never replaces it:** file
  `_Arcade/cores/jtbubl-netplay_<date>.rbf`, loaded by its own MRA, a copy of the
  player's *Bubble Bobble (US, Ver 5.1)* MRA (English; set `bublboblr`, from
  `bublbobl.zip`) with `<rbf>jtbubl-netplay</rbf>` and ` [netplay]` in its name (`tools/deploy.sh <ip> arcade`). Main picks the core for
  `<rbf>jtbubl</rbf>` as the last file named `jtbubl` + `.` or `_`, so the `-`
  keeps the normal MRAs on `jtbubl.rbf`; update_all does not touch the netplay
  files. Both players use the netplay MRA (the ROM check does not depend on the
  MRA's file name). (The `neptuno-fpga` Bubble Bobble repository is
  Jotego's older port for another board, not the MiSTer core.)
- Jotego builds MiSTer cores with Quartus 20.1 (`jotego/jtcore20`); see 12.6.

### 12.2 Main_MiSTer: the game and the session

- `System` gets `SYS_ARCADE = 3`, chosen for a core loaded from an MRA
  (`is_arcade()`) whose configuration string has the option
  `O[127:126],Netplay,netplay.ini,Off,Host,Join` (status bits `[127:126]`,
  the same values as the other cores' *Netplay*). Arcade cores without it are
  not touched.
- `mra_loader.cpp` calls three hooks: `netplay_note_arcade_rom(index, md5)`
  when a `<rom>` node is finished (the md5 Main already computes for
  `asm_md5` over the data it sent), `netplay_note_arcade(xml, nvram)` at the
  end of `arcade_send_rom()`, after the ROMs and the DIP switches have gone to
  the core, and `netplay_note_dip()` in `arcade_sw_send()`.
- **The ROM check.** `rom_md5` in HELLO is the md5 over `{index u8, md5[16]}`
  of each `<rom>` node that sent data, in index order, the last node per index
  (as the core holds it; a later `index="0"` node after a valid one sends
  nothing and does not count) (`rom2_md5` = `rom_md5`). So
  the ROM data, the order Main assembled it in and the core's header bytes (for
  Bubble Bobble the PCB type and `<rom index="1">`) all count, but not the
  MRA's or the zip's file name. A difference gives `REJ_ROM`, shown as
  "Different ROM set (MRA or zip)". `core_build` is the core's `V,` string
  (jtframe: the commit), so a core that update_all has updated on only one side
  gives `REJ_CORE`, "Different core version (update both)".
- **Starting a session.** The MRA load is the game load: `netplay_note_arcade`
  starts a session with the OSD *Netplay* option, or `mode=` in `netplay.ini`
  for *netplay.ini*. As there is no later game load, a change of the OSD
  option while the core runs starts (Host, Join) or stops (Off) a session. A
  change counts once the OSD is closed, or after it stood 1.5 s with the OSD
  open, so stepping through Off, Host and Join does not start sessions.
  A DIP switch the player changes in the OSD starts the session again (12.4).
- `sav_md5` is zeros. A game whose MRA has `<nvram>` is refused
  (`REJ_NVRAM`, "Games with NVRAM are not supported yet"): its NVRAM is the
  player's own and has changed since it was loaded.
- The OSD Reset, the cheats and the pause are the core's matter (12.3).

### 12.3 The core's netplay module (requirements)

The module is the GB2P/NES one (`rtl/netplay.sv`, the same states, CTRL and
rings), added in jtframe so every jtframe core gets it:

- Mailbox at `0x3C000000` as NES and Game Boy 2P, `MAGIC` = `0x3130504E44435241`
  ("ARCDNP01"). The address must not collide with the DDR3 a jtframe core uses
  itself: screen rotation writes at `0x24000000`–`0x2BFFFFFF`, so it does not.
  The mailbox shares the video DDR3 client (`jtframe_np_ddrarb`): rotation keeps
  priority, the mailbox takes the bus between two of its writes. Cores whose
  video client reads DDR3 (the DDR3 line-frame buffer, `JTFRAME_MR_GAME_DDR`)
  are refused at build time.
- Code: `target/mister/hdl/jtframe_netplay.sv` (the protocol),
  `jtframe_np_board.sv` (controls, reset, pause between the board and the game;
  also used by the Verilator test bench), `jtframe_np_ddrarb.sv`; the macro
  `JTFRAME_NETPLAY` (in the core's `macros.def`, `[mister]`) builds it in and
  adds the OSD option.
- **Frame tick:** the start of the emulated vertical blank (jtframe `LVBL`
  falling), from the game's own video timing: frame k starts on the first
  clock in which the game's `LVBL` reads low.
- **Freezing the game.** Everything a jtframe game does advances on clock
  enables: the ones `jtframe mem` generates from `mem.yaml` (`jtframe_gated_cen`,
  CPUs and sound) and the pixel enables (`jtframe_pxlcen`, video). With
  `JTFRAME_NETPLAY` both get a `hold` input that freezes them completely: no
  pulse is lost and none is caught up afterwards, so a held clock does not exist
  for the game. The clock in which a frame starts is always held, plus 4 more,
  so INPUT[k] reaches the game before its next enable; the hold lasts as long
  as INPUT[k] is missing. The held pixel enable stops the scaler's input, so
  HDMI repeats the newest frame; `HDMI_FREEZE` is not used (a freeze where a
  frame ends makes ascal skip a buffer switch and show a frame two frames old
  once: a flicker on every stall, seen on hardware). Only cores
  whose game logic runs entirely on those enables qualify (checked per core;
  `jtbubl` does).
- **No SDRAM in the game's timing.** jtframe holds a CPU's clock enable while
  its ROM read waits for the SDRAM and catches the lost pulses up afterwards,
  while the pixel enables do not wait. The SDRAM's latency (its refresh phase,
  the other buses) differs between two MiSTers, so the order of the CPU, sound
  and pixel enables differed too: measured in the test bench, 58 of 60 frames
  with the same picture, and on hardware DESYNC after 876 and 13863 frames.
  Waiting without catching up would cost the time the CPUs wait (12 % for
  `jtbubl`). So with `JTFRAME_NETPLAY` the CPUs read their ROMs from block RAM
  (`mem.yaml` `mainrom`, `subrom`, `sndrom` with `when: [JTFRAME_NETPLAY]`,
  loaded from the same download; the SDRAM buses stay for the layout and are
  left idle): a read's `ok` drops for exactly the clock after an address change.
  Only the graphics read the SDRAM, which decides no game timing. `jtbubl`:
  465 of 553 RAM blocks. The test bench checks the order of the enables per
  frame (`np_ilv`): identical in all frames.
- **The CRC covers the game state** (`JTFRAME_NP_STATE`): every write of the
  main and sub CPUs, address and data, taken in its first clock, instead of the
  picture. The graphics still read the SDRAM, and a line that is late on one
  MiSTer changes the picture without the games being out of step (a desync
  after 17522 frames with identical cores on hardware). `np_test --corrupt F`
  gives the join other input in frame F: CRC mismatch at frame F.
- The core's version (`V,` in the configuration string, compared by Main) is
  jtcores' commit, so `tools/jt_build.sh` refuses to build uncommitted changes.
- **RAM.** Block RAM keeps what the game left in it across a reset (high
  scores, for instance), so two MiSTers that played before would start a
  session from different RAM (seen on hardware: DESYNC at frames 876 and
  13863). While the game is held in reset (ARMED, PRIME) every game RAM is
  written with zeros through `jtframe_np_ramclr`, in front of each RAM's first
  port (`np_ram` = 1; the address steps on the RAM's clock enable). For
  `jtbubl`: work and comm RAM, the four VRAMs, the two palette RAMs, the sound
  CPU's RAM (`jtframe_sysz80`) and the MCU's internal RAM (`jtframe_6801mcu`,
  whose simulation model cleared it on reset while the FPGA did not: netplay
  sims no longer do). The test bench's `--dirty-ram` fills the join's RAM with
  a pattern before its session (`np_ram` = 2).
- **Session start.** In ARMED and PRIME the game is held in reset while its
  video timing runs on (jtframe's video timers have no reset). Frame 0 starts
  at an `LVBL` fall once INPUT[0] and INPUT[1] are in hand: reset is released
  there and the clock enable generators restart from zero (`clr`), so both
  sides start at the same video position and enable phase. The game's line
  buffers still hold a picture from before the session, so the CRC of frames
  0 and 1 covers only the input; from frame 2 it covers every visible pixel
  (`pxl_cen & LHBL & LVBL`, 8 bits per colour).
- **Input:** 12 bits per player, entries as SNES (`{f[11:0], sess[7:0],
  joy[11:0]}` in both halves): bits 3:0 Right, Left, Down, Up; 9:4 buttons 1–6;
  10 Start; 11 Coin. The host is player 1, the join player 2; each side's own
  player 1 controls are its `LOCAL`. Service and test buttons and the tilt are
  held off.
- **Session start:** in ARMED the module holds the game in reset and clears
  the game's RAM (everything the game writes) to a fixed value, so both sides
  start equal without a ROM reload. Main sends the session's DIP switches
  meanwhile (12.4). PRIME and RUN as in section 3.
- While netplay is active: the OSD Reset, the core's pause (also the one on an
  open OSD), cheats and hiscore loading have no effect on the game.
- DIP switches (download index 254): taken in IDLE and ARMED (Main sends the
  session's in ARMED). One in PRIME or RUN (a player changed a switch in the
  OSD) sets the `RELOAD` error, so the session ends cleanly before Main starts
  it again, instead of running a few frames with other switches than the peer.

### 12.4 Protocol version 4 and the DIP switches

- UDP **version 4** for arcade: as version 3 (system byte = 3, `u16` input
  samples, of which 12 bits are used; `rom2_md5`, `boot_md5` (zeros) and
  `rtc_time` after `sav_md5`), plus `dip u64` right after `rtc_time` (before
  `settings`), in HELLO and HELLO_ACK. `settings` is 0. A peer of another
  console gets `REJ_OTHER_SYSTEM` in its own version.
- **The DIP switches are the host's.** The join takes `dip` from HELLO_ACK. In
  place of the ROM reload (section 4, step 3) Main sends the session's switches
  to the core (`arcade_sw_send`) without saving them: the player's `.dip` file
  is not changed, also not when the OSD's DIP page is opened meanwhile. Main
  remembers which session they were sent for; once that session is over (an
  end, a refusal after arming, OSD Off, a new session) the player's own come
  back. A host offers its own switches, also right after it was a join. A DIP switch changed in the OSD during a session becomes the
  player's own and starts the session again.
- Recordings: `NPR3` with system 3 and `dip u64` after the system byte; a
  replay plays with the recorded switches.

### 12.5 Server and lobby

- The core field in REG is the core's own name, the OSD's title
  (`user_io_get_core_name(1)`, `JTBUBL`), the same for every MRA of the core;
  not Main's core name, which for an MRA is its set name (`bublboblr`) and
  differs per version of a game. The game is the MRA's file name
  without `.mra`, the md5 `rom_md5` (12.2). The server needs no other change:
  rooms match on core and md5. Every core other than `NES`, `SNES` and `GB2P`
  is an arcade core: the status page shows it with an arcade badge, and an
  *Arcade* tab with the open arcade rooms in place of a library; the main
  menu's room list (below) takes these rooms and keeps those whose game is one
  of the player's MRAs.
- Arcade games never come from the server. The host loads the netplay MRA and
  picks OSD *Netplay → Host*.
- **Rooms in the arcade menu:** with `server=` set, Main mounts a RAM folder
  `_Arcade/_Netplay` once the MRA is loaded and keeps one MRA per waiting room
  of the same core in it, `<name> - <game>.mra`: a copy of the player's own MRA
  with the host's MRA name (searched in `_Arcade` and its folders; none: the
  room is not shown), with `<!-- netplay room: <id> -->` after the root tag.
  Loading one joins that room. An MRA load reloads the core and restarts Main,
  so the folder is not unmounted by `netplay_stop()` and the room is read back
  from the file; the loaded room's file stays until its session is over.
  OSD *Netplay → Join* without a picked room joins the room with the same ROM
  when it is the only one waiting (the `*` room of section 7).
- **Rooms inside the core:** with `JTFRAME_NETPLAY` jtframe's OSD has
  *Join room* (`F9,MRA,Join room`) under the Netplay option. Main's file
  browser opens it in `_Arcade/_Netplay` (that folder is its home), so the
  rooms are picked where NES and SNES pick theirs, in the core's own menu.
  `user_io_file_tx()` hands the pick to netplay (`netplay_take_file()`), which
  joins the room in the file without a core reload; nothing is sent to the
  core (jtframe ignores download index 9 anyway). Without `server=` the entry
  says "rooms need server= in netplay.ini"; with OSD Netplay Off it says so.
- **In the main menu** (no core loaded, `server=` set) Main keeps the same
  folder up to date with the waiting rooms of every arcade core (any core but
  `NES`, `SNES`, `GB2P`), so a
  player sees them before loading any MRA; loading one stops that lobby (core
  change) and the folder stays for the MRA load.

### 12.6 Open

- Building jtframe cores: Quartus 20.1 (Docker image `jotego/jtcore20`),
  `tools/jt_build.sh bubl` -> `jtcores/release/mister/jtbubl.rbf`. Quartus 20.1's own
  `libudev.so.1` crashes `quartus_map`; the script preloads the system's.
- jtframe with netplay lives in `jtcores/` (branch `netplay`, patches in
  `patches/jtcores/`), based on jtcores `15d60ca4f` (2026-10-23), the jtframe of
  the released `jtbubl` core: jtframe's MiSTer video changes of 2026-11-03..07
  draw the OSD across the whole screen width (seen on hardware). T2a: `jtframe/bin/np_sim.sh bublbobl [options]` from
  `cores/bubl/ver/np` (ROM zips in `~/.mame/roms`).

### 12.7 Tests (arcade)

| # | Test | Passes when |
| --- | --- | --- |
| T3 | Engine tests (HELLO v4 with `dip`, 12-bit words, the host's DIP switches, other ROM set, other core version, NVRAM, other console, record/replay with `dip`) and `NP_SYSTEM=arcade` UDP runs (direct, OSD mode, through a server, `direct=no`, room from the main menu, *Join room* in the core with a second host waiting with the same game, a join without a room refused while two rooms wait): no reload, both play with the host's DIP switches, the join's own come back after the session | `PASS` |
| T2a | `jtbubl` with the netplay module in Verilator, two machines, a fake HPS each | the same CRC every frame for ≥ 600 frames |
| T4 | Quartus build of `jtbubl` with netplay | timing met |
| T5a | Replay on one MiSTer, ≥ 36000 frames of Bubble Bobble | "replay OK" |
| T6a | Two MiSTers through the lobby | 30 min of a two-player game without a CRC mismatch |

## 13. GBA Wireless Adapter (v5: T2w, T2w-u, T3w and T4w done; hardware (T5w): a Pokémon FireRed/LeafGreen battle and LinkUniversal_stress (packet loss, packet sync) through the server)

Games that support Nintendo's GBA Wireless Adapter (AGB-015) play over the
internet: Apotris, Pokémon FireRed, LeafGreen and Emerald, Mario Golf Advance
Tour and others. Unlike sections 7 to 12 this is **not lockstep**: each MiSTer
runs one GBA, and the adapter is emulated. The adapter's own protocol already
lets the game wait for the other side (the "ready" handshake after every word
and the Wait command), so internet latency only slows the link down; it does not
desync anything. Link-cable games stay with the lockstep plan (GBA 2P,
`research/gba2p-plan.md`).

Sources: the adapter protocol as documented by afska and davidgfnet
(gba-link-connection, `docs/wireless_adapter.md`), and gpSP's adapter
emulation (`rfu.c`, `serial.c`, GPL-2.0-or-later, David Guillen Fandos), which
Main's adapter is ported from.

### 13.1 The core

- Base: MiSTer-devel `GBA_MiSTer` `master` (`93790a0`); it runs Apotris on the
  MiSTer (tested with its own BIOS and the user's). The core's serial port is a
  stub today (a transfer takes its time and raises its IRQ, no data moves).
- New: the serial port in **Normal mode, 32 bit**, for the adapter only
  (OSD *Link port: Off / Wireless Adapter*). With the adapter selected it
  behaves as gpSP does:
  - **RCNT** GPIO mode: SD going high resets the adapter.
  - **Internal clock** (GBA is master): writing SIOCNT with Start sends
    SIODATA32 to the adapter; the transfer ends (Start cleared, SI = 1, IRQ if
    enabled) when the adapter's answer word is in SIODATA32. While the adapter
    has no answer yet, the transfer simply lasts longer.
  - **SI/SO handshake**: internal clock: SO rising makes SI go low ("adapter
    ready"); external clock: SO rising makes SI go high, SO falling makes it low.
  - **External clock** (after Wait, SendDataWait, RetransmitAndWait the adapter
    is master): when the GBA has Start set with external clock and SI = SO = 0,
    the adapter's next pushed word lands in SIODATA32, Start clears, IRQ.
- `gba_rfu` (new, in the core) handles the word level so the HPS is asked
  **once per command, not per word**:
  - the NINTENDO handshake (13.2 rule) in the FPGA;
  - a command `0x9966LLCC` and its LL words are collected; the complete
    command goes to the mailbox; the answer (ack word with its length, then the
    data, or `0x996601ee` + error) comes back and is streamed word by word;
  - pushed words (the adapter's events in Wait mode: `0x99660028` data,
    `0x99660029` disconnected, `0x99660027` timeout, `0x99660128` with the
    missed clients) come from the HPS as a list and are sent when the GBA is
    ready for them;
  - every other GBA word is answered `0x80000000`.
- Mailbox: in DDR3, at an address the core does not use (GBA uses DDR3 for the
  second ROM copy, savestates and rewind: the address is chosen in 13.3), on its
  own `ddram.sv` channel. Words carry a sequence tag in both halves (SPEC 7
  rule: Cortex-A9 may tear 64-bit stores).

### 13.2 Handshake rule (in the FPGA)

Reset (SD high, or the core's reset) puts the adapter in RESET. In RESET it
answers `0` and moves to HANDSHAKE when the GBA's low 16 bits are `0x494E`. In
HANDSHAKE it answers `(sent << 16) | (~previous_sent & 0xFFFF)` and moves to
COMMANDS when the GBA sends `0xB0BB8001`.

### 13.3 Mailbox

At `0x3C000000` (byte offsets; every header carries its tag in both 32-bit
halves; `rtl/gba_rfu.sv` and `support/netplay/rfu_mailbox.cpp`):

| Offset | Content | Written by |
| --- | --- | --- |
| `0x000` | magic "GBARFU01" | FPGA |
| `0x008` | status `{resets16, 16'h0}` x2 (resets: SD pulses) | FPGA |
| `0x010` | command `{seq16, cmd8, len8}` x2, after its data | FPGA |
| `0x018` | command data[0..31] `{0, word}` (each word as it arrives) | FPGA |
| `0x200` | answer `{seq16, flags8, len8}` x2, after its data (flags bit 0: error, data[0] the code) | HPS |
| `0x208` | answer data[0..63] `{seq16, index16, word}` | HPS |
| `0x500` | event `{eseq16, 8'h0, n8}` x2, after its data | HPS |
| `0x508` | event data[0..3] `{eseq16, index16, word}` | HPS |

The HPS's data words carry their header's sequence number and their index,
and the FPGA reads a word again until its tag is right: the FPGA reads the
header first and may otherwise see a data word that has not landed yet (the
HPS writes through the L3, the FPGA reads through its own SDRAM port). The
event words are read right after their header, so an untagged stale word was
pushed to the GBA (Pokemon then waits 100 ms in its slave handler and resets
the adapter: "communication error").

### 13.4 Main_MiSTer: the adapter

- `support/netplay/rfu.cpp`: gpSP's command processing (Hello, Setup,
  Broadcast, StartHost, EndHost, BroadcastRead start/poll/end, PollConnections,
  Connect, IsConnectionComplete, FinishConnection, SendData, SendDataWait,
  ReceiveData, Wait, DisconnectClient, Bye, SignalLevel, VersionStatus,
  SystemStatus, SlotStatus, ConfigStatus, RetransmitAndWait) on the HPS, in the
  netplay thread; it answers a command within a few hundred microseconds.
- A host's Wait after SendDataWait or RetransmitAndWait ends with "sent"
  (`0x99660028`) as soon as every client has acked the data. Clients that have
  not acked yet are reported (`0x99660128`, bits 0-3 the clients that got it,
  bits 8-11 always clear) only after the Setup's retransmissions **and at least
  250 ms**: a real adapter retransmits within milliseconds, the internet takes
  tens of them, and Pokemon ends the link with "communication error" when it
  sees misses. Setup's retransmission count 0 means never report a miss. A
  silent client is dropped after 4 s.
- Up to 5 adapters per room (1 host, 4 clients), as the hardware.
- Started by the OSD option; `netplay.ini` `server=` and `key=` as for the
  other cores. Without `server=`: `peer=` connects two MiSTers directly.

### 13.5 Network

- v1 is two MiSTers. They pair exactly as the other cores do (OSD Netplay Host
  or Join, `peer=` or the server's rooms, hole punching, relay; SPEC 7). The room
  is the core `GBA` with the game's name, but the match does **not** require
  the same md5: FireRed and LeafGreen talk to each other over the adapter.
- On top of that pair the game's own wireless menus work as on real hardware:
  one GBA hosts (StartHost broadcasts), the other searches (BroadcastRead lists
  the peer's broadcast), connects, sends and receives. gpSP's packets (RFU1:
  broadcast, connect request/accept/reject, disconnect, host data, client data,
  client ack) go to "the other player" instead of RetroArch's netpacket peers.
- They need order and delivery: a reliable channel inside the session
  (sequence number, ack, in order; the oldest unacked packet is resent after
  1.5 round trips + 10 ms, 30 to 100 ms, the others after 100 ms: the receiver
  keeps what came after a gap, and homebrew (gba-link-connection) gives up
  after 10 frames without new data), a new packet type next
  to the lockstep ones. Packet: `NPW1` type seq16 ack16 len16 version (2)
  from32 to32, then the data. `from`/`to` are random session ids, one per
  loaded game: data and acks of another session are ignored, and a HELLO with a
  new id means the other player loaded the game again, so both sides start
  over (sequence 1, nothing old kept). The oldest packet unacked for 3 s, or
  the other side silent for 10 s: resend once a second.
- A game load with the same Netplay mode and room as before keeps the place on
  the server and the way to the other player; only the link starts over (a new
  session id). A host that opened a new room instead would leave a join that
  already got the old one asking for a room that is gone.
- More than two players (the adapter allows five) needs rooms of up to five on
  the server: later (13.7).

### 13.6 Tests (wireless)

| Test | What | Pass |
| --- | --- | --- |
| T2w | `make -C GBA_MiSTer/npsim t2w`: the whole core in Verilator with `gba_rfu`, the mailbox served by Main's own `rfu_mailbox.cpp`/`rfu.cpp`, and a second adapter as the peer; the test ROM `npsim/rfutest.s` resets the adapter (SD), does the handshake and Hello, VersionStatus, Setup, Broadcast, StartHost, SystemStatus, a refused Connect, PollConnections, Wait (event pushed by external clock), ReceiveData, SendData | all 18 results as expected and the peer receives the host's data: `PASS T2w` |
| T2w-u | `make -C GBA_MiSTer/npsim sertb`: `gba_serial` (GHDL) and `gba_rfu` in Verilator with Main's `rfu.cpp`/`rfu_mailbox.cpp`; the CPU is Pokemon FireRed's librfu (pret: `sio32intr_clock_master`/`_slave`, their SI/SO handshakes and timers) joining a host adapter over a 20-60 ms network: search, Connect, Wait, the host's data 50-275 ms later pushed as `0x99660028`, `0x80000000`, ReceiveData; also with the HPS's mailbox writes late (2-50k clocks) and out of order | `PASS sertb` in all five runs |
| T3w | `test_rfu` (two adapters in one process: the whole command flow, events, timeouts, junk and hostile packets under ASan), `test_rfu_link` (2000 packets each way over a network that loses, duplicates and reorders: all arrive once and in order; the other side loading its game again mid-game: both start over and data flows again; a peer that never acks gets resends once a second; a lockstep peer and another version are named), and `NP_SYSTEM=gba` UDP runs (direct, through the server, relay only): two Mains with a faked `gba_rfu` side, different games, find each other's room, connect, exchange data both ways; through the server, the host or the join loads its game again after the first exchange and a second exchange follows over the same room | `PASS` |
| T4w | Quartus build of GBA with the adapter | timing met |
| T5w | Two MiSTers: afska's `LinkWireless` demo and an Apotris 2-player battle over the wireless adapter through the server | the match runs to the end |

### 13.7 Later

Wireless multiboot; playing against RetroArch gpSP (its own netpacket protocol);
more than 2 players tested on hardware.

## 14. Neo Geo (v6, released in v0.6: verified in simulation (T2n, T3n) and on hardware, two MiSTers through the lobby server)

The MiSTer Neo Geo core (`NeoGeo_MiSTer`, MiSTer-devel) with lockstep netplay,
as sections 7 to 12: only the controllers cross the network, and both MiSTers
run the same frames. First version: cartridge systems in Console (AES) mode, two
players, joysticks, memory card unplugged. Not with netplay: Neo Geo CD,
multitap, spinner and mouse.

### 14.1 Determinism (normative)

**Requirement:** started as in 14.2, two MiSTers make the same writes with both
CPUs (68000 and Z80: address, data and order per CPU) in every frame, from the
first frame in which the 68000 runs, whatever the DDR3's timing, the phase the
PLL locked in, and the time between the core's load and the reset's end.

The upstream core does not meet it. What the netplay core changes:

- **The Z80's ROM (M1) is in the SDRAM**, not in DDR3. DDR3 is shared with the
  HPS and the scaler and answers when they let it; the Z80 waited 3 to 6 % of
  every frame for it, a different time on every MiSTer, and an interrupt then
  met another instruction. The core copies M1 from where Main_MiSTer puts it
  (DDR3 `$32000000`, load index 9) to SDRAM `$0100000` (the megabyte only the
  CD systems use) with its memory copy, so Main's loader is unchanged, and
  `sdram_mux` serves the Z80 after the 68000 and the graphics. The SDRAM is the
  core's own and synchronous to it: a read takes a number of clocks that
  follows from the core's state. The Z80 waits (`nWAIT`) until its byte is
  there, normally not at all (a read is done in 8 to 9 clocks of 96 MHz, the
  Z80 has 24).
- **The YM2610 never stands still for DDR3** while Netplay is Host or Join
  (`np_on`). Upstream stops its clock enable when an ADPCM byte is late; its
  timers interrupt the Z80. A late byte is then the byte before it (sound only:
  what the CPUs read of the ADPCM channels counts addresses, not data).
- **Timing constraints that hold on the hardware.** A path that the timing
  constraints allow two clocks may arrive in the first or the second, on one
  MiSTer or run otherwise than on another; simulation always takes the first.
  Upstream gave every path from the Z80 two clocks (`NeoGeo.sdc`); its bus is
  looked at on every clock (the SDRAM's M1 reads at 96 MHz, the port and NMI
  edge detectors), so only the Z80's own paths keep two clocks. Seen on
  hardware with the per-frame diagnostics (14.3): a replay on the same MiSTer
  parted from its recording at frame 10, the Z80 having waited for the SDRAM
  188 times less in frame 9, the simulation equal to the replay.
- **Counters start from the end of the reset.** The reset ends on a fixed
  raster position of the free-running picture, so what is tied to the picture
  is the same on both MiSTers; what is not must not run through the reset:
  the YM2610's clock dividers stand at zero during it and its slot counter
  starts at slot 0 when it ends (`jt12_div`, `jt12_reg`); the LSPC's timer and
  the auto-animation counters take the reset pulse `nRESETP` on any clock (it is
  one 24 MHz cycle long and missed their enables); the SDRAM's refresh counter
  of the reset phase starts again once a frame (`sdram_mux`). The LSPC's divide-by-3
  (8 MHz) and the Z80's 4 MHz (`lspc2_clk.v`) start with the reset as the
  picture does: free-running, their phase to the picture was whatever the
  FPGA's start and the time before the session left, and two MiSTers ran the
  Z80 up to 4 clocks of 24 MHz apart (seen on hardware with the trace: host
  and join apart from the Z80's first event, the join equal to the bench; the
  bench with the divider started in another state gives the host's numbers).

### 14.2 Session start

- A session starts on **a core that has not run since it was loaded** (FPGA
  configuration): the reset clears neither the RAMs nor the CPUs' registers nor
  most of the LSPC's, and a game that ran before leaves them behind (in
  simulation: 361 signals in 56 modules differ after 30 frames and a reset,
  and the 68000's first frame with them).
- So Main_MiSTer arms netplay (CTRL enable, 14.3) **before** it loads the ROM
  set, and the core's module keeps the machine in reset from then on (ARMED,
  PRIME). The reset is released at the first start of a vertical blank with
  INPUT[0] and INPUT[1] in hand and no load going on; frame 0 starts there.
  The picture runs through the reset and the machine leaves it a fixed number
  of its frames after the release (the reset counter, then the watchdog's 8
  frames): released anywhere else in the picture, one MiSTer's machine would
  start a frame earlier in the session than the other's (T2n: frame 0 of
  different lengths, the 68000's first writes in frame 7 or 8). When the machine has left reset since the FPGA
  was loaded (STATUS bit `ran`; Main_MiSTer keeps the same fact itself: a ROM set
  was loaded since the core was), Main_MiSTer loads the core (RBF) and the ROM
  set again before a session (14.4).
- The machine starts the same way however long it waited: everything is reset
  until the release (14.1, `--start-delay` in T2n).
- **Not on a boot ROM.** When the core starts, Main_MiSTer sends
  `bootrom/neogeo.rom` if the SD card has one (any core: `bootrom/<name>.rom`,
  ioctl index 0). The core normally leaves reset on the first load of any kind,
  so the machine ran that BIOS, with whatever game the SDRAM still held from
  before, until the player picked a game, and the 68000's registers kept that
  run into the session (seen on hardware: `movem` in frame 10 stored A1/A2 =
  `$C1471C`, left by the BIOS's cartridge check; 15.5 s run before the session;
  a fixed CRC per MiSTer, DESYNC at frame 10). With the OSD's Netplay option on
  (`[46:45]` not Off = 1; netplay.ini is 0) and a cartridge system, the machine therefore stays in
  reset until a game's program arrives (P1/P2, straight or as the loader's copy
  command); with Netplay Off the core behaves as before. T2n `--bootrom F`.
  The trace's first event (14.3) tells how long the machine ran before a
  session.
- **Not before the save file is in.** At the end of a load the core reads the
  game's save file (backup RAM and memory card, 72 KB) through Main_MiSTer, one
  sector at a time as Main's main loop gets to it, and holds the machine in
  reset while it does (`bk_loading`). The module counts that as a load: the
  release waits for its end. Otherwise one MiSTer's machine leaves reset later
  (the reset restarts the 8-frame watchdog reset), and the session parts where
  the machines start (seen on hardware: DESYNC at frame 8 and 11, also when
  one MiSTer replayed its own recording; T2n `--sd`). The memory card stays
  unplugged during a session, so what the file holds is never read.
- OSD: `oDE,Netplay,netplay.ini,Off,Host,Join` (status `[46:45]`), read by
  Main_MiSTer only.
- While a session is active: the session's input for both players (the host
  is player 1), memory card unplugged, no multitap, spinner or mouse, the OSD's
  Reset and the user button do nothing, the YM2610 never waits for DDR3.

### 14.3 The core's netplay module (`rtl/netplay/neogeo_netplay.sv`)

- While ARMED the module takes the session's id from every CTRL it reads: Main
  arms with session 0 before the ROM set loads, before the players agree on one.

The arcade module (12.3) without jtframe, with these differences:

- **Mailbox** at `0x3FC00000` (the Neo Geo loader stages sprites up to
  `0x3E000000`), the NES/arcade layout, `MAGIC` = `0x3130504E47454F4E`
  ("NEOGNP01"), on its own 64-bit channel of the core's `ddram.sv` (after the
  ADPCM reads, before the load-time copy). STATUS `{frame, 4'b0, ran, state,
  error, stalls}`. Input entries as arcade: 12 bits per player, `3:0` Right
  Left Down Up, `7:4` A B C D, `8` Start, `9` Select, `10` Coin, `11` the core's
  bit 11; the core's combination buttons (A+B, C+D) are folded into A–D on the
  sending side.
- **Diagnostics** (not the protocol): `DBG` at `+0x2800`, frames 0–127 of a
  session, two words each: `{Z80 write CRC, machine clocks}` and `{Z80 SDRAM
  wait samples, machine clocks the 68000 waits for the SDRAM, Z80 writes,
  68000 writes}` (Main's file still calls the second column `late`). Main_MiSTer
  clears it when a session starts and writes it with the CRCs to
  `netplay/neogeo-dbg-<mode>.txt` after frame 130 or when the session ends;
  `neogeo_sim --session` prints the same (`D` lines), so a MiSTer's run can be
  set against the bench's and two MiSTers' runs against each other. `TRACE` at
  `+0x3000`: the first 512 events of a session, 64 bits each as the core
  makes them, kind in bits 31:28, in the same file (`T` lines: bits 63:32,
  kind, 23:16, 15:0) and from the bench. `NP_TRACE68` in `neogeo.sv` picks
  the source. The Z80: `{machine clocks since the release, kind, data,
  address}` (kinds: 1 Z80 port write, 2 port read with the value read, 3
  interrupt acknowledge, 4 NMI, 5 YM2610 IRQ line, 6 the 68000's sound
  command). The 68000 (the default since the Z80 matched): 7 a write whose
  data or strobes differ from the last one traced in its part of the map
  (eight parts), with the machine clock in the frame in units of 8, its
  address (bit 16 left out) and data; 8 the start of each frame; 9 an
  interrupt acknowledge; 10 a read outside the BIOS ROM and the LSPC, as 7;
  11, the first event, made at the release: the machine clocks it ran before
  the session (since the FPGA was loaded), times armed, times dropped to IDLE
  (all, and for a dead heartbeat). `npsim/trace68.py` decodes one file or
  compares two.
  Seen with it on hardware: a recording equal to the bench event for event
  and clock for clock; one replay of it with a single bit different in a
  value the Z80 had read from memory (01/09, event 173), another replay equal
  throughout (8279 frames).
- **Heartbeat:** CTRL `{"CTRL", heartbeat[15:0], session, 4'b0, join, run,
  enable}`. Main_MiSTer changes the heartbeat all the time (at least every
  0.1 s). IDLE arms only when the heartbeat moved between two reads, so a CTRL
  word left in DDR3 by an earlier session never arms netplay (DDR3 is not
  cleared when cores change); a heartbeat that stands still for 2^24 clocks
  (0.35 s) ends the session (RUN: error CTRL_DROP).
- **Frame tick:** the start of the machine's vertical blank (`BNKB` falling).
- **Freezing (`hold`):** every clock enable of the machine comes from the core's
  24 MHz pair (`CLK_EN_24M_N/P`); `hold` stops it, so no pulse is lost or caught
  up. `hold` is a register: the freeze starts in the clock after the tick, the
  same clock of the machine on both MiSTers. Every frame start is held at least
  `HOLD_MIN` = 64 clocks, longer while INPUT[k] is missing: an SDRAM read in
  flight at the tick ends inside the hold on every MiSTer, so a hold's length
  never reaches the machine. Unlike SNES (10.1) clock enables are enough here:
  the requirement is shown in simulation (T2n: different hold lengths give
  identical writes and timing in the machine's own clocks).
- **SDRAM refresh in a hold:** the machine's refresh comes with its picture and
  stops in a hold. A hold older than `HOLD_MIN` asks `sdram_mux` for a refresh
  (`NP_RFSH`, a toggle) every 340 clocks (7.1 µs; the SDRAM needs one per
  7.8 µs) and lasts until 16 clocks after the last one, so the machine never
  meets one. The module decides both, so a hold cannot end while a refresh it
  asked for runs. (Refresh is not modelled in the simulation: the chip model
  keeps its data.)
- **CRC:** over the game state, not the picture: each frame's INPUT, then every
  write of the 68000 in its first clock (address bits 23:1, UDS, data), CRC-32.
  The sprites and the fix layer wait for the SDRAM; the picture is no evidence
  of a desync.
- Picture: the held pixel enable stops the scaler's input, so HDMI repeats the
  newest frame; `HDMI_FREEZE` is not used (arcade, 12.3).

### 14.4 Main_MiSTer (`support/netplay/netplay.cpp`, `SYS_NEOGEO`)

- **The core:** name `NEOGEO` and the OSD option `...,Netplay,netplay.ini,...`
  in its configuration string (the MiSTer-devel core has none: not armed).
  OSD bits `[46:45]`. The room's core is `NEOGEO`; the server hands out no
  Neo Geo games (ROM sets are folders and zips), and there is no room folder:
  Join takes the oldest waiting room with this ROM set (`*`).
- **Protocol:** version 4 (the arcade encoding) with system byte 5. HELLO
  carries `rom_md5` = the ROM set, `boot_md5` = the BIOS files, `settings` =
  `{DIP [9:7], BIOS [22], Video Mode [3], System Type [1]}`, `sav_md5` zeros
  (the card is unplugged). Different: `REJ_ROM` "Different ROM set", `REJ_BIOS`
  "Different BIOS files", `REJ_SETTINGS`; a CD is `REJ_SYSTEM`.
- **ROM set md5:** the program (P ROMs) and M1 as the loader sends them to the
  core (`netplay_neogeo_data()` from `load_rom_to_mem`), in the order of their
  place in the core (P1 `$200000`, P1 second half `$280000`, P2 `$300000`, then
  M1), and the cart's configuration word (protection chips, wait states). So
  the same game matches from a Darksoft folder, a MAME zip or a `.neo` file
  (seen on hardware: two packs of the same game did not match by file). The
  sprites and the ADPCM samples decide no game timing and are left out.
- **BIOS md5:** the system ROM the loader sends (`uni-bios.rom` unless the OSD
  says Original or it is missing, else `neo-epo.sp1` for AES and `sp-s2.sp1`
  for MVS), `sfix.sfix` and `000-lo.lo`, from the folder that holds
  `000-lo.lo` (the ROM set's, or up to two above it).
- **Loading (two calls in `neogeo_romset_tx`):** before the load, with Netplay
  on (OSD Host or Join, or `netplay.ini`), `netplay_neogeo_before()`:
  - the first ROM set since the core was loaded: the thread writes CTRL
    (enable, session 0) with a heartbeat on every loop until the core says
    ARMED (at most 1 s, else "the core did not respond" and no session); the
    load then goes into a machine held in reset;
  - a later one: the machine has run, so Main writes the ROM set's path into
    DDR3 behind the mailbox's rings (`0x3000`: "NNPPEND1", the time, the path)
    and loads the core (RBF) again, which restarts Main; `netplay_start()` takes
    the path if it is less than 30 s old and `netplay_poll()` loads it.
  After the load `netplay_neogeo_loaded()` starts the session as a game load
  does on the other cores.
- **Session:** the engine's as arcade, except: in WAIT_CORE the core must be
  ARMED (not IDLE: "load the game again"); CTRL carries a new heartbeat on every
  step while enabled (`ctrl_word(..., heartbeat)`); the "reload" is nothing (the
  machine waits in reset since before the load). A pre-arm without a session
  ends after 120 s (a load that never finished).

### 14.5 Tests (Neo Geo)

| Test | What | Pass |
| --- | --- | --- |
| T2n | `make -C NeoGeo_MiSTer/npsim det ROM=<romset folder> BIOS=<bios folder>`: the whole core (`emu`) in Verilator, the SDRAM controller its own with an exact chip model; the bench is Main_MiSTer (the loader, and the netplay thread: arms before the load, starts the session, writes INPUT[k] from a fixed script, with a heartbeat) and the DDR3 with adjustable timing. Six sessions: DDR3 with jitter and pauses, DDR3 slower, the other clock phase, the session started 2 and 20 frames later, and input late on 2 to 50 % of the frames by up to 6 frames (holds of different lengths, long ones with SDRAM refreshes); DDR3 and the SDRAM start with different garbage (`--fill`), Main gives different times (`--rtc`), and the save file is read after the load with Main answering each sector after 0 to 60,000 clocks (`--sd`, still going on when the session starts in some runs), and two runs get a boot ROM at the core's start 12 and 25 frames before the ROM set (`--bootrom`; the bench heartbeats only once it has armed, as Main) | per frame of the session both CPUs' writes, their timing in the machine's own clocks (held clocks do not count) and the CRC in the mailbox equal to the reference run's (upstream: the Z80's writes differ from its first frame) |
| T3n | `make -C Main_MiSTer/support/netplay/test`: `test_netplay` (heartbeat word, settings, `ran`, a session on a core not armed is refused, a pre-armed one runs and the core takes the session's id, a heartbeat that stops ends it, a left-over CTRL word never arms); `NP_SYSTEM=neogeo` UDP runs with a fake core that keeps the module's rules: direct, through the server, the host played the game first (core reload: Main's restart with the path in DDR3), the join has the program in two files (same game, other pack), a different ROM set and a different BIOS refused | `PASS` |
| T2n-s | `obj_trace/neogeo_sim --snap` and `snapdiff.py`: every signal of the core 64 clocks after the reset's end, in runs as above | no signal differs (not counted: the SDRAM controller's start-up counter and the framework's OSD button timer) |

## 15. ao486 network card (v0.7: the card (T2e, T4e), Main's wire to the home network (T3e), the rooms (15.4, 15.6: T3e-l, T3e-u), the DOS kit with our IPX and the all-disks install (15.5: T3e-m, T3e-i); on hardware (T5e, T5e-r): DHCP and ping from DOS, Doom and the menu between two MiSTers through the server)

The MiSTer ao486 core with an NE2000 network card, so that DOS and Windows 95
programs can talk to other machines. Not lockstep: each MiSTer runs its own PC,
and only Ethernet frames cross the network, as the GBA adapter's packets do
(section 13). First the card and its wire to the MiSTer's own network; then a
virtual LAN per room through the lobby server (IPX games such as Doom, Duke
Nukem 3D, Warcraft II, more than two players), then Windows 95 with its own
NE2000 driver.

### 15.1 The core (`ao486_MiSTer`, branch `netplay`)

- **The card** is upstream ao486 PR #238 (georgemog, not merged), put on
  master `628ddbc`: an NE2000/RTL8019AS (`rtl/soc/ne2000/`, the device model of
  Minimig-AGA's Ethernet_shmem2 branch) at an ISA I/O base with a selectable
  IRQ, wired into `rtl/system.v`. Frames go through a 64 KB window in DDR3 at
  ARM physical `0x1FF00000` (Avalon word base `0x03FE0000`, the window the
  A2065 and NeXT cores use), on the core's own DDR3 port, shared with the CPU's
  memory by a fixed-priority arbiter (memory first). `sys/` is not touched.
- **OSD** (`P2`): `O[66]` Network Off/On, `O[68:67]` IRQ 11/10/5/3,
  `O[65:64]` the mode, Shared (eth0) / eth1 / MACVLAN / Bridge (tap0), read by
  Main only. The PR put Network and IRQ on `oS`/`oTU` (status 60–62); 60 is
  Low-Res (`P1oS`, since 2020), so Network On changed the video mode. They are
  at 66–68, and the core's `status` wire is 128 bits (it connected 64).
  `O[70:69]` Netplay netplay.ini / Off / Host / Join (15.4), read by Main only.
- **The window's contract** (the core's `ETH_SHM_*`, the PR's
  `sw/nettest/ne2000d.py`): 16-bit values little-endian, a 32-bit value
  `{word+2, word}`.

| Offset | What | Written by |
| --- | --- | --- |
| `0x1000` | FLAGS; low byte bit 2 RX_AVAIL (a hint) | Main sets |
| `0x104C` | the card's MAC, 6 bytes | Main, before the core leaves reset |
| `0x1052` | STATUS, bit 12 COMM_OK (signature and a moving heartbeat seen) | core |
| `0x1088` | heartbeat, 32 bits, changed every pass | Main |
| `0x108C` | signature `0xCAFEBABE`, written last; 0 when Main lets go | Main |
| `0x2C08` | TX request sequence S (1..65535, then 1: 0 is never used), written after frame S is staged | core |
| `0x2C0A` | TX done: the last sequence Main has sent | Main |
| `0x2C40` | TX lengths, 8 × u16, by slot | core |
| `0x3000` | TX slots, 8 × 1536 bytes; frame S in slot S % 8 | core |
| `0x2C04`, `0x2C06` | RX ring head (core), tail (Main), 16 slots | |
| `0x2C20` | RX lengths, 16 × u16 | Main |
| `0x9000` | RX slots, 16 × 1536 bytes | Main |

- The single TX buffer at `0x2000` with its length at `0x2C02`, which the PR's
  `ne2000d.py` reads, is the core's old contract and stays empty (seen on
  hardware: the sequence advanced, the length stayed 0, no frame left).
  The core does not wait for Main: the guest's transmit completes once the
  frame is staged.
- The core fetches the MAC from the window after a reset (the system's or the
  card's own, `base+0x18`) and adopts it only if it is unicast and locally
  administered. It keeps the last adopted one (`station_mac`) through both
  resets: the card's reset puts it, not the built-in `52:54:05:04:03:02`, into
  PAR and the PROM. A DOS driver reads the PROM right after resetting the card,
  before the fetch is done; with the built-in address there, both MiSTers of a
  room would use it (seen on hardware). Only power-up gives the built-in one.

### 15.2 Main_MiSTer (`support/netplay/ne2000.cpp`)

- Called from `netplay_start/stop/poll` (no new hooks in `user_io.cpp`); only
  for ao486 (`is_x86()`), not the PC XT or 286 cores.
- **Start** (the core was loaded, before `x86_init` releases its reset): clear
  the window, the MAC `52:54:05:xx:yy:zz` (the last three bytes of eth0's
  address, which exists also on WiFi, so two MiSTers on one LAN or in one room
  differ), heartbeat 0, then the signature. **Stop** (another core): the link closed, the signature 0.
- **Every pass:** the heartbeat; the mode from the OSD (Network Off, or a mode
  the MiSTer lacks: no link); every sequence after the last sent up to the
  request is sent from its slot, in order, then TX done is written (no link,
  or a length under 14 or over 1536: that frame goes nowhere, as on a card with
  no cable); more than 8 behind, only the 8 newest are still there; received frames go into the ring while it has room (length
  before tail), the rest are dropped (the socket is drained every pass: a
  card that falls behind loses frames, it does not get old ones later); the
  card's own frames echoed by the socket and frames under 14 bytes are dropped.
- **The card's address** is the source address of the guest's frames: the
  eth0 filter and the echo check follow it. The core fetches Main's address
  from DDR3 in the background after the card's reset, and a DOS driver reads
  the PROM right after resetting the card, so it may get the built-in
  `52:54:05:04:03:02` and program the card with that (seen on hardware: DHCP
  went out from it and the replies were filtered away). Group addresses are
  never taken. Since the core keeps the adopted address through its reset
  (15.1), the driver normally gets Main's.
- The host side (AF_PACKET, the MAC filter for eth0, macvlan, tap) is the
  A2065 module's (`support/minimig/minimig_a2065_ethernet.cpp`).

### 15.3 Tests (ao486 network card)

| Test | What | Pass |
| --- | --- | --- |
| T2e | `sim/iverilog/ne2000/run_regression.sh` in `ao486_MiSTer` (Icarus Verilog 12): the PR's 36 benches (the device model through its host port and the ISA bus, TX/RX rings, the mailbox and the arbiter, the station MAC) and `tb_ne2000_mac_reset` (the adopted MAC through the card's reset with DDR3 busy, a new MAC after the system reset, a zeroed window keeps the last) | 36 pass, 1 expected failure (`ethernet_tb`, BF-1 in the imported model) |
| T3e | `make -C Main_MiSTer/support/netplay/test`: `test_ne2000`, the window in memory with a fake core and a fake Ethernet: published over garbage, the MAC's form, the heartbeat moves, Network Off opens nothing, TX from the slot ring: one, several between two passes in order, a bad length skipped, lapped (only the 8 newest), the sequence passing 0xFFFF → 1, without a link nothing sent, RX order and lengths, own echo and runts dropped, a full ring drops, wraps after the core consumes, a missing mode closes, MACVLAN, Off closes, stop withdraws the signature; the room: the MiSTer's link closed, TX to the queue and not the wire, RX from the queue into the ring and the rest waiting, a bounded queue, out of the room the link back | `PASS` |
| T3e-l | `test_eth_link`: two links over a clean and a bad network (20 % loss, 10 % duplicates, reordering): connected, frames whole both ways (also 1514 bytes), runts and oversize not sent, lost after 10 s and back; a restart (new id) followed, a frame of the old pairing refused, lost when the other side goes quiet after starting over, an oversize datagram refused; a lockstep player, another version, junk refused | `PASS` |
| T3e-u | `NP_SYSTEM=ao486` runs of `run_udp_test.sh` (two `netplay.cpp` over UDP, the card as two queues): direct (netplay.ini and OSD) and through a real server with `NP_AUTOJOIN` (hole punching, and `direct=no`); each side's card sends 199 frames; `NP_AO486_REPAIR=host|join`: that side turns Netplay off and on (direct, and through the server for both sides), then both send again; `NP_AO486_NET_OFF=1`: both start with Network Off and only choose Host/Join | all 199 frames arrive whole on each side, none of its own; linked with the other's name; the direct path, or through the server with `direct=no`; after the toggle linked again within 45 s and at least 40 new frames each way; with Network Off at the start both turn it on and link | 
| T5e | hardware, one MiSTer with Ethernet, Network On, Shared, IRQ 11: in DOS `NE2KTEST` from the PR's `sw/nettest`, Crynwr `NE2000 0x60 11 0x300`, mTCP `DHCP` and `PING` | NE2KTEST passes; DHCP gets an address from the home router; ping answers from the router and from the internet |
| T5e-r | hardware, two MiSTers in a room through the server (15.4), Doom 1.9 IPXSETUP with NE2000.COM and NPIPX (15.5) | both find each other and play (2026-11-17; with PDIPX instead neither ever finds the other) |
| T3e-m | `tools/ao486/dos/netplay/qemu_test.sh <DOS disk> <work dir>`: the DOS kit in QEMU (15.5) | `ALL PASS` |
| T3e-o | `python3 -I tools/mister-scripts/test_netplay_onoff.py`: netplay_on, netplay_off and normal_main.py on a fake `/media/fat` with a local database: a netplay `MiSTer_offline` (or none) gets the official binary (zipped or plain database, its own `url` or `base_files_url`, the URL from `downloader.ini`), an MD5 mismatch installs nothing, offline takes `.MiSTer.old` or changes nothing; a normal `MiSTer_offline` is kept and nothing is fetched; netplay_off swaps back after the fix and changes nothing when it fails; netplay_on fixes on an update and when already active, and still switches offline. The scripts before this fail 5 of the 22 | `ALL PASS` |
| T3e-i | `tools/mister-scripts/test_ao486_install.sh <NETPLAY.IMG> <DOS disk> <work dir>`: the all-disks scripts on images in a privileged container (loop mounts): dry run changes nothing; install (the kit from the floppy, NP.BAT, the hook before the game start, `:NPEND` last, CRLF, the backup, a disk without AUTOEXEC.BAT, fsck clean); Windows 95, no-DOS and CD images untouched; again = updated; uninstall byte for byte, a later line stays; refused while ao486 runs; shortcuts: only the MGLs of disks with the menu, to `_Netplay/_DOS Games` with `_Netplay/ao486_netplay`, a user's file there and the originals untouched, the uninstall removes only ours. The installed copy boots in QEMU to the question and `1` gives the menu | `ALL PASS` |
| T4e | `CORE=ao486 tools/quartus_build.sh`, compared with upstream master built the same way (upstream does not meet its own constraints: `TIMING FAILED` is expected) | worst setup slack and TNS on the CPU clock no worse than about upstream's (2026-11-16: upstream −6.218 ns / TNS −20 260, ALMs 82 %, RAM blocks 79 %; netplay −5.748 ns / −21 378, 90 %, 82 %; with 0003 on 2026-11-17: −6.143 ns, 89 %, 82 %, and the HDMI clock −0.192 ns, positive in the other builds); the core boots on hardware |

### 15.4 The room (Netplay Host/Join)

- **Two MiSTers** with `peer=` pair directly as the other cores do (section 7).
  **Through the server** (`server=`) the room is a LAN of up to eight with the
  server as its switch (15.6). OSD Netplay Host or Join (or `mode=` in
  netplay.ini with the option on netplay.ini). The server's room is core
  `AO486`, game `LAN`; Join takes the open AO486 room with a place. No room
  folder and no way to pick a room: with two or more AO486 rooms open on one
  server, Join gets "N rooms with this game: pick one" and waits.
- **When:** Main's main thread watches the OSD: Netplay Host or Join and
  Network On put the card in the room (`ne2000_room(true)`: the MiSTer's own
  link is closed), anything else takes it out. A change of Netplay counts once
  the OSD is closed, or after it has stood 1.5 s with the OSD open (as arcade:
  stepping from Off to Join passes Host); a change of Network counts at once.
  Either reaches the netplay thread (`lan_thread`) as a new pairing (with the
  server the host opens a new room).
- **One setting:** when a Host or Join choice counts (also `mode=` from
  netplay.ini, at the core load) and Network is Off, Main turns Network On
  (`user_io_status_set("[66]", 1)`) and says "Netplay: network card on. Reset
  the PC (OSD Reset) so DOS finds it." Only at that moment: Network turned Off
  by hand afterwards stays off, and the room with it. The thread
  starts from Off at every core load. There is no game load and no core reload.
- **Pairing again:** ten seconds without a packet from the other side
  ("connection lost"), both sides pair from the start: a new socket, the join
  asks for the open room again. So two MiSTers find each other again after
  either turned its option off and on, or loaded the core again. Through the
  server the host keeps its room id while the core runs (15.6).
- **Frames:** the card's frames cross in two queues of 64 between the main
  thread (which alone touches the window) and the netplay thread (the oldest
  goes when one is full); from the room into the card while its RX ring has
  room, the rest wait in the queue.
- **The link** (`eth_link.cpp`), not reliable and not ordered, as Ethernet is
  not (IPX games and TCP resend by themselves): packet `NPE1` type version (1)
  from32 to32 (big-endian), then the frame (14 to 1536 bytes; a longer datagram
  is refused, not cut); type 0 HELLO, 1 FRAME. `from` and `to` are random ids,
  one per pairing. HELLO every 500 ms until the other
  side has answered with our id, then every second; a side that becomes
  connected answers at once. A HELLO with a new id from the other side (its core
  loaded again) starts over. Frames are taken only from the paired side and
  for this pairing, and sent only while connected (before that they are
  dropped, as on a card with no cable). Ten seconds without a packet: lost.
  Another magic before connecting (a lockstep player, the GBA adapter):
  "the other player is not using the network card"; another version: "different
  netplay version". A frame with its header is at most 1550 bytes of UDP: over
  the internet that is fragmented; the server reads 2048.
- **OSD:** "waiting for player 2 (network card)" / "connecting (network card)",
  "network linked with X (direct|through the server)" (again after the other
  side started over), "the other player started over", "connection lost";
  `netplay.log` every 10 s: frames sent, received, dropped, foreign, the path.

### 15.5 The DOS side: drivers, IPX and the game menu (`tools/ao486/dos/netplay`)

Everything the PC needs, on one install floppy (`NETPLAY.IMG`, built by
`build.sh` with Open Watcom 2.0 in Docker; the compiler is a pinned monthly
build checked by SHA-256). Nothing on the MiSTer side changes.

- **IPX: `NPIPX.COM`** (ours, GPL 2+). Intel PDIPX with the Crynwr NE2000
  packet driver passes no received IPX packet on to the programs (seen on
  hardware with two MiSTers and in QEMU with two NE2000 cards: the packet
  driver hands the frames to PDIPX's handle, a listening ECB never fills), so
  Doom's IPXSETUP never finds the other player. NPIPX is a TSR on the packet
  driver with the Novell IPX interface games use: the far entry from INT 2Fh
  AX=7A00h and INT 7Ah; open/close socket (dynamic sockets 4000h-7FFFh,
  short-lived ones closed when their program ends: INT 21h 00h/4Ch hook, owner
  = the current PSP from DOS's swappable data area), get local target, send,
  listen, schedule IPX/special event (AES, on INT 1Ch), cancel, interval
  marker, internetwork address (network 0, node = the card's MAC), relinquish,
  packet size (1500); SPX answers "not installed". AL = 0 after every call that
  succeeds (Doom checks AL after a send). Frames go out as Ethernet II 8137;
  Ethernet II 8137, raw 802.3 (FFFF) and 802.2 (E0E0) are taken in. A packet
  goes to the first listening ECB of its socket (FIFO); immediate address =
  the sender's MAC; ESR with AL = FFh (IPX) or 00h (AES), interrupts off.
  A send to our own node is delivered locally; broadcasts are not looped back.
- **`NPMENU.EXE /CHECK`** finds the card at 0x300 (a reset sets ISR.RST and
  CR reads back 21h; only when no packet driver owns it) and its IRQ (a
  zero-length remote DMA sets ISR.RDC; with IMR = RDC the line shows in the
  PIC's request register while masked; OSD choices 11, 10, 5, 3). It writes
  `NPLOAD.BAT` (the loads this boot still needs: `NE2000.COM 0x60 <irq> 0x300`,
  `NPIPX.COM`, or nothing when they are loaded) and `NPIRQ.TXT`; exit code 1 =
  a card. No environment variables anywhere: the ready-made ao486 disks have
  no room left in the environment and `SET` fails quietly.
- **The boot choice, `NPMENU /BOOT`** (from AUTOEXEC.BAT through `NETBOOT.BAT
  BOOT`): with no card it says so and returns 0 at once, so the disk boots as
  before with no wait. With the card it does the check (writes `NPLOAD.BAT`,
  loads nothing) and asks "Online" or "Single player"; Single player is
  highlighted and starts by itself after 10 s without a key (the BIOS tick
  counter; keys pressed during the boot are dropped first), so a disk never
  stops here. Any key stops the countdown; Up/Down and Enter, `1`/`O`
  online, `2`/`S`/Esc single player. Exit code 1 = online (load, then the
  menu), 0 = single player: nothing is loaded and the boot goes on to the
  disk's own game.
- **`NETBOOT.BAT`**: with `BOOT` the boot choice, else the check; then the
  loads and the menu in a loop (exit code 2 = run `RUN.BAT` and come back, 3 =
  stop at the DOS prompt, 0 = go on). `NP` (no `BOOT`) brings the menu at once.
  F10 leaves `NPSKIP.FLG`, which the AUTOEXEC hook reads.
- **Install** (`A:\INSTALL` = `NPMENU /INSTALL`): the kit to `C:\NETPLAY`,
  `C:\NP.BAT`, and in `C:\AUTOEXEC.BAT` (backup `AUTOEXEC.NPB`, made once) the
  lines `CALL C:\NETPLAY\NETBOOT.BAT BOOT` and `IF EXIST C:\NETPLAY\NPSKIP.FLG
  GOTO NPEND` before the first `CD ` or `RUNGAME` line (how the ready-made disks
  start their game; else at the end), and `:NPEND` last. Installing again only
  updates the files.
- **All disks at once** (MiSTer Scripts menu, `tools/mister-scripts/
  ao486_netplay_install.sh`, Python 3 in it, as root): for every `.vhd` in
  each `games/AO486` (usb0-5 and fat, any case), the first FAT partition (or a
  FAT image without a partition table) is loop-mounted (vfat) and gets what
  `A:\INSTALL` gives: the kit's files from `games/AO486/NETPLAY.IMG` (mounted
  read-only), `C:\NP.BAT`, and the hook by the same rule (backup once; a disk
  with the hook gets the files only; no AUTOEXEC.BAT: one with `@ECHO OFF`,
  the hook and `:NPEND`). Skipped: no FAT partition, no `COMMAND.COM` (not
  DOS), Windows 95/98 (`MSDOS.SYS` text with `[Options]` and no `BootGUI=0`:
  it boots into Windows), anything not `.vhd` (CD images). Refused while
  `/tmp/CORENAME` is AO486 (a mounted disk must not change under the core).
  `--dry-run` mounts read-only and only says what it would do.
  `ao486_netplay_uninstall.sh` (= `--uninstall`) does `NPMENU /UNINSTALL` on
  each. The game shortcuts of those disks are copied to `_Netplay/_DOS Games`
  (section 1.1; `--menu-root` for tests).
- **Uninstall** (`A:\UNINSTAL` = `NPMENU /UNINSTALL`; `A:\UNINSTALL` works too,
  DOS cuts the name to eight letters): takes the three netplay lines out of
  `C:\AUTOEXEC.BAT`; when the rest is the backup line for line, the backup is
  copied back byte for byte, else only those lines go and later changes stay.
  Then `AUTOEXEC.NPB`, `C:\NP.BAT` and every file in `C:\NETPLAY` (and the
  folder) are deleted. Not a batch file in `C:\NETPLAY` (it would delete
  itself while DOS reads it); from C: it is `C:\NETPLAY\NPMENU /UNINSTALL`.
- **The menu**: the games of `GAMES.INI` (users add their own) found on the
  hard disks (fixed disks only, three folders deep, not WINDOWS, DOS, NETPLAY,
  MISTER, DRIVERS, UTIL): ready first, then found but missing files (named,
  e.g. FastDoom without DOOM.EXE/IPXSETUP.EXE), then (Tab hides them) the
  supported ones not on the disks. Types: `ipx` (the menu sets players, mode
  and skill on the game's own IPX starter, `args=` with %N %M %S), `program`
  (starts it, shows how its own menus set up network play), `fpu` (listed, not
  started: the ao486 has no FPU). A start writes `RUN.BAT` (drive, folder, the
  program or `CALL` of a .BAT, back to C:\) and leaves; the menu comes back
  after the game.
- **The room in the menu**: every menu sends an IPX broadcast on socket 4E50h
  once a second (`NPLB`, version 1, state 0 = in the menu / 1 = starting a game,
  name, game, arguments); a peer is shown until 5 s of silence, one who
  started a game for 60 s or until it is back in its menu. When the other
  player starts a game that is ready here, J follows with the same arguments.
  The name is `PLAYER-xxxx` (the MAC's last two bytes) until F2 sets one
  (`NETPLAY.CFG`).
- **Tests (T3e-m)**: `qemu_test.sh <DOS disk image> <work dir>` in the np-qemu
  image (two QEMU PCs with ne2k_isa on one socket network, the screen read from
  VGA text memory): install (hook before the game start, backup, `:NPEND`),
  card off (boot as before, no question), card on without a key (the question,
  the countdown, single player after 8-13 s, no menu), card on at IRQ 10 with
  `1` (drivers loaded once, IRQ found, a fake Heretic listed, NP again loads
  nothing), two PCs (online by Down+Enter and by `O`; each sees the other, A
  starts Heretic deathmatch, B follows with J, both fake IPXSETUPs get
  `-nodes 2 -deathmatch -skill 3`), uninstall by `A:\UNINSTALL` (AUTOEXEC.BAT
  is the old one again, C:\NETPLAY, NP.BAT and the backup gone; with a line
  added after the install only the netplay lines go). Doom itself over NPIPX in QEMU: the
  shareware reaches E1M1 with two players. On hardware: Doom with NPIPX
  between two MiSTers through the server (2026-11-17).

### 15.6 Rooms of up to eight (the server as the switch, ao486 only)

Only ao486 rooms; every other core keeps host and join, PEER, hole punching
and the relay exactly as before (section 7). The server's key is checked as
for every REG.

- **Server** (`server/ethswitch.go`): a REG with core `AO486` opens or joins a
  switch room. The answer is `OK <role> switch <room>`; no PEER follows (no
  hole punching: everything goes through the server). Up to 8 members; a ninth
  gets "room is full" (by room) or is not matched (by `*`). Join `*` takes the
  oldest AO486 room with a live member and a place ("N rooms … pick one" when
  there are several). A host that registers its room again from a new socket
  (its link started over) keeps it; another core's REG for an ao486 room id,
  or the other way round, is refused.
- **The link:** the server is each member's other side of NPE1 (15.4): every
  HELLO from a member is answered with the server's own id for that member
  (so the member's keepalive is the server's too); a member is connected when
  its HELLO names that id. FRAME only from a connected member with its ids,
  14–1536 bytes. Switching: the source address is learned (at most 256 per
  room, then learning starts over); a unicast to a learned address goes to
  that member only (to the sender itself: nowhere), a broadcast, multicast or
  unknown address to all other connected members.
- **Members** leave by BYE or after 15 s of silence; whenever members come or
  go, all get `NPS1 ROOM <count> <names in order of arrival, ", ">`. The room
  closes when the last member is gone (not when the host leaves); the server's
  list shows the first member as the room's host and the others as joined.
- **Main:** on `switch` the link's other side is the server ("network linked
  with the room (through the server)"); `ROOM` shows as "Netplay: N in the
  room: names". The host keeps its room id while the core runs (a new socket
  after a lost link registers the same room). A join alone in the room for
  10 s ("alone in the room, looking again") pairs from the start, so it finds
  the host's new room after the host loaded the core again. With `peer=`
  nothing changes (two MiSTers, direct).
- **DOS side:** nothing changes: NPIPX broadcasts to all and takes packets from
  anyone (15.5); Doom: `IPXSETUP -nodes 3` or `4`.
- **Tests:** `server/ethswitch_test.go` (three members: no frame before the
  handshake, broadcast to the other two, unicast to the learned member only,
  unknown to all, wrong id and runts dropped; eight fit, the ninth not; the
  host leaving keeps the room and tells the seven; the last leaving closes it;
  a host on a new socket keeps its room; other cores unchanged; wrong key
  refused). T3e-u through the real server: `NP_AO486_PLAYERS=3` (each of
  three gets at least 150 frames from each other, the names of all three),
  two players (linked with the room, never direct), Netplay off and on for
  host and join, and `NP_AO486_RELOAD=1` (the host's Main starts over with a
  new room, the join finds it and frames flow).
