#!/bin/sh
# Installs netplay-server as a service that starts at boot, on Linux with
# systemd (Raspberry Pi OS, Debian, Ubuntu). Run it from the folder with the
# netplay-server-linux-* files:
#
#   sudo sh install-linux.sh            install or update, then start
#   sudo sh install-linux.sh remove     stop and remove (keeps /opt/netplay-server)
#
# Settings, the key, the roms folder and catalog.txt live in /opt/netplay-server.
# Log: journalctl -u netplay-server -f
set -eu

dir=/opt/netplay-server
unit=/etc/systemd/system/netplay-server.service
here=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" -eq 0 ] || { echo "Run it with sudo: sudo sh $0 $*"; exit 1; }
command -v systemctl >/dev/null || { echo "No systemd here: start $dir/netplay-server by hand."; exit 1; }

if [ "${1:-}" = remove ]; then
	systemctl disable --now netplay-server 2>/dev/null || true
	rm -f "$unit"
	systemctl daemon-reload
	echo "Removed the service. Settings and games are still in $dir."
	exit 0
fi

case "$(uname -m)" in
	aarch64|arm64) bin=netplay-server-linux-arm64 ;;
	armv7l|armv6l|armhf) bin=netplay-server-linux-armv7 ;;
	x86_64|amd64) bin=netplay-server-linux-amd64 ;;
	*) echo "No build for $(uname -m)"; exit 1 ;;
esac
[ -f "$here/$bin" ] || { echo "Missing $here/$bin (copy the whole build folder)"; exit 1; }

id netplay >/dev/null 2>&1 || useradd --system --home-dir "$dir" --shell /usr/sbin/nologin netplay
mkdir -p "$dir/roms"
systemctl stop netplay-server 2>/dev/null || true
install -m 0755 "$here/$bin" "$dir/netplay-server"
chown -R netplay:netplay "$dir"

cat > "$unit" <<EOF
[Unit]
Description=netplay-server (MiSTer NES netplay lobby and relay)
After=network-online.target
Wants=network-online.target

[Service]
User=netplay
WorkingDirectory=$dir
ExecStart=$dir/netplay-server -config $dir/netplay-server.ini
Restart=always
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$dir
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now netplay-server

# the first start writes netplay-server.ini with a new key
for i in 1 2 3 4 5 6 7 8 9 10; do [ -f "$dir/netplay-server.ini" ] && break; sleep 0.5; done
key=$(sed -n 's/^key=\([^ ;]*\).*/\1/p' "$dir/netplay-server.ini" 2>/dev/null | head -1)
port=$(sed -n 's/^port=\([0-9]*\).*/\1/p' "$dir/netplay-server.ini" 2>/dev/null | head -1)
ip=$(hostname -I 2>/dev/null | cut -d' ' -f1)
echo
echo "netplay-server is running and starts at boot."
echo "  Settings: $dir/netplay-server.ini   Games to hand out: $dir/roms"
echo "  Forward port ${port:-7845} (UDP and TCP) in the router to ${ip:-this machine}."
echo "  In each MiSTer's netplay.ini:  server=<your address>:${port:-7845}   key=$key"
echo "  Rooms in a browser: http://${ip:-localhost}:${port:-7845}/?key=$key"
echo "  Log: journalctl -u netplay-server -f"
