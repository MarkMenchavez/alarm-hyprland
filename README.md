# alarm-hyprland

* Download from ARCHBOOT ISO file
  https://archboot.com
  archboot-2025.12.07-02.09-6.18.0-3-aarch64-ARCH-local-aarch64.iso

* Create Virtual Machine
  Type 2 Hypervisor   : VMWare Fusion 13.6 @ M1
  Operating System    : Other 64-bit Arm
  Name                : Arch Linux ARM Hyprland
  Processors          : 4
  Memory              : 8192MB
  Display             : 3D Acceleration 8192MB Shared Memory Full Resolution for Retina Display
  Networking          : Bridged, additional computer on the physical Ethernet network
  Storage             : NVMe 80GB
  Default Applications: None
  Keyboard & Mouse    : Mac Profile

* Boot from ISO file
  
* Partition and Format Manually
  1. cfdisk /dev/nvme0n1
     gpt label
     p1 512M   BIOS boot
     p2 2048M  EFI System
     p3 2048M  Linux extended boot
     p4 8192M  Linux swap
     p5 40960M Linux root arm-64
     p6 rest   Linux home
  2. mkfs.btrfs /dev/nvme0n1p5
     mkfs.btrfs /dev/nvme0n1p6
     mkswap /dev/nvme0n1p4
     mkfs.fat -F32 /dev/nvme0n1p3
     mkfs.fat -F32 /dev/nvme0n1p2
  3. mount /dev/nvme0n1p5 /mnt
     btrfs subvolume create /mnt/@
     umount -R /mnt
     mount /dev/nvme0n1p6 /mnt
     btrfs subvolume create /mnt/@home
     umount -R /mnt
  4. mount -o subvol=@,compress=zstd,noatime,ssd /dev/nvme0n1p5 /mnt
     mkdir /mnt/home
     mount -o subvol=@home,compress=zstd,noatime,ssd /dev/nvme0n1p6 /mnt/home
     mkdir /mnt/boot
     mount -o rw,noatime /dev/nvme0n1p3 /mnt/boot
     mkdir -p /mnt/efi
     mount -o rw,noatime,umask=0077 /dev/nvme0n1p2 /mnt/efi
     swapon /dev/nvme0n1p4

* Connect to Network
  systemctl restart systemd-networkd
  systemctl restart systemd-resolved
  ip link show
  ip addr show
  ping 8.8.8.8
  ping mirror.archlinuxarm.org

* Install Arch Linux ARM
  pacstrap /mnt base linux linux-firmware btrfs-progs nano sudo
  genfstab -U -p /mnt >> /mnt/etc/fstab
  arch-chroot /mnt
  mkinitcpio -P
  ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
  hwclock --systohc
  nano /etc/locale.gen
  en_US.UTF-8 UTF-8
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf
  echo "vm-alarm-hyprland" > /etc/hostname
  cat >> /etc/hosts <<EOF
    127.0.0.1   localhost
    ::1         localhost
  EOF
  passwd
  useradd -m -G wheel -s /bin/bash mcdm
  passwd mcdm
  EDITOR=nano visudo
  %wheel ALL=(ALL) ALL

  bootctl --esp-path=/efi --boot-path=/boot install

  /efi/loader/loader.conf
  default arch
  timeout 3
  editor 0
  
  /boot/loader/entries/arch.conf
  title   Arch Linux ARM
  linux   /Image
  initrd  /initramfs-linux.img
  options root=PARTUUID=<PARTUUID-of-p5> rootfstype=btrfs rw rootflags=rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvolid=256,subvol=@

  blkid /dev/nvme0n1p5

  bootctl --esp-path=/efi --path=/boot/efi update
  
