#!/usr/bin/env bash

# Minimal robust shell options:
# -E: inherit ERR trap in functions
# -e: exit on error
# -u: error on unset variables
# -o pipefail: fail on first failed command in pipelines
set -Eeuo pipefail

# Target block device (change to the correct device before running)
DISK="/dev/nvme0n1"

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
    
mkdir -p /mnt/.snapshots
mount -o subvol=@snapshots,compress=zstd,noatime,ssd "${DISK}p5" /mnt/.snapshots

mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd,noatime,ssd "${DISK}p6" /mnt/home

mkdir -p /mnt/boot
mount -o rw,noatime,umask=0077 "${DISK}p3" /mnt/boot

mkdir -p /mnt/efi
mount -o rw,noatime,umask=0077 "${DISK}p2" /mnt/efi

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

echo "You may now customize the installation inside the chroot."
arch-chroot /mnt /bin/bash

timedatectl set-timezone Asia/Singapore
timedatectl set-ntp true
systemctl enable systemd-timesyncd
ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
hwclock --systohc

bootctl --esp-path=/efi --boot-path=/boot install

pacman -S networkmanager --noconfirm --needed
systemctl enable NetworkManager

pacman -S pacman-contrib --noconfirm --needed
systemctl enable paccache.timer

pacman -S plymounth --noconfirm --needed

pacman -S iptables-nft ufw

pacman -S mesa --noconfirm --needed

# Exit chroot
exit
umount -R /mnt