#!/usr/bin/env bash
# Builds netplay-server for Windows, Linux x86-64, Linux ARM64 (Raspberry Pi 3/4/5
# with 64-bit Raspberry Pi OS) and ARMv7 (32-bit Raspberry Pi OS, MiSTer) into
# server/build/, with Go in Docker (no Go install needed).
set -euo pipefail
cd "$(dirname "$0")"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e GOCACHE=/tmp/gocache -v "$PWD":/src -w /src golang:1.22-bookworm sh -c '
  go vet ./... && go test ./... &&
  CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w" -o build/netplay-server-linux-amd64 . &&
  GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w" -o build/netplay-server.exe . &&
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w" -o build/netplay-server-linux-arm64 . &&
  GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w" -o build/netplay-server-linux-armv7 .'
cp install-linux.sh build/
ls -l build/
