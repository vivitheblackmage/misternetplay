#!/usr/bin/env bash
# Builds a jtframe arcade core for MiSTer with Quartus 20.1 in Docker
# (image jotego/jtcore20, the version Jotego builds MiSTer cores with).
#
#   tools/jt_build.sh [core]        default: bubl  -> jtcores/release/mister/...
#
# LD_PRELOAD: Quartus 20.1 ships a libudev.so.1 that crashes quartus_map (flexlm host id
# scan, "realloc(): invalid pointer"); the system one works.
# --nodbg: a release build (JTFRAME_RELEASE), without the debug figures on screen.
# Log: jtcores/jt_build.log
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
core="${1:-bubl}"
# The core's version string (V, in the OSD and in netplay's "Different core
# version" check) is jtcores' commit: building uncommitted changes would give
# a different core the same version as an older build.
dirty=$(git -C "$root/jtcores" status --porcelain --untracked-files=no)
if [ -n "$dirty" ]; then
	echo "jtcores has uncommitted changes: commit them first (the core's version is the commit)"
	echo "$dirty"
	exit 1
fi
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libudev.so.1 -e GOTOOLCHAIN=local -e GOCACHE=/tmp/gocache \
	-v "$root/jtcores":/jtcores -w /jtcores jotego/jtcore20 \
	-c "source setprj.sh >/dev/null && jtcore $core -t mister --nolinter --nodbg" \
	2>&1 | tee "$root/jtcores/jt_build.log"
