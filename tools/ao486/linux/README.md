# A Linux disk for ao486 with the network card

`build.sh <work dir>` builds `ao486-linux.vhd` (64 MB) in Docker:

- **Linux 6.18 LTS** (the last series that builds for a 486: 7.1 removed it),
  `tinyconfig` plus `kernel.config`: 486SX with the FPU emulated
  (`MATH_EMULATION`, needs `MODIFY_LDT_SYSCALL`), no PCI, VGA text console,
  PS/2 keyboard, serial console, IPv4, and the NE2000 ISA driver built in
  (`netdev=11,0x300,eth0` on the command line, as the ao486 OSD sets the card).
- **BusyBox** 1.36.1, static, for i486 with musl (the musl.cc i486 toolchain);
  without its SHA-NI code (no such instructions on a 486).
- Everything runs from RAM (an initramfs): `rootfs/etc/rc` brings up eth0 with
  DHCP and starts a web server (`/www`) and telnetd (no password: for a LAN).
- **SYSLINUX** on a FAT16 partition from sector 63, a fixed VHD footer
  (`vhd_footer.py`).

On the MiSTer: `games/AO486/media/<folder>/ao486-linux.vhd` as IDE 0-0, OSD
Hardware: Network On, NE2000 IRQ 11. In a netplay room (Netplay Host/Join) the
two machines get no DHCP: set addresses by hand, e.g.
`ip addr add 192.168.86.1/24 dev eth0` and `.2` on the other.

Tried in QEMU (`-cpu 486`, `-device ne2k_isa,iobase=0x300,irq=11`): boots from
the disk, DHCP, ping. QEMU's 486 has an FPU, so the emulation is tried only on
the MiSTer.
