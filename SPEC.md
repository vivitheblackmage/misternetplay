# NES_MiSTer Netplay — SPEC v1

Status: v1 against NES_MiSTer `49a0a66` and Main_MiSTer `0827165`. Built in
Quartus (timing OK) and tested on hardware: replay determinism (T5) and lockstep
over the internet between two MiSTers. The lobby and hole punching are tested in
T3 but not yet on hardware.
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
- **Frame 0** starts when the netplay module releases reset. **Frame k** (k ≥ 1)
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
- `user_io.cpp`: `netplay_start()` when a core named `NES` starts,
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
| anywhere else | Join | joins the oldest waiting room with the same game (md5), else OSD "no room with this game" |

**Control protocol (UDP, same port).** Packets starting with `NPS1` are for the
server; fields are separated by tabs (`\t`). Everything from the server and from
other players is untrusted: lengths and characters are checked, anything
invalid is dropped.
- `NPS1 REG` key room role name local-address core md5 game → `NPS1 OK` role
  `waiting|paired` room-id, or `NPS1 ERR` text. `room` is the host's random id
  (8 hex digits) or `*` for a join without a room (match on md5); after OK the
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

**HTTP (TCP, same port number), all with `?key=`:** `/roms` (`md5 size name`),
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
