# DOS drivers for the ao486 network card

The ao486 netplay core has an NE2000 network card (SPEC.md section 15). DOS
programs reach it through a packet driver, and IPX games (Doom, Duke Nukem 3D,
Warcraft II, ...) through an IPX driver on top of the packet driver. Both are
free to share; they are here unchanged so that nobody has to hunt for them.

| File | What | Licence |
| --- | --- | --- |
| `crynwr/NE2000.COM` | Crynwr packet driver for NE2000 cards (packet driver collection 11.x, `pktd11.zip`, 1993) | GNU GPL version 1 (`crynwr/COPYING.DOC`) |
| `crynwr/source/` | the source it is built from (`NE2000.ASM` and the files it includes, `HEAD.ASM`, `TAIL.ASM`, `MAKEFILE.NOR`), from the Crynwr sources as FreeDOS packages them (`crynwr.zip`, `SOURCE/CRYNWR/SOURCES.ZIP`) | GNU GPL version 1; some helper files are in the public domain (see their first line) |
| `pdipx/pdipx.zip` | Intel PDIPX 1.03, IPX on top of a packet driver, as distributed | "freely copyable by all parties for all purposes" (`pdipx/readme.txt`) |
| `pdipx/pdipx1.com`, `pdipx/readme.txt` | the driver and its readme, taken out of the zip | as above |

Where they come from: the packet driver collection and its sources are at
the Crynwr mirrors and in the FreeDOS repository
(`https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/repositories/1.3/net/crynwr.zip`);
PDIPX at `http://files.shikadi.net/malv/files/network/pd2ipx/pdipx.zip`.

**PDIPX does not work here:** with the Crynwr NE2000 packet driver it passes
no received IPX packet on to the programs (on the MiSTer and in QEMU alike),
so IPX games never find each other. Use **NPIPX** from `netplay/` instead (our
IPX driver, GPL 2 or later). PDIPX stays here only as the record of what was
tried.

## The netplay kit (`netplay/`)

`netplay/build.sh <work dir>` builds `NETPLAY.IMG`, an install floppy: the
packet driver, NPIPX, and a menu that loads them at boot when the ao486 network
card is on and lists the network games found on the hard disk (SPEC.md 15.5).
On the ao486: mount it as A:, type `A:\INSTALL` once per hard disk image.
`netplay/README.TXT` is the user's guide that goes on the floppy.

## Using the drivers by hand

In the ao486 OSD (Hardware page): **Network On**, **NE2000 IRQ 11**, and
either **Netplay Host / Join** (a room with another MiSTer) or **Netplay Off**
with **NE2000 Mode Shared** (the MiSTer's own network, with a cable). Then in
DOS:

```
NE2000 0x60 11 0x300     the packet driver: software interrupt 0x60, IRQ 11, I/O 0x300
NPIPX                    IPX on top of it (for IPX games)
```

then the game's own network setup, for example `IPXSETUP -nodes 2` for Doom.
Load the drivers once per boot: a second card test or driver start resets the
card under the loaded driver, and nothing is received any more.

For TCP/IP programs (DHCP, ping, telnet, FTP) use mTCP
(`https://www.brutman.com/mTCP/`) with `PACKETINT 0x60` in its configuration.
