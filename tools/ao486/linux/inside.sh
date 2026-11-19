#!/usr/bin/env bash
# The build itself, inside debian:bookworm (build.sh). /recipe: this folder,
# /work: downloads, sources and the result.
set -euo pipefail

KVER=6.18.64
BBVER=1.36.1
DISK_MB=64

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential bc flex bison libelf-dev wget xz-utils bzip2 cpio \
	syslinux syslinux-common mtools dosfstools fdisk python3 >/dev/null

cd /work
[ -f linux-$KVER.tar.xz ] || wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
[ -f busybox-$BBVER.tar.bz2 ] || wget -q https://busybox.net/downloads/busybox-$BBVER.tar.bz2
[ -f i486-linux-musl-cross.tgz ] || wget -q https://musl.cc/i486-linux-musl-cross.tgz
[ -d linux-$KVER ] || tar xf linux-$KVER.tar.xz
[ -d busybox-$BBVER ] || tar xf busybox-$BBVER.tar.bz2
[ -d i486-linux-musl-cross ] || tar xf i486-linux-musl-cross.tgz
export PATH=/work/i486-linux-musl-cross/bin:$PATH

# ---- the kernel: tinyconfig + the ao486 fragment
cd /work/linux-$KVER
make -s ARCH=i386 tinyconfig
scripts/kconfig/merge_config.sh -m .config /recipe/kernel.config >/dev/null
make -s ARCH=i386 olddefconfig
for o in M486SX MATH_EMULATION NE2000 ISA BLK_DEV_INITRD VGA_CONSOLE KEYBOARD_ATKBD INET PACKET DEVTMPFS; do
	grep -q "^CONFIG_$o=y" .config || { echo "kernel option $o did not stick"; exit 1; }
done
make -s ARCH=i386 -j"$(nproc)" bzImage
cp arch/x86/boot/bzImage /work/bzImage

# ---- BusyBox, static, for i486 (musl)
cd /work/busybox-$BBVER
make -s defconfig
sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
       -e 's/^CONFIG_CROSS_COMPILER_PREFIX=.*/CONFIG_CROSS_COMPILER_PREFIX="i486-linux-musl-"/' \
       -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
       -e 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' \
       -e 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config   # SHA-NI: not on a 486
make -s oldconfig </dev/null >/dev/null
make -s -j"$(nproc)"
rm -rf /work/rootfs && mkdir -p /work/rootfs
make -s CONFIG_PREFIX=/work/rootfs install >/dev/null

# ---- the root file system (in RAM)
cd /work/rootfs
mkdir -p proc sys dev tmp root etc www usr/share
cp -r /recipe/rootfs/. .
cp /work/busybox-$BBVER/examples/udhcp/simple.script etc/udhcpc.script
chmod +x etc/udhcpc.script etc/rc init
printf 'root::0:0:root:/root:/bin/sh\n' > etc/passwd
printf 'root:x:0:\n' > etc/group
find . | cpio -o -H newc --quiet | gzip -9 > /work/initrd.gz

# ---- the disk: MBR + one FAT16 partition from sector 63, SYSLINUX
cd /work
total=$((DISK_MB * 2048))
part=$((total - 63))
rm -f part.img disk.img
dd if=/dev/zero of=part.img bs=512 count=$part status=none
mkfs.fat -F 16 -h 63 -n AO486LINUX part.img >/dev/null
cat > syslinux.cfg <<'EOF'
DEFAULT linux
PROMPT 0
TIMEOUT 0
LABEL linux
  KERNEL bzImage
  INITRD initrd.gz
  APPEND console=tty0 ne.io=0x300 ne.irq=11 netdev=11,0x300,eth0
EOF
mcopy -i part.img bzImage initrd.gz syslinux.cfg ::/
syslinux --install part.img
dd if=/dev/zero of=disk.img bs=512 count=63 status=none
cat part.img >> disk.img
printf 'start=63, type=6, bootable\n' | sfdisk -q disk.img
dd if=/usr/lib/syslinux/mbr/mbr.bin of=disk.img conv=notrunc bs=440 count=1 status=none

# ---- a fixed VHD footer (the MiSTer reads the raw sectors; the footer is for other tools)
python3 /recipe/vhd_footer.py disk.img ao486-linux.vhd
ls -la bzImage initrd.gz ao486-linux.vhd
