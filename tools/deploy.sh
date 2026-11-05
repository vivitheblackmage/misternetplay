#!/usr/bin/env bash
# Copy the netplay builds to a MiSTer over SSH (default password: 1).
#
#   tools/deploy.sh <mister-ip> [core|main|ini|all] [--no-reboot]
#
#   core  NES_MiSTer/output_files/NES.rbf  -> /media/fat/_Console/NES_netplay.rbf
#         SNES_MiSTer/output_files/SNES.rbf -> /media/fat/_Console/SNES_netplay.rbf
#         (each when built)
#   main  Main_MiSTer/bin/MiSTer           -> /media/fat/MiSTer_online, plus
#         Scripts/netplay_on.sh and netplay_off.sh to switch (your MiSTer is kept)
#   ini   tools/netplay.ini.example        -> /media/fat/netplay.ini (only if missing)
#
# A new MiSTer binary only takes effect after a reboot. The script reboots only
# when the netplay binary is the active one (and not with --no-reboot).
set -euo pipefail

# ssh/scp ask for the MiSTer's password (default 1). Without a terminal (from a
# script), tools/sshpw.py types it when it is there; MISTER_PW, default 1.
if [ -z "${SSHPW_WRAPPED:-}" ] && [ ! -t 0 ] && [ -f "$(dirname "$0")/sshpw.py" ]; then
	export SSHPW_WRAPPED=1 SSHPW="${MISTER_PW:-1}"
	exec python3 -I "$(dirname "$0")/sshpw.py" "$0" "$@"
fi

host="${1:?usage: deploy.sh <mister-ip> [core|main|ini|all] [--no-reboot]}"
what="${2:-all}"
reboot=1
[ "${3:-}" = "--no-reboot" ] && reboot=0

root="$(cd "$(dirname "$0")/.." && pwd)"
ssh_opts=(-o StrictHostKeyChecking=accept-new)

if [[ "$what" == core || "$what" == all ]]; then
	n=0
	for c in NES SNES; do
		rbf="$root/${c}_MiSTer/output_files/$c.rbf"
		[ -f "$rbf" ] || continue
		scp "${ssh_opts[@]}" "$rbf" "root@$host:/media/fat/_Console/${c}_netplay.rbf"
		echo "core -> /media/fat/_Console/${c}_netplay.rbf"
		n=$((n + 1))
	done
	[ $n -gt 0 ] || { echo "no core built - build one in Quartus first"; exit 1; }
fi

if [[ "$what" == main || "$what" == all ]]; then
	bin="$root/Main_MiSTer/bin/MiSTer"
	[ -f "$bin" ] || { echo "no $bin - run make in Main_MiSTer first"; exit 1; }
	# /media/fat/MiSTer (the binary that boots) is left alone, unless the
	# netplay binary is the active one: then it is updated too.
	ssh "${ssh_opts[@]}" "root@$host" 'mkdir -p /media/fat/Scripts'
	scp "${ssh_opts[@]}" "$bin" "root@$host:/media/fat/MiSTer_online.new"
	scp "${ssh_opts[@]}" "$root"/tools/mister-scripts/netplay_{on,off}.sh "root@$host:/media/fat/Scripts/"
	active=$(ssh "${ssh_opts[@]}" "root@$host" 'cd /media/fat && chmod +x MiSTer_online.new Scripts/netplay_on.sh Scripts/netplay_off.sh &&
		if [ -f MiSTer_online ] && cmp -s MiSTer MiSTer_online; then
			cp MiSTer_online.new MiSTer.new && mv MiSTer.new MiSTer && echo yes
		else echo no; fi
		mv MiSTer_online.new MiSTer_online')
	echo "main -> /media/fat/MiSTer_online, scripts -> /media/fat/Scripts/netplay_on.sh, netplay_off.sh"
	if [ "$active" = yes ]; then
		echo "netplay binary was active: /media/fat/MiSTer updated too"
	else
		echo "your normal /media/fat/MiSTer is untouched; run netplay_on from the Scripts menu to switch"
		reboot=0
	fi
fi

if [[ "$what" == ini || "$what" == all ]]; then
	ssh "${ssh_opts[@]}" "root@$host" '[ -f /media/fat/netplay.ini ]' \
		&& echo "netplay.ini already on the MiSTer, not touched" \
		|| { scp "${ssh_opts[@]}" "$root/tools/netplay.ini.example" "root@$host:/media/fat/netplay.ini"; echo "ini -> /media/fat/netplay.ini"; }
fi

if [[ ( "$what" == main || "$what" == all ) && $reboot == 1 ]]; then
	echo "rebooting $host"
	ssh "${ssh_opts[@]}" "root@$host" 'sync; reboot' || true
fi
