# netplay-server

A private lobby and relay for NES netplay on MiSTer. One small file, no
dependencies:

| File | Computer |
| --- | --- |
| `netplay-server.exe` | Windows |
| `netplay-server-linux-amd64` | Linux PC/NAS (x86-64) |
| `netplay-server-linux-arm64` | Raspberry Pi 3/4/5 with 64-bit Raspberry Pi OS |
| `netplay-server-linux-armv7` | Raspberry Pi with a 32-bit OS, MiSTer |

Build with `./build.sh` (Go in Docker). Everything ends up in `build/`.

## How it works

A player picks **Netplay → Host** in the OSD and loads a game: a room opens on
the server. For everyone else the room shows up in the file browser as the
folder `_Netplay/Rooms/<name> - <game>/`; whoever loads the game in it joins.
The MiSTers then try to talk to each other directly (hole punching); when that
does not work, the server passes the traffic on. The players never need to
open a port.

## Start on Windows

Double-click `netplay-server.exe`. The first start creates `netplay-server.ini`
next to it, with a random key.

## Start on Linux / Raspberry Pi (starts at boot)

Copy the whole `build/` folder to the Pi (for example
`scp -r build pi@raspberrypi.local:netplay-server`), and there:

```sh
cd netplay-server
sudo sh install-linux.sh
```

The script picks the right file for the computer, installs it in
`/opt/netplay-server`, starts the server as a service (own user `netplay`) and
prints the key and what goes into the MiSTer's `netplay.ini`. To update: run the
same command with new files. To remove: `sudo sh install-linux.sh remove`.
Log: `journalctl -u netplay-server -f`. Games to hand out: `/opt/netplay-server/roms`.

Without systemd, or just to try it: run `./netplay-server-linux-arm64` directly.

## Settings (`netplay-server.ini`)

```ini
port=7845          ; UDP + TCP
key=3f9c...        ; the same key in the players' netplay.ini
roms=roms          ; games the server hands out (in RAM only on the MiSTers)
catalog=catalog.txt ; "md5 name" per line: versions everyone brings themselves
```

Forward **port 7845, UDP and TCP**, in the router to the computer running the
server. Give it a fixed address in the router, and a name with for example
DuckDNS.

Rooms and games show in a web browser: `http://<server>:7845/?key=<key>`.
`netplay-server -make-catalog <folder>` prints catalog lines for the files in a
folder.

Only put games in `roms` that you are allowed to share, such as your own games
and homebrew.

## On the MiSTers

```ini
[netplay]
server=myserver.duckdns.org:7845
key=3f9c...
name=Alex           ; shown in the room list (at most 16 characters)
delay=4
```

- **Open a room:** OSD **Netplay → Host**, load a game.
- **Join:** open the folder **_Netplay/Rooms** in the file browser, open a room
  and pick the game in it. (Or **Netplay → Join** and load the same game: you
  land in the oldest room with exactly that game.)
- The server's games are in **_Netplay/Server games**.
- The list is refreshed every 3 seconds; leave and re-open the folder to see
  new rooms.
