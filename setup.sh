#!/usr/bin/env bash
# Sets up the netplay workspace next to this script:
#   NES_MiSTer/   your fork (or upstream), branch "netplay" with the core patch
#   SNES_MiSTer/  your fork (or upstream), branch "netplay" with the core patch
#   Gameboy2P_MiSTer/  Gameboy2PUW_MiSTer (pomstazlesa), branch "netplay" (work in progress)
#   Main_MiSTer/  your fork (or upstream), branch "netplay" with the HPS patch
#   jtcores/      Jotego's jtcores (arcade cores, jtframe), branch "netplay" (work in progress)
#
# Use your own forks so you can push:
#   NES_URL=git@github.com:<you>/NES_MiSTer.git MAIN_URL=git@github.com:<you>/Main_MiSTer.git ./setup.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NES_URL="${NES_URL:-https://github.com/MiSTer-devel/NES_MiSTer.git}"
SNES_URL="${SNES_URL:-https://github.com/MiSTer-devel/SNES_MiSTer.git}"
GB2P_URL="${GB2P_URL:-https://github.com/pomstazlesa/Gameboy2PUW_MiSTer.git}"
MAIN_URL="${MAIN_URL:-https://github.com/MiSTer-devel/Main_MiSTer.git}"
JTCORES_URL="${JTCORES_URL:-https://github.com/jotego/jtcores.git}"

# The patches were written against these upstream commits.
NES_BASE=49a0a662e244469ca77b2155746a066df704ffae
SNES_BASE=4c2b74661b4c4c44eefb6b13743fcaf988bc8063
GB2P_BASE=83e167f8fbcf76559951125d58a8104fc019308b
MAIN_BASE=08271656799ede50358de1248f6ee878dd7ce5c4
JTCORES_BASE=15d60ca4f7f8e050b38eefee8c2125657ae65b37

setup_repo() {
	local dir=$1 url=$2 base=$3 patches=$4
	if [ ! -d "$here/$dir/.git" ]; then
		git clone "$url" "$here/$dir"
	fi
	cd "$here/$dir"
	git fetch --quiet origin
	if git rev-parse --verify --quiet netplay >/dev/null; then
		echo "$dir: branch netplay already exists, leaving it alone"
	else
		git checkout -b netplay "$base"
		if ls "$here/patches/$patches"/*.patch >/dev/null 2>&1; then
			git am --3way "$here/patches/$patches"/*.patch
		fi
		echo "$dir: branch netplay created on $base"
	fi
	cd "$here"
}

setup_repo NES_MiSTer  "$NES_URL"  "$NES_BASE"  NES_MiSTer
setup_repo SNES_MiSTer "$SNES_URL" "$SNES_BASE" SNES_MiSTer
setup_repo Gameboy2P_MiSTer "$GB2P_URL" "$GB2P_BASE" Gameboy2P_MiSTer
setup_repo Main_MiSTer "$MAIN_URL" "$MAIN_BASE" Main_MiSTer
setup_repo jtcores "$JTCORES_URL" "$JTCORES_BASE" jtcores
# the sound chips Bubble Bobble needs (jtbubl)
git -C "$here/jtcores" submodule update --init --recursive modules/jt12 modules/jtopl

echo
echo "Done. Building and testing: see README.md."
