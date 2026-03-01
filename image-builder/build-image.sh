#!/usr/bin/env bash
set -ex

# This script runs inside a privileged Debian container (Docker), 
# which allows it to use loopback devices and mount ext4 file systems,
# something macOS cannot do natively.

WORK_DIR="/build/work"
IMG_NAME="lite-image.img"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# 1. Download the latest Pi OS Lite (Bookworm 64-bit)
if [ ! -f "${IMG_NAME}" ]; then
    echo "Downloading Raspberry Pi OS Lite (Bookworm 64-bit)..."
    wget -qO pi-os.img.xz "https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz"
    unxz pi-os.img.xz
    mv 2024-11-19-raspios-bookworm-arm64-lite.img "${IMG_NAME}"
fi

# Expand the image slightly to give us room to install Node and Chromium
dd if=/dev/zero bs=1M count=2000 >> "${IMG_NAME}"
parted "${IMG_NAME}" resizepart 2 100%
e2fsck -f -p $(bash -c 'loop=$(losetup -P -f --show "${IMG_NAME}"); echo ${loop}p2')
resize2fs $(bash -c 'loop=$(losetup -P -f --show "${IMG_NAME}"); echo ${loop}p2')

# Map the image partitions
LOOP_DEV=$(losetup -P -f --show "${IMG_NAME}")
BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"

ROOTFS="/build/rootfs"
mkdir -p "${ROOTFS}"
mount "${ROOT_DEV}" "${ROOTFS}"
mount "${BOOT_DEV}" "${ROOTFS}/boot/firmware"

# Mount pseudo-filesystems needed for chroot
mount --bind /dev "${ROOTFS}/dev"
mount --bind /sys "${ROOTFS}/sys"
mount --bind /proc "${ROOTFS}/proc"
mount --bind /dev/pts "${ROOTFS}/dev/pts"

# Copy QEMU so we can execute ARM64 binaries inside the chroot
cp /usr/bin/qemu-aarch64-static "${ROOTFS}/usr/bin/"

# Copy our app code into the image
mkdir -p "${ROOTFS}/home/pi/Slideshow"
cp -r /app/svelte "${ROOTFS}/home/pi/Slideshow/"
cp /app/deploy.sh "${ROOTFS}/home/pi/Slideshow/"
cp /app/tune-pi.sh "${ROOTFS}/home/pi/Slideshow/"

# Execute a setup script INSIDE the Pi image
cat << 'EOF' > "${ROOTFS}/setup-chroot.sh"
#!/usr/bin/env bash
set -ex

# We are now executing inside the ARM64 Pi OS filesystem!
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Pi default user might not exist yet if generating from scratch, but we are using off-the-shelf lite.
# Update the system
apt-get update
apt-get install -y curl wget git

# Now, we simply call our deploy script, which installs Node, Chromium, builds the app, etc.
# But we need to fake $SUDO_USER
cd /home/pi/Slideshow
chmod +x deploy.sh tune-pi.sh
SUDO_USER=pi ./deploy.sh
# And apply tuning (which installs cage, sets governor, tweaks cmdline)
SUDO_USER=pi ./tune-pi.sh

# Let's ensure the repo has correct ownership
chown -R pi:pi /home/pi/Slideshow
EOF

chmod +x "${ROOTFS}/setup-chroot.sh"

echo "Chrooting into Pi image to run installation..."
chroot "${ROOTFS}" /bin/bash /setup-chroot.sh
rm "${ROOTFS}/setup-chroot.sh"

# Cleanup
echo "Cleaning up..."
umount "${ROOTFS}/dev/pts"
umount "${ROOTFS}/proc"
umount "${ROOTFS}/sys"
umount "${ROOTFS}/dev"
umount "${ROOTFS}/boot/firmware"
umount "${ROOTFS}"
losetup -D

mv "${IMG_NAME}" /app/slideshow-kiosk.img

echo "Done! Image saved to slideshow-kiosk.img"
