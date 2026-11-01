#!/usr/bin/env bash
# Sets up the netplay workspace next to this script:
#   NES_MiSTer/   your fork (or upstream), branch "netplay" with the core patch
#   Main_MiSTer/  your fork (or upstream), branch "netplay" with the HPS patch
#
# Use your own forks so you can push:
#   NES_URL=git@github.com:<you>/NES_MiSTer.git MAIN_URL=git@github.com:<you>/Main_MiSTer.git ./setup.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
NES_URL="${NES_URL:-https://github.com/MiSTer-devel/NES_MiSTer.git}"
MAIN_URL="${MAIN_URL:-https://github.com/MiSTer-devel/Main_MiSTer.git}"

# The patches were written against these upstream commits.
NES_BASE=49a0a662e244469ca77b2155746a066df704ffae
MAIN_BASE=08271656799ede50358de1248f6ee878dd7ce5c4

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
		git am --3way "$here/patches/$patches"/*.patch
		echo "$dir: branch netplay created on $base"
	fi
	cd "$here"
}

setup_repo NES_MiSTer  "$NES_URL"  "$NES_BASE"  NES_MiSTer
setup_repo Main_MiSTer "$MAIN_URL" "$MAIN_BASE" Main_MiSTer

echo
echo "Done. Building and testing: see README.md."
