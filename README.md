# Arch Linux ARM

<https://archlinuxarm.org>

----

## Virtual Machine

| Settings             |                                                      |
|----------------------|------------------------------------------------------|
| Host                 | M1 Macbook Pro                                       |
| Type 2 Hypervisor    | VMWare Fusion 26H1                                   |
| Operating System     | Other Linux 6.x 64-bit Arm                           |
| Name                 | Arch Linux ARM Hyprland                              |
| Processors           | 4                                                    |
| Memory               | 8192 MB                                              |
| Display              | 3D Acceleration                                      |
|                      | 8192 MB Shared Memory                                |
|                      | Full Resolution for Retina Display                   |
| Networking           | Bridged                                              |
|                      | Additional computer on the physical Ethernet network |
| Storage              | NVMe 80 GB                                           |
| Keyboard & Mouse     | Mac Profile                                          |
  
## ISO

<https://archboot.com>

archboot-2025.12.31-xxxxxxx-aarch64-ARCH-local-aarch64.iso

## Networking

    systemctl restart systemd-networkd
    systemctl restart systemd-resolved

    ip link show
    ip addr show
    ping 8.8.8.8
    ping mirror.archlinuxarm.org

### Partition

`cfdisk /dev/nvme0n1`

gpt label

| Partition  | Size   | Type                |Type UUID                           |
|------------|-------:|:-------------------:|:----------------------------------:|
| nvme0n1p1  | 1024M  | EFI System          |C12A7328-F81F-11D2-BA4B-00A0C93EC93B|
| nvme0n1p2  | 2048M  | Linux extended boot |BC13C2FF-59E6-4262-A352-B275FD6F7172|
| nvme0n1p3  | rest   | Linux root arm-64   |B921B045-1DF0-41C3-AF44-4C6F280D3FAE|

### Format

    mkfs.fat -F32 /dev/nvme0n1p1
    mkfs.fat -F32 /dev/nvme0n1p2
    mkfs.btrfs -L ARCH /dev/nvme0n1p3

### BTRFS Subvolumes

    mount /dev/nvme0n1p3 /mnt  
    btrfs subvolume create /mnt/@  
    btrfs subvolume create /mnt/@home
    umount -R /mnt

### Mount

    mount -o subvol=@,compress=zstd,noatime /dev/nvme0n1p3 /mnt

    mkdir -p /mnt/home
    mount -o subvol=@home,compress=zstd,noatime /dev/nvme0n1p3 /mnt/home

    mkdir -p /mnt/boot
    mount /dev/nvme0n1p2 /mnt/boot

    mkdir -p /mnt/efi
    mount /dev/nvme0n1p1 /mnt/efi

### Pacstrap

    pacstrap /mnt base \
                  linux \
                  linux-firmware \
                  device-mapper \
                  btrfs-progs \
                  dosfstools \
                  iptables-nft \
                  terminus-font \
                  nano \
                  sudo \
                  polkit

### FSTAB
  
    lsblk -f

    genfstab -U -p /mnt >> /mnt/etc/fstab

### CHROOT

    arch-chroot /mnt

#### Hostname
  
    echo "vm-alarm-hyprland" > /etc/hostname

### Console

    nano /etc/vconsole.conf
      KEYMAP=us
      FONT=ter-v16n

#### Locale

    nano /etc/locale.gen
       en_US.UTF-8 UTF-8
    locale-gen
    
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

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
      options root=PARTUUID=<PARTUUID-of-p3> rootfstype=btrfs rw rootflags=rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvolid=256,subvol=@ quiet splash loglevel=0 rd.udev.log_level=0

    blkid /dev/nvme0n1p3

#### MKINITCPIO

    pacman -S plymouth

    nano /etc/mkinitcpio.conf
          MODULES=(btrfs vfat crc32c)
          HOOKS=(...systemd plymouth...)

    plymouth-set-default-theme -R spinfinity
    
    # This might be redundant, 
    # plymouth-set-default-theme -R <theme> already calls mkinitcpio internally
    # mkinitcpio -P

#### Services

    pacman -S networkmanager --noconfirm --needed
    systemctl enable NetworkManager

    pacman -S pacman-contrib --noconfirm --needed
    systemctl enable paccache.timer

#### User Accounts  
  
    useradd -m -G wheel -s /bin/bash mcdm -c "Mark Menchavez"
    passwd mcdm
  
    EDITOR=nano visudo
      %wheel ALL=(ALL) ALL

#### Done
  
    exit
    umount -R /mnt
    reboot

#### Date and Time

    timedatectl set-local-rtc 0
    timedatectl set-timezone Asia/Singapore
    timedatectl set-ntp true

    # These are redundant.
    # systemctl enable systemd-timesyncd
    # ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
    # hwclock --systohc

#### Enable Swapfile / ZRAM

    btrfs filesystem mkswapfile --size 8G /swapfile
    swapon /swapfile

    sudo nano /etc/fstab
    /swapfile none swap defaults 0 0

    pacman -S zram-generator
    sudo nano /etc/systemd/zram-generator.conf
    [zram0]
    zram-size = ram / 2
    compression-algorithm = zstd
    swap-priority = 100

    sudo systemctl daemon-reload
    
    sudo systemctl restart systemd-zram-setup@zram0.service
    
    echo "vm.swappiness=80" | sudo tee /etc/sysctl.d/99-swappiness.conf
    sudo sysctl --system

#### Packages

    pacman -S fastfetch htop gping 
    
    pacman -S hyprland             
              
              mesa mesa-utils vulkan-tools
              
              kitty                
              
              mako                 

              pipewire 
              pipewire-alsa
              pipewire-pulse
              gst-plugin-pipewire
              wireplumber
              pavucontrol              
              
              xdg-desktop-portal
              xdg-desktop-portal-hyprland
              xdg-desktop-portal-gtk
              
              hyprpolkitagent

              qt5-wayland
              qt6-wayland

              noto-fonts
              ttf-jetbrains-mono-nerd

  #### Hyprland Config

      mkdir -p ~/.config/hypr
      cp /usr/share/hypr/hyprland.lua ~/.config/hypr

      nano ~/.config/hypr/hyprland.lua

      env 
      LIBGL_ALWAYS_SOFTWARE = 1

      monitor
         output = Virtual-1
         mode   = 2048x1152@60
         position = 0x0
         scale = 1

      autostart
         systemctl --user start hyprpolkitagent

      keybinds
         Return       - Terminal
         B            - Browser
         Q            - Close current window
         SHIFT X      - Exit Hyprland

#### Pipewire / Wireplumber

    # These are not needed. They automatically start after reboot
    systemctl --user enable --now pipewire.service
    systemctl --user enable --now pipewire-pulse.service
    systemctl --user enable --now wireplumber.service

    # Only if audio does stutter
    sudo nano /usr/share/wireplumber.conf.d/alsa-vm.conf
      audio.format "S16LE"
      
#### AUR

    sudo pacman -S base-devel git
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si

#### Browser

    yay -S brave-bin

#### Display Manager

    sudo pacman -S sddm qt6-declarative qt6-svg
    yay -S pixie-sddm-git

    sudo mkdir -p /etc/sddm.conf.d
    sudo nano /etc/sddm.conf.d/theme.conf
      [Theme]
      Current=pixie
    
    sudo systemctl enable sddm

#### Others

    sudo pacman -S xdg-user-dirs
    xdg-user-dirs-update

    sudo pacman -S starship
    

    
