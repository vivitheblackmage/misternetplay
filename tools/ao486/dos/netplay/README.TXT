NETWORK GAMES ON THE MISTER AO486 CORE
======================================

What it does
  When the ao486 network card is on, the PC asks at boot: Online or Single
  player. Online loads the network drivers and shows a menu of the network
  games on its hard disks; pick one and it starts with the right network
  settings. The menu also shows who else is in the room, and what they
  start: press J to follow them with the same settings. Single player boots
  the disk as usual, and starts by itself after 10 seconds if no key is
  pressed. With the network card off nothing changes and nothing is asked.

Install on all disks at once (easiest)
  MiSTer Scripts menu: ao486_netplay_install. It puts the menu on every DOS
  hard disk image in games/AO486 (Windows 95/98 disks are skipped), from
  games/AO486/NETPLAY.IMG. Run it again after an update.
  ao486_netplay_uninstall takes it off all of them.

Install on one disk
  1. Boot the disk as usual, mount NETPLAY.IMG as floppy A: in the OSD.
  2. Leave the game to the DOS prompt (Ctrl+C, then Y, in a game menu)
     and type  A:\INSTALL
  It copies everything to C:\NETPLAY and adds two lines to C:\AUTOEXEC.BAT
  (the old file is kept as C:\AUTOEXEC.NPB).

Uninstall
  Type  A:\UNINSTALL  (with NETPLAY.IMG as A:), or
  C:\NETPLAY\NPMENU /UNINSTALL  without the floppy. It takes the netplay
  lines out of C:\AUTOEXEC.BAT and deletes C:\NETPLAY, C:\NP.BAT and the
  backup. Changes you made to AUTOEXEC.BAT after the install stay.

Play
  1. ao486 OSD, Hardware page: Netplay Host on one MiSTer and Join on the
     others (up to eight). That turns Network On as well. Wait for
     "network linked" in the OSD.
  2. Reboot the PC (OSD Reset) and press 1 (Online) when it asks, or type
     NP if it is already running.
  3. The menu comes up. Your friends show under "In the room" when the
     link works. Pick the game; everyone starts it from the menu.

  At the boot question: Up/Down and Enter, 1 or O = Online, 2 or S =
  Single player. Any key stops the 10 second countdown.
  Esc in the menu goes on booting as before (the disk's own game start);
  F10 stops at the DOS prompt.

Games
  GAMES.INI lists the games the menu knows and how each one starts its
  network play; add your own there. Doom needs id's DOOM.EXE/DOOM2.EXE and
  IPXSETUP.EXE: FastDoom has no network play.

Files
  NPMENU.EXE   the menu (GPL 2 or later)
  NE2000.COM   Crynwr NE2000 packet driver (GPL 1)
  NPIPX.COM    IPX for the games, on the packet driver (GPL 2 or later)
