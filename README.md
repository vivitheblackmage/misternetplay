# NES netplay for MiSTer

Play NES games together on two [MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki)
boards over the internet or a LAN. Both MiSTers run the real NES core in
lockstep: each frame's controller input is sent to the other side, and both
run exactly the same frames with the same input. A checksum of the game state
is compared all the time, so a desync stops the session instead of going on
silently.

It comes in three parts:

- **NES core** (`NES_netplay.rbf`): the MiSTer NES core with a netplay module
  added to the FPGA design.
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
  through the lobby server, with the server running on Windows 10.
- Games stay in sync: recorded and replayed frame by frame with identical
  results over 38,000+ frames each on NROM, MMC1, MMC3, MMC5 and UNROM games
  (Super Mario Bros., The Legend of Zelda, Super Mario Bros. 3, Castlevania III,
  Gun.Smoke).
- Automated tests for the core (Verilator testbench) and for the netplay engine,
  host and join over real UDP, with and without the server.

## Where the NES core and the Main binary come from

Both are the official MiSTer-devel projects. This repository does not copy
them; it holds our changes as patches on top of exact upstream commits:

| Part | Upstream repository | Base commit | Our changes |
| --- | --- | --- | --- |
| NES core (FPGA) | [github.com/MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer) | `49a0a66` (2026-09-30) | [`patches/NES_MiSTer/`](patches/NES_MiSTer) |
| Main binary (ARM) | [github.com/MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | `0827165` (2026-10-30) | [`patches/Main_MiSTer/`](patches/Main_MiSTer) |

The NES core is the work of the MiSTer-devel contributors and of the authors
credited in its own README; Main_MiSTer likewise. Both are licensed GPL-3.0,
and so are our patches.

`./setup.sh` clones both upstream repositories next to it and applies the
patches on a branch called `netplay`.

Everything else here is our own: the lobby server (`server/`), the tools
(`tools/`) and the NetPong test game (`netpong/`). The Quartus Docker setup in
`tools/quartus-docker/` is based on
[ebraminio/mister-docker-build](https://github.com/ebraminio/mister-docker-build) (MIT).

## What you need

| | Needed |
| --- | --- |
| MiSTer | Two MiSTers (DE10-Nano) with SDRAM, a network connection (Ethernet is best) and the current MiSTer Linux. Tested on kernel `6.18.38-MiSTer` (glibc 2.31). `MiSTer_online` needs glibc 2.29 or newer, so a MiSTer kept up to date with the official updater (`update_all` or `downloader`) is fine. Check with `uname -r` over ssh. |
| Game | The same ROM file on both MiSTers (same md5). NetPong, a free two-player test game, is included. |
| Server (optional) | Windows 10/11, or Linux on x86-64, ARM64 or ARMv7, such as Raspberry Pi OS (32- or 64-bit), Debian or Ubuntu. The binaries have no dependencies; the installer needs systemd (without it, run the binary by hand). Tested on Windows 10; Linux x86-64 in the automated tests. One forwarded port (7845, UDP and TCP) on the server's router. |
| Building (developers) | Linux, tested on Ubuntu 24.04 (also in WSL2 on Windows 10). Docker for Quartus Prime Lite 17.0.2, Verilator 5, g++, Python 3, Go 1.22 (or Docker). See [Building](#building). |

## Installing on the MiSTer

Download `nes-netplay-<version>.zip` from the releases and unzip it on a
computer. Then on **each** MiSTer:

1. Copy everything in the folder `SD card` to the root of the MiSTer's SD card
   (where `_Console` is), over the network share or with the card in a
   computer. None of your files is overwritten:
   - `_Console/NES_netplay.rbf`: the core, next to the normal NES core
   - `MiSTer_online`: the netplay main binary
   - `Scripts/netplay_on.sh`, `Scripts/netplay_off.sh`
   - `netplay.ini`: the settings (keep yours if you already have one)
   - `games/NES/NetPong/NetPong.nes`
2. On the MiSTer: **Scripts → netplay_on**. Your binary is saved as
   `MiSTer_offline`, `MiSTer_online` becomes `MiSTer`, and the MiSTer
   reboots. **Scripts → netplay_off** switches back.
3. Start **Console → NES_netplay**. In the OSD: **Advanced → RAM Clear → $00**,
   then **Save settings** at the bottom of the menu (both players need the
   same settings).

### Playing directly (no server)

- The host forwards **UDP port 7845** in its router to its MiSTer, then picks
  **Netplay → Host** in the OSD and loads a game.
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
- The OSD says `playing with Alex (delay 4, direct)` or `... through the server`.

All settings are described in [`tools/netplay.ini.example`](tools/netplay.ini.example).

## Running the server

- **Windows:** double-click `netplay-server.exe`.
- **Raspberry Pi / Linux:** copy the `Server` folder from the release zip to
  the machine and run `sudo sh install-linux.sh`. It picks the right binary,
  installs it as a service that starts at boot, and prints the key.

The first start writes `netplay-server.ini` with a random key. Forward port
**7845, UDP and TCP**, to that computer. Open rooms show in a browser at
`http://<server>:7845/?key=<key>`. Details: [`server/README.md`](server/README.md).

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
| `Different NES core build` | different `NES_netplay.rbf` files: use the same release on both |
| `Different save (.sav) file` | the game has battery saves and they differ; copy one player's `.sav` to the other, or remove both |
| `Set RAM Clear to $00 or $FF` | OSD → Advanced → RAM Clear, then Save settings |
| `Different core settings` | an OSD setting differs (system type, PPU reset, extra sprites, mask edges, overscan): make them the same before loading the game |
| `Different netplay version` | use the same release on both MiSTers |
| `cannot reach server` | wrong `server=`, or the server is not running |
| `server: wrong key` | `key=` does not match the server's |
| `connection lost` | nothing arrived from the other player for 5 seconds |
| no connection at all (direct) | the host's router must forward UDP 7845 to the MiSTer |
| `(missing game)` in Rooms | you do not have that game with the same md5 |

Not supported: FDS, NSF, Vs. System and Dendy games; cheats, savestates and
multitap are switched off during netplay.

## Building

Linux (Ubuntu 24.04 tested, WSL2 works; keep the work folder in the Linux file
system, not under `/mnt/c`):

```sh
sudo apt install -y git make g++ verilator python3 rsync
./setup.sh                                   # NES_MiSTer/ and Main_MiSTer/ with the patches
make -C NES_MiSTer/sim lint test             # RTL lint and testbench
make -C Main_MiSTer/support/netplay/test     # netplay engine tests, host + join over UDP
tools/quartus_build.sh                       # the core, Quartus 17.0.2 in Docker (10-30 min)
(cd Main_MiSTer && source setup_default_toolchain.sh && make)   # MiSTer_online
server/build.sh                              # netplay-server, Go in Docker
tools/make_release.sh v0.2                   # releases/v0.2/ and nes-netplay-v0.2.zip
```

The Quartus image: [`tools/quartus-docker/README.md`](tools/quartus-docker/README.md).
Deploy to a MiSTer over ssh: `tools/deploy.sh <ip> all`.
The design and the protocols are specified in [`SPEC.md`](SPEC.md).

## Licence

GPL-3.0 (see `LICENSE`), as the upstream NES_MiSTer and Main_MiSTer.
`tools/quartus-docker` is MIT (see `tools/quartus-docker/LICENSE.ebraminio`).
Only put games on a server that you are allowed to share.
