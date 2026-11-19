# The ao486 netplay kit for DOS

SPEC.md 15.5 is the definition. In short:

| File | What |
| --- | --- |
| `npipx.c` | `NPIPX.COM`: IPX (the Novell interface games use) on a packet driver; replaces PDIPX, which receives nothing here |
| `npmenu.c` | `NPMENU.EXE`: `/CHECK` (card, IRQ, which drivers to load), `/BOOT` (online or single player at boot, single after 10 s), the game menu with the room, `/INSTALL`, `/UNINSTALL` |
| `NETBOOT.BAT` | boot choice or check, load, menu loop; AUTOEXEC.BAT calls it with `BOOT` |
| `GAMES.INI` | the games the menu knows and how each starts its network play |
| `INSTALL.BAT`, `UNINSTAL.BAT`, `README.TXT` | on the floppy: install, uninstall and the user's guide |
| `build.sh <work dir>` | Open Watcom 2.0 (pinned, SHA-256) and mtools in Docker → `NPMENU.EXE`, `NPIPX.COM`, `NETPLAY.IMG` |
| `qemu_test.sh <DOS disk> <work dir>` | T3e-m: two QEMU PCs (np-qemu image), `qemu_test.py` says what is checked |

The test needs a DOS hard disk image that boots in QEMU and starts its game
the way the ready-made ao486 disks do (`CD <dir>` and `RUNGAME.BAT` in
AUTOEXEC.BAT). It works on copies; the image itself is not changed. Disks
that load the ao486 CD driver (VIDE-CDD) stop at boot in QEMU.

Licences: `npipx.c` and `npmenu.c` GPL 2 or later; NE2000.COM (Crynwr) GPL 1,
from `../crynwr`. Nothing third-party is built into the programs except the
Open Watcom C runtime, which may be redistributed in compiled programs.
