#!/usr/bin/env bash
# Build a core with Quartus in Docker and check timing (SPEC.md T4).
#
#   tools/quartus_build.sh            build NES_MiSTer, then check timing
#   tools/quartus_build.sh --timing   only check the last build's timing
#   CORE=SNES tools/quartus_build.sh  the same for SNES_MiSTer
#   CORE=Gameboy CORE_DIR=Gameboy2P_MiSTer tools/quartus_build.sh  project name != folder
#
# Needs the mister-quartus17 image (tools/quartus-docker/README.md).
# Result: <CORE>_MiSTer/output_files/<CORE>.rbf, log in <CORE>_MiSTer/output_files/quartus.log.
# Exit 0 only if the build succeeded and no timing path has negative slack.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="${QUARTUS_IMAGE:-mister-quartus17}"
name="${CORE:-NES}"
core="$root/${CORE_DIR:-${name}_MiSTer}"
out="$core/output_files"

if [ "${1:-}" != "--timing" ]; then
	if ! docker image inspect "$image" >/dev/null 2>&1; then
		echo "Docker image '$image' not found. Build it first: see tools/quartus-docker/README.md"
		exit 1
	fi
	mkdir -p "$out"
	start=$(date +%s)
	echo "Building $name core in $image (usually 10-30 min)..."
	docker run --rm -v "$core":/build -w /build "$image" quartus_sh --flow compile "$name" > "$out/quartus.log" 2>&1
	rc=$?
	echo "Quartus finished in $(( ($(date +%s) - start) / 60 )) min, exit $rc"
	if [ $rc -ne 0 ]; then
		echo "BUILD FAILED. Errors:"
		grep -E "^Error|Error \(" "$out/quartus.log" | head -30
		exit 1
	fi
fi

summary="$out/$name.sta.summary"
[ -f "$summary" ] || { echo "no $summary"; exit 1; }
neg=$(grep -B1 -E "^Slack *: *-" "$summary")
if [ -n "$neg" ]; then
	echo "TIMING FAILED (negative slack):"
	echo "$neg"
	exit 1
fi
echo "TIMING OK: $(grep -c '^Slack' "$summary") paths, none negative"
[ -f "$out/$name.rbf" ] && echo "RBF: $out/$name.rbf ($(du -h "$out/$name.rbf" | cut -f1))"
exit 0
