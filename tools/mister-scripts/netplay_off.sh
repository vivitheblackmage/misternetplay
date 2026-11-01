#!/bin/bash
# MiSTer Scripts menu: switch back to your normal Main_MiSTer binary and reboot.
cd /media/fat || exit 1
if [ -f MiSTer_online ] && ! cmp -s MiSTer MiSTer_online; then
	echo "Netplay binary is not active, nothing to do."
	exit 0
fi
[ -f MiSTer_offline ] || { echo "No /media/fat/MiSTer_offline to go back to."; exit 1; }
cp MiSTer_offline MiSTer.new && chmod +x MiSTer.new && mv MiSTer.new MiSTer || exit 1
echo "Netplay OFF. Rebooting..."
sync; sleep 2; reboot
