#!/usr/bin/env bash
# Builds a small Linux disk for the MiSTer ao486 core with the NE2000 network
# card (SPEC.md 15): Linux 6.18 LTS for a 486SX (FPU emulated), BusyBox, all in
# RAM (initramfs), booted by SYSLINUX from a FAT16 partition, as a fixed VHD.
#
#   tools/ao486/linux/build.sh <work dir>     ->  <work dir>/ao486-linux.vhd
#
# Everything is built in Docker (debian:bookworm); downloads are kept in the
# work dir. Nothing of the result goes into git.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mkdir -p "${1:?usage: $0 <work dir>}" && cd "$1" && pwd)"

docker run --rm -v "$here":/recipe:ro -v "$work":/work -w /work debian:bookworm bash /recipe/inside.sh
ls -la "$work/ao486-linux.vhd"
