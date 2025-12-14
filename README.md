# Arch Linux ARM

<https://archlinuxarm.org>

----

## Virtual Machine

| Settings             |                                                      |
|----------------------|------------------------------------------------------|
| Host                 | M1 Macbook Pro                                       |
| Type 2 Hypervisor    | VMWare Fusion 13.6                                   |
| Operating System     | Other 64-bit Arm                                     |
| Name                 | Arch Linux ARM Hyprland                              |
| Processors           | 4                                                    |
| Memory               | 8192 MB                                              |
| Display              | 3D Acceleration                                      |
|                      | 8192 MB Shared Memory                                |
|                      | Full Resolution for Retina Display                   |
| Networking           | Bridged                                              |
|                      | Additional computer on the physical Ethernet network |
| Storage              | NVMe 80 GB                                           |
| Default Applications | None                                                 |
| Keyboard & Mouse     | Mac Profile                                          |
  
## ISO

<https://archboot.com>

archboot-2025.12.07-02.09-6.18.0-3-aarch64-ARCH-local-aarch64.iso

## Network

    systemctl restart systemd-networkd
    systemctl restart systemd-resolved
    ip link show
    ip addr show
    ping 8.8.8.8
    ping mirror.archlinuxarm.org

## Install

`curl -fsSL https://raw.githubusercontent.com/markmenchavez/alarm-hyprland/main/install.sh | bash`

### Partition

`cfdisk /dev/nvme0n1`

gpt label

| Partition  | Size   | Type                |Type UUID                           |
|------------|-------:|:-------------------:|:----------------------------------:|
| nvme0n1p1  | 512M   | BIOS boot           |21686148-6449-6E6F-744E-656564454649|
| nvme0n1p2  | 1024M  | EFI System          |C12A7328-F81F-11D2-BA4B-00A0C93EC93B|
| nvme0n1p3  | 2048M  | Linux extended boot |BC13C2FF-59E6-4262-A352-B275FD6F7172|
| nvme0n1p4  | 8192M  | Linux swap          |0657FD6D-A4AB-43C4-84E5-0933C84B4F4F|
| nvme0n1p5  | 40960M | Linux root arm-64   |B921B045-1DF0-41C3-AF44-4C6F280D3FAE|
| nvme0n1p6  | rest   | Linux home          |933AC7E1-2EB4-4F13-B844-0E14E2AEF915|

### Format

    mkfs.fat -F32 /dev/nvme0n1p2
    mkfs.fat -F32 /dev/nvme0n1p3
    mkswap /dev/nvme0n1p4
    mkfs.btrfs /dev/nvme0n1p5
    mkfs.btrfs /dev/nvme0n1p6

### BTRFS Subvolumes

    mount /dev/nvme0n1p5 /mnt  
    btrfs subvolume create /mnt/@  
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@cache
    btrfs subvolume create /mnt/@snapshots
    umount -R /mnt

    mount /dev/nvme0n1p6 /mnt
    btrfs subvolume create /mnt/@home
    umount -R /mnt

### Mount

    mount -o subvol=@,compress=zstd,noatime,ssd /dev/nvme0n1p5 /mnt

    mount -o subvol=@log,compress=lzo,noatime,ssd /dev/nvme0n1p5 /mnt/var/log
    mount -o subvol=@cache,compress=lzo,noatime,ssd /dev/nvme0n1p5 /mnt/var/cache
    
    mkdir -p /mnt/.snapshots
    mount -o subvol=@snapshots,compress=zstd,noatime,ssd /dev/nvme0n1p5 /mnt/.snapshots

    mkdir -p /mnt/home
    mount -o subvol=@home,compress=zstd,noatime,ssd /dev/nvme0n1p6 /mnt/home
    
    mkdir -p /mnt/boot
    mount -o rw,noatime,umask=0077 /dev/nvme0n1p3 /mnt/boot
    
    mkdir -p /mnt/efi
    mount -o rw,noatime,umask=0077 /dev/nvme0n1p2 /mnt/efi
    
    swapon /dev/nvme0n1p4

### Console

    mkdir -p /mnt/etc
    nano /etc/vconsole.conf
      KEYMAP=us
      FONT=ter-v16n

### Pacstrap

    pacstrap /mnt base \
                  linux \
                  linux-firmware \
                  device-mapper \
                  networkmanager \
                  polkit \
                  iptables-nft \
                  btrfs-progs \
                  dosfstools \
                  terminus-font \
                  nano \
                  sudo \
                  plymouth \
                  pacman-contrib

### FSTAB
  
    lsblk -f

    genfstab -U -p /mnt >> /mnt/etc/fstab

### CHROOT

    arch-chroot /mnt

#### MKINITCPIO

    nano /etc/mkinitcpio.conf
          MODULES=(btrfs vfat crc32c)
          HOOKS=(...systemd plymouth...)

    plymounth-set-default-theme -R spinfinity
    
    # This might be redundant, 
    # plymouth-set-default-theme -R <theme> already calls mkinitcpio internally
    mkinitcpio -P

#### Date and Time

    timedatectl set-timezone Asia/Singapore
    timedatectl set-ntp true
    systemctl enable systemd-timesyncd
    ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
    hwclock --systohc

#### Locale

    nano /etc/locale.gen
      en_US.UTF-8 UTF-8
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

#### Hostname
  
    echo "vm-alarm-hyprland" > /etc/hostname

#### User Accounts  
  
    passwd
  
    useradd -m -G wheel -s /bin/bash mcdm -c "Mark Menchavez"
    passwd mcdm
  
    EDITOR=nano visudo
      %wheel ALL=(ALL) ALL

#### Boot loader

    bootctl --esp-path=/efi --boot-path=/boot install

    nano /efi/loader/loader.conf
      default arch
      timeout 0
      editor 0
  
    nano /boot/loader/entries/arch.conf
      title   Arch Linux ARM
      linux   /Image
      initrd  /initramfs-linux.img
      options root=PARTUUID=<PARTUUID-of-p5> rootfstype=btrfs rw rootflags=rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvolid=256,subvol=@ quiet splash loglevel=0 rd.udev.log_level=0

    blkid /dev/nvme0n1p5

    bootctl --esp-path=/efi --path=/boot/efi update

#### Services

    systemctl enable NetworkManager
    systemctl enable paccache.timer

#### Packages

    pacman -Sy mesa

#### Done
  
    exit
    umount -R /mnt
    reboot
    