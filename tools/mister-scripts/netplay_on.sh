#!/bin/bash
# MiSTer Scripts menu: switch to the netplay Main_MiSTer binary and reboot.
# Your normal binary is kept as /media/fat/MiSTer_offline. When MiSTer is an
# older netplay binary already (an update), it is replaced and MiSTer_offline
# stays your normal one.
cd "${NP_FAT:-/media/fat}" || exit 1
# Since v0.7 the netplay cores live in _Netplay, with their build date in the
# name (NES_netplay_20261118.rbf). Copies left in _Console or _Computer by
# older releases would be started by game shortcuts (MGL files and MiSTer_SAM
# name a core without its date, and the largest name wins), so they go once a
# _Netplay copy is there; so do older versions in _Netplay and _Arcade/cores.
newest() { ls "$@" 2>/dev/null | sort | tail -n 1; }
for c in NES SNES GAMEBOY2P GBA NeoGeo ao486; do
	n=$(newest _Netplay/${c}_netplay_*.rbf _Netplay/${c}_netplay.rbf)
	[ -n "$n" ] || continue
	for f in _Console/${c}_netplay.rbf _Console/${c}_netplay_*.rbf _Computer/${c}_netplay.rbf _Computer/${c}_netplay_*.rbf \
	         _Netplay/${c}_netplay.rbf _Netplay/${c}_netplay_*.rbf; do
		[ -f "$f" ] && [ "$f" != "$n" ] && rm -f "$f" && echo "Removed the old $f ($n is the one now)."
	done
done
n=$(newest _Arcade/cores/jtbubl-netplay_*.rbf)
if [ -n "$n" ]; then
	for f in _Arcade/cores/jtbubl-netplay.rbf _Arcade/cores/jtbubl-netplay_*.rbf; do
		[ -f "$f" ] && [ "$f" != "$n" ] && rm -f "$f" && echo "Removed the old $f ($n is the one now)."
	done
fi
# netplay_on before v0.5 saved the active netplay binary as MiSTer_offline on an
# update, so netplay_off had nothing to go back to: get the official one now.
fix=Scripts/.config/netplay/normal_main.py
if [ -f MiSTer ] && grep -q -F netplay.ini MiSTer && { [ ! -f MiSTer_offline ] || grep -q -F netplay.ini MiSTer_offline; }; then
	echo "MiSTer_offline is not your normal MiSTer binary (an older netplay_on saved"
	echo "the netplay one there). Getting the official one..."
	[ -f "$fix" ] && python3 "$fix" || echo "Not now (no network?). netplay_off tries again."
fi
[ -f MiSTer_online ] || { echo "No /media/fat/MiSTer_online - deploy it first."; exit 1; }
if cmp -s MiSTer MiSTer_online; then
	echo "Netplay binary is already active."
	exit 0
fi
# a netplay binary has netplay.ini in it; the normal MiSTer binary does not
if grep -q -F netplay.ini MiSTer; then
	echo "Updating the netplay binary (MiSTer_offline is kept)."
else
	cp MiSTer MiSTer_offline || exit 1
fi
cp MiSTer_online MiSTer.new && chmod +x MiSTer.new && mv MiSTer.new MiSTer || exit 1
echo "Netplay ON. Rebooting..."
sync; sleep 2; reboot
