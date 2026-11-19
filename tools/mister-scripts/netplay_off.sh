#!/bin/bash
# MiSTer Scripts menu: switch back to your normal Main_MiSTer binary and reboot.
cd "${NP_FAT:-/media/fat}" || exit 1
# a netplay binary has netplay.ini in it; the normal MiSTer binary does not
if ! grep -q -F netplay.ini MiSTer; then
	echo "Netplay binary is not active, nothing to do."
	exit 0
fi
# netplay_on before v0.5 saved the active netplay binary as MiSTer_offline on an
# update: then get the official binary first (normal_main.py checks its MD5).
fix=Scripts/.config/netplay/normal_main.py
if [ ! -f MiSTer_offline ] || grep -q -F netplay.ini MiSTer_offline; then
	echo "MiSTer_offline is not your normal MiSTer binary (an older netplay_on saved"
	echo "the netplay one there). Getting the official one..."
	if ! { [ -f "$fix" ] && python3 "$fix"; }; then
		echo "Could not get it. Connect the MiSTer to the network and run"
		echo "netplay_off again."
		exit 1
	fi
fi
cp MiSTer_offline MiSTer.new && chmod +x MiSTer.new && mv MiSTer.new MiSTer || exit 1
echo "Netplay OFF. Rebooting..."
sync; sleep 2; reboot
