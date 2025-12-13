#!/usr/bin/env bash

set -Eeuo pipefail

DISK="/dev/nvme0n1"

wipefs -a "${DISK}"

sfdisk "$DISK" <<'EOF'
label: gpt
,512M, 21686148-6449-6E6F-744E-656564454649
,1024M, C12A7328-F81F-11D2-BA4B-00A0C93EC93B
,2048M, BC13C2FF-59E6-4262-A352-B275FD6F7172
,8192M, 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
,40960M, B921B045-1DF0-41C3-AF44-4C6F280D3FAE
,,933AC7E1-2EB4-4F13-B844-0E14E2AEF915
EOF

mkfs.fat -F32 /dev/nvme0n1p2
mkfs.fat -F32 /dev/nvme0n1p3
mkswap /dev/nvme0n1p4
mkfs.btrfs /dev/nvme0n1p5
mkfs.btrfs /dev/nvme0n1p6

mount /dev/nvme0n1p5 /mnt  
btrfs subvolume create /mnt/@  
umount -R /mnt

mount /dev/nvme0n1p6 /mnt
btrfs subvolume create /mnt/@home
umount -R /mnt

mount -o subvol=@,compress=zstd,noatime,ssd /dev/nvme0n1p5 /mnt
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd,noatime,ssd /dev/nvme0n1p6 /mnt/home
mkdir -p /mnt/boot
mount -o rw,noatime,umask=0077 /dev/nvme0n1p3 /mnt/boot
mkdir -p /mnt/efi
mount -o rw,noatime,umask=0077 /dev/nvme0n1p2 /mnt/efi
swapon /dev/nvme0n1p4

lsblk "${DISK}"