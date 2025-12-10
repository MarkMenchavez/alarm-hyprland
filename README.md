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
     p3 2048M  Linux filesystem
     p4 8192M  Linux swap
     p5 40960M Linux filesystem
     p6 rest   Linux filesystem
  2. mkfs.btrfs /dev/nvme0n1p5
     mkfs.btrfs /dev/nvme0n1p6
     mkswap /dev/nvme0n1p4
     swapon /dev/nvme0n1p4
     mkfs.ext4 /dev/nvme0n1p3
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
     mkdir -p /mnt/boot/efi
     mount -o rw,noatime,umask=0077 /dev/nvme0n1p2 /mnt/boot/efi

* Connect to Network
  ip link show
  ip link set ens160 up
     
