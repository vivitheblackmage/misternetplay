#!/usr/bin/env bash
# T3e-i: the MiSTer scripts that put the ao486 netplay menu on all DOS disks
# (test_ao486_install.py says what is checked). Loop mounts need a privileged
# container (debian:bookworm with mtools, dosfstools, fdisk).
#
#   tools/mister-scripts/test_ao486_install.sh <NETPLAY.IMG> <dos disk image> <work dir>
#
# The disk image is copied, never changed; <work dir>/out/installed.vhd is the
# copy after the install, for a boot test.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
floppy="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
disk="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
work="$(mkdir -p "$3" && cd "$3" && pwd)"
docker run --rm --privileged -v "$here":/s:ro -v "$floppy":/f.img:ro -v "$disk":/d.img:ro -v "$work":/w debian:bookworm bash -euc '
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq && apt-get install -y -qq python3 mtools dosfstools fdisk >/dev/null
	python3 -I /s/test_ao486_install.py /s /f.img /d.img /w/out
'
