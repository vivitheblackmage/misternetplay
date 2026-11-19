#!/usr/bin/env bash
# Builds the ao486 netplay menu and IPX driver (SPEC.md 15.5) and the install floppy.
#
#   tools/ao486/dos/netplay/build.sh <work dir>
#       -> <work dir>/NPMENU.EXE, NPIPX.COM, NETPLAY.IMG (1.44 MB, FAT12)
#
# Open Watcom 2.0 (a pinned monthly build, checked by SHA-256) is downloaded
# into the work dir once; the compiler and mtools run in Docker
# (debian:bookworm). Nothing of the result goes into git.
set -euo pipefail

OW_TAG=2026-11-01-Build
OW_SHA256=89e90b7544cf3ea4a38124ec4c104a5027f31101405d7115c3f833daa465bb48

here="$(cd "$(dirname "$0")" && pwd)"
dos="$(cd "$here/.." && pwd)"
work="$(mkdir -p "${1:?usage: $0 <work dir>}" && cd "$1" && pwd)"

tarball="$work/ow-snapshot-${OW_TAG%-Build}.tar.xz"
if [ ! -f "$tarball" ]; then
	curl -sL --fail -o "$tarball.part" \
		"https://github.com/open-watcom/open-watcom-v2/releases/download/$OW_TAG/ow-snapshot.tar.xz"
	mv "$tarball.part" "$tarball"
fi
echo "$OW_SHA256  $tarball" | sha256sum -c --quiet

docker run --rm -v "$here":/src:ro -v "$dos":/dos:ro -v "$work":/work -w /work debian:bookworm bash -euc '
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq && apt-get install -y -qq xz-utils mtools >/dev/null
	if [ ! -x ow/binl64/wcl ]; then mkdir -p ow && tar xf ow-snapshot-*.tar.xz -C ow; fi
	export WATCOM=/work/ow INCLUDE=/work/ow/h PATH=/work/ow/binl64:$PATH
	rm -rf obj && mkdir obj && cd obj
	cp /src/npmenu.c /src/npipx.c .
	wcl -q -bt=dos -ml -os -s -wx -we -fe=NPMENU.EXE npmenu.c
	wcl -q -bt=com -mt -zu -os -s -k1024 -wx -we -fe=NPIPX.COM npipx.c
	cp NPMENU.EXE NPIPX.COM /work/
	cd /work
	rm -rf floppy && mkdir floppy
	for f in INSTALL.BAT UNINSTAL.BAT NETBOOT.BAT GAMES.INI README.TXT; do
		sed "s/\r\$//; s/\$/\r/" /src/$f > floppy/$f      # DOS line ends
	done
	cp obj/NPMENU.EXE obj/NPIPX.COM floppy/
	cp /dos/crynwr/NE2000.COM floppy/NE2000.COM
	rm -f NETPLAY.IMG
	mformat -C -f 1440 -v NETPLAY -i NETPLAY.IMG ::
	MTOOLS_NO_VFAT=1 mcopy -i NETPLAY.IMG floppy/* ::/
	mdir -i NETPLAY.IMG ::/
'
ls -la "$work/NPMENU.EXE" "$work/NPIPX.COM" "$work/NETPLAY.IMG"
