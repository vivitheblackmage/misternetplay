#!/bin/bash
# MiSTer Scripts menu: switch to the netplay Main_MiSTer binary and reboot.
# Your normal binary is kept as /media/fat/MiSTer_offline.
cd /media/fat || exit 1
[ -f MiSTer_online ] || { echo "No /media/fat/MiSTer_online - deploy it first."; exit 1; }
if cmp -s MiSTer MiSTer_online; then
	echo "Netplay binary is already active."
	exit 0
fi
cp MiSTer MiSTer_offline || exit 1
cp MiSTer_online MiSTer.new && chmod +x MiSTer.new && mv MiSTer.new MiSTer || exit 1
echo "Netplay ON. Rebooting..."
sync; sleep 2; reboot
