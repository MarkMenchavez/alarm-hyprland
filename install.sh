#!/usr/bin/env bash

# Minimal robust shell options:
# -E: inherit ERR trap in functions
# -e: exit on error
# -u: error on unset variables
# -o pipefail: fail on first failed command in pipelines
set -Eeuo pipefail

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Target block device (change to the correct device before running)
DISK="/dev/nvme0n1"

# Ensure disk exists
if [[ ! -b "$DISK" ]]; then
  echo "Block device $DISK not found." >&2
  exit 1
fi

# Unmount any mounts on this disk
for m in $(mount | awk -v d="$DISK" '$0 ~ d {print $3}'); do
  echo "Unmounting $m"
  umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
done

# Disable swap on partitions of this disk
for s in $(swapon --noheadings --raw | awk -v d="$DISK" '$1 ~ d {print $1}'); do
  echo "Turning off swap $s"
  swapoff "$s" 2>/dev/null || true
done

# WARNING: destructive -- wipes filesystem signatures on the device
# Make sure $DISK is correct before running this script.
wipefs -a "${DISK}"

# Create a GPT partition table using sfdisk. The heredoc below defines
# the partition sizes and partition type GUIDs. Adjust sizes/GUIDs if
# your target layout differs.
# The GUIDs used below map to the following partition types (see README):
#  - 21686148-6449-6E6F-744E-656564454649  => BIOS boot partition (p1)
#  - C12A7328-F81F-11D2-BA4B-00A0C93EC93B  => EFI System Partition (ESP) (p2)
#  - BC13C2FF-59E6-4262-A352-B275FD6F7172  => Linux extended boot (p3)
#  - 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F  => Linux swap (p4)
#  - B921B045-1DF0-41C3-AF44-4C6F280D3FAE  => Linux root arm-64 (p5)
#  - 933AC7E1-2EB4-4F13-B844-0E14E2AEF915  => Linux home (p6)
sfdisk "$DISK" <<'EOF'
label: gpt
,512M, 21686148-6449-6E6F-744E-656564454649
,1024M, C12A7328-F81F-11D2-BA4B-00A0C93EC93B
,2048M, BC13C2FF-59E6-4262-A352-B275FD6F7172
,8192M, 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
,40960M, B921B045-1DF0-41C3-AF44-4C6F280D3FAE
,,933AC7E1-2EB4-4F13-B844-0E14E2AEF915
EOF

# Ask the kernel to re-read the partition table and wait for udev to
# create the corresponding device nodes (e.g. ${DISK}p2).
blockdev --rereadpt "${DISK}"
udevadm settle --timeout=5 || true

# Format partitions.
mkfs.fat -F32 "${DISK}p2"
mkfs.fat -F32 "${DISK}p3"
mkswap "${DISK}p4"
mkfs.btrfs -f "${DISK}p5"
mkfs.btrfs -f "${DISK}p6"

# Create btrfs subvolumes on the main data partition and then unmount
mount "${DISK}p5" /mnt  
btrfs subvolume create /mnt/@  
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@spool
btrfs subvolume create /mnt/@vartmp
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
umount -R /mnt

mount "${DISK}p6" /mnt
btrfs subvolume create /mnt/@home
umount -R /mnt

# Mount subvolumes with recommended compression and noatime to reduce
# write amplification. `ssd` mount option is harmless on many systems
# and can help on flash-backed storage.
mount -o subvol=@,compress=zstd,noatime,ssd "${DISK}p5" /mnt

mkdir -p /mnt/var/log
mount -o subvol=@log,compress=lzo,noatime,ssd "${DISK}p5" /mnt/var/log

mkdir -p /mnt/var/cache
mount -o subvol=@cache,compress=lzo,noatime,ssd "${DISK}p5" /mnt/var/cache

mkdir -p /mnt/var/spool
mount -o subvol=@spool,compress=lzo,noatime,ssd "${DISK}p5" /mnt/var/spool

mkdir -p /mnt/var/tmp
mount -o subvol=@vartmp,compress=lzo,noatime,ssd "${DISK}p5" /mnt/var/tmp

mkdir -p /mnt/tmp
mount -o subvol=@tmp,compress=zstd,noatime,ssd "${DISK}p5" /mnt/tmp

mkdir -p /mnt/.snapshots
mount -o subvol=@snapshots,compress=zstd,noatime,ssd "${DISK}p5" /mnt/.snapshots

mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd,noatime,ssd "${DISK}p6" /mnt/home

mkdir -p /mnt/boot
mount -o rw,noatime,umask=0077 "${DISK}p3" /mnt/boot

mkdir -p /mnt/boot/efi
mount -o rw,noatime,umask=0077 "${DISK}p2" /mnt/boot/efi

swapon "${DISK}p4"

# Show resulting partition layout for verification
lsblk "${DISK}"

# Ensure minimal target /etc exists and write console settings before
# running pacstrap. Some package hooks (mkinitcpio for the kernel)
# execute during pacstrap and expect `/etc/vconsole.conf` to exist.
mkdir -p /mnt/etc
cat > /mnt/etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=ter-v16n
EOF

# Install a minimal set of packages into the new system. Add or remove
# packages as needed for your target environment (especially the kernel
# package for aarch64 if your repository differs).
PACKAGES=(
    base
    linux
    linux-firmware

    iptables-nft

    device-mapper
    btrfs-progs
    dosfstools

    terminus-font
    nano

    sudo
    polkit
)

pacstrap /mnt "${PACKAGES[@]}" --needed --noconfirm

# Generate fstab with UUIDs and append to target fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Ensure `en_US.UTF-8 UTF-8` is enabled in the target locale.gen so
# running `locale-gen` inside the chroot will generate the locale.
if [ -f /mnt/etc/locale.gen ]; then
  sed -i 's/^#\s*en_US.UTF-8\s\+UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen || true
fi

# Enter chroot to perform further configuration
arch-chroot /mnt /bin/bash <<'CHROOT_EOF'

echo Setting hostname.
echo "vm-alarm-hyprland" > /etc/hostname

echo "Setting timezone with NTP enabled."
timedatectl set-timezone Asia/Singapore
timedatectl set-ntp true
systemctl enable systemd-timesyncd
ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
hwclock --systohc

echo Generating locales.
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

echo Enabling periodic cleanup of cached packages.
pacman -S pacman-contrib --noconfirm --needed
systemctl enable paccache.timer

# Prepare systemd-boot configuration files on the target ESP/boot so they
# exist after installation. Determine PARTUUID for the root partition (p5)
# and write a boot entry referencing it.
DISK="/dev/nvme0n1"
PARTUUID="$(blkid -s PARTUUID -o value "${DISK}p5" || true)"

echo Installing bootloader.
bootctl --esp-path=/boot/efi --boot-path=/boot install

cat > /boot/efi/loader/loader.conf <<'EOF'
default arch
timeout 0
editor 0
EOF

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux ARM
linux   /Image
initrd  /initramfs-linux.img
options root=PARTUUID=$PARTUUID rootfstype=btrfs rw rootflags=rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvolid=256,subvol=@ quiet splash loglevel=0 rd.udev.log_level=0
EOF

# set required MODULES
sed -i 's/^MODULES=.*/MODULES=(btrfs vfat crc32c)/' /etc/mkinitcpio.conf
# This is redundant since plymouth-set-default-theme -R calls mkinitcpio
#mkinitcpio -P 

echo Enabling Boot splash theme.
pacman -S plymouth --noconfirm --needed

# simple edit: insert plymouth between systemd and autodetect
sed -i 's/systemd[[:space:]]\+autodetect/systemd plymouth autodetect/' /etc/mkinitcpio.conf
plymouth-set-default-theme -R spinfinity
    
# plymouth-set-default-theme -R <theme> already calls mkinitcpio internally
#mkinitcpio -P

echo Enabling networking services.
pacman -S networkmanager --noconfirm --needed
systemctl enable NetworkManager

#pacman -S timeshift --noconfirm --needed
#pacman -S ufw --noconfirm --needed
#pacman -S mesa --noconfirm --needed

CHROOT_EOF

# Exit chroot
#umount -R /mnt