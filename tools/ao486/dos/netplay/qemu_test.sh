#!/usr/bin/env bash
# T3e-m: the netplay menu in QEMU (qemu_test.py says what is checked).
#
#   tools/ao486/dos/netplay/qemu_test.sh <dos disk image> <work dir>
#
# <work dir> must hold NETPLAY.IMG from build.sh. The disk image is copied,
# never changed. Uses the np-qemu Docker image (qemu-system-i386).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
disk="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
work="$(cd "$2" && pwd)"
docker run --rm -v "$here":/src:ro -v "$disk":/disk.img:ro -v "$work":/work np-qemu bash -euc '
	export DEBIAN_FRONTEND=noninteractive
	command -v mtype >/dev/null || { apt-get update -qq && apt-get install -y -qq mtools >/dev/null; }
	python3 -I /src/qemu_test.py /disk.img /work/NETPLAY.IMG /work/qemu
'
