#!/usr/bin/env bash
# Collects a release in releases/<version>/ and tags the source it came from.
#
#   tools/make_release.sh v0.2
#
# Checks first that everything is committed and that the builds are newer than
# the sources: the core (.rbf; Quartus is not re-run, tools/quartus_build.sh),
# Main_MiSTer (rebuilt here, it is quick) and the server (server/build.sh when
# Docker runs, else the existing builds must be newer than the Go files).
# The binaries stay out of git (releases/ is ignored); the tag <version> in this
# repo and in NES_MiSTer and Main_MiSTer marks their source.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ver="${1:-}"
[[ "$ver" =~ ^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$ ]] || { echo "usage: $0 v<major>.<minor>  (e.g. v0.2)"; exit 1; }
out="$root/releases/$ver"
[ -e "$out" ] && { echo "$out exists already"; exit 1; }
cd "$root"

fail() { echo "not released: $*"; exit 1; }

# SOURCE.txt: where the binaries come from (the public repo's tag, the upstreams)
write_source() {
	{
		echo "NES netplay $ver, $(date '+%Y-%m-%d')"
		echo
		echo "Source code: https://github.com/vivitheblackmage/misternetplay, tag $ver"
		echo "  NES core:    github.com/MiSTer-devel/NES_MiSTer  $(sed -n 's/^NES_BASE=\(.......\).*/\1/p' setup.sh) + patches/NES_MiSTer ($(ls patches/NES_MiSTer/*.patch | wc -l) patches)"
		echo "  Main binary: github.com/MiSTer-devel/Main_MiSTer $(sed -n 's/^MAIN_BASE=\(.......\).*/\1/p' setup.sh) + patches/Main_MiSTer ($(ls patches/Main_MiSTer/*.patch | wc -l) patches)"
		echo "  Server, tools, NetPong: in the repository itself."
		echo
		echo "./setup.sh at that tag recreates both source trees. Licence GPL-3.0."
	} > "$1"
}
clean() {   # $1 repo dir; the miniz ChangeLog shows as modified from line endings and is ignored
	local d
	d=$(git -C "$1" status --porcelain --untracked-files=no | grep -v ' lib/miniz/ChangeLog.md$' || true)
	[ -z "$d" ] || fail "$1 has uncommitted changes:"$'\n'"$d"
}
clean .
clean NES_MiSTer
clean Main_MiSTer
for r in . NES_MiSTer Main_MiSTer; do
	git -C "$r" rev-parse -q --verify "refs/tags/$ver" >/dev/null && fail "tag $ver exists in $r"
done

# patches/ must be what the repos' netplay branches hold
for r in NES_MiSTer Main_MiSTer; do
	var=NES_BASE; [ "$r" = Main_MiSTer ] && var=MAIN_BASE
	base=$(sed -n "s/^$var=\(.*\)/\1/p" setup.sh)
	n_repo=$(git -C "$r" rev-list --count "$base..HEAD")
	n_patch=$(ls patches/"$r"/*.patch | wc -l)
	[ "$n_repo" = "$n_patch" ] || fail "$r has $n_repo commits on $base but patches/$r has $n_patch (export with git format-patch)"
done

# core: the .rbf must be newer than every tracked source file (not the ones
# Quartus itself rewrites at the end of a build: .qsf, .cdf, pin dump)
rbf=NES_MiSTer/output_files/NES.rbf
[ -f "$rbf" ] || fail "no $rbf (tools/quartus_build.sh)"
newest=$(cd NES_MiSTer && git ls-files -z -- . ':!*.md' ':!sim/*' ':!*.qsf' ':!*.cdf' ':!*pin_model_dump.txt' | xargs -0 stat -c '%Y %n' | sort -n | tail -1)
[ "${newest%% *}" -le "$(stat -c %Y "$rbf")" ] || fail "$rbf is older than ${newest#* } (rebuild with tools/quartus_build.sh)"

# Main_MiSTer: rebuild (incremental)
(cd Main_MiSTer && set +u && source setup_default_toolchain.sh >/dev/null && make -j8 >/dev/null) || fail "Main_MiSTer build"

# server
if docker info >/dev/null 2>&1; then server/build.sh >/dev/null || fail "server build"; fi
for f in netplay-server.exe netplay-server-linux-amd64 netplay-server-linux-arm64 netplay-server-linux-armv7 install-linux.sh; do
	[ -f "server/build/$f" ] || fail "no server/build/$f (server/build.sh, needs Docker)"
	for g in server/*.go server/install-linux.sh; do
		[ "server/build/$f" -nt "$g" ] || fail "server/build/$f is older than $g (server/build.sh, needs Docker)"
	done
done

tools/make_kit.sh >/dev/null

mkdir -p "$out/server"
cp "$rbf" "$out/NES_netplay.rbf"
cp Main_MiSTer/bin/MiSTer "$out/MiSTer_online"
cp dist/netplay-kit.zip "$out/"
cp server/build/netplay-server* server/build/install-linux.sh server/README.md "$out/server/"
chmod +x "$out/MiSTer_online" "$out"/server/netplay-server-linux-* "$out/server/install-linux.sh"
write_source "$out/SOURCE.txt"
tools/make_bundle.sh "$out" >/dev/null       # nes-netplay-<version>.zip: everything ready in one file
(cd "$out" && find . -type f ! -name md5sums.txt | sort | xargs md5sum > md5sums.txt)

# Nothing private may be in a release (names, addresses, paths, e-mail)
if [ -x tools/check_private.sh ]; then
	tools/check_private.sh "$out" || { rm -rf "$out"; fail "private data in the release (see above)"; }
fi

for r in . NES_MiSTer Main_MiSTer; do git -C "$r" tag -a "$ver" -m "NES netplay $ver"; done
echo "releases/$ver:"
(cd "$out" && find . -type f | sort | sed 's|^\./|  |')
echo "Tagged $ver in this repo, NES_MiSTer and Main_MiSTer."
