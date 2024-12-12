#!/bin/bash

# Exit on error
set -e

# User configuration
HOSTNAME="framework13"
USERNAME="your_username"
ROOT_PART="/dev/sda2"
EFI_PART="/dev/sda1"
SWAP_SIZE="0" # Set to "96G" if you want a swap file
PRINTER_SUPPORT=true # Set to "false" to skip printer support

echo "Starting Arch Linux installation..."

# Step 1: Partition the Disk
echo "Partitioning the disk..."
parted /dev/sda --script mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 boot on \
    mkpart primary ext4 513MiB 100%

# Step 2: Format Partitions
echo "Formatting partitions..."
mkfs.fat -F32 $EFI_PART
mkfs.ext4 $ROOT_PART

# Step 3: Mount Partitions
echo "Mounting partitions..."
mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $EFI_PART /mnt/boot

# Step 4: Install Base System
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Step 5: Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Step 6: Configure System in Chroot
echo "Configuring system in chroot..."
arch-chroot /mnt <<EOF

# Timezone and Clock
echo "Setting timezone..."
if timedatectl | grep -q "Time zone"; then
    echo "Timezone detected online."
    timedatectl set-timezone "$(timedatectl | grep 'Time zone' | awk '{print $3}')"
else
    echo "Unable to detect timezone. Please select manually."
    ln -sf /usr/share/zoneinfo/$(ls /usr/share/zoneinfo | fzf) /etc/localtime
fi
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname and Networking
echo "$HOSTNAME" > /etc/hostname
cat <<EOL >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Root Password
echo "Setting root password..."
echo "root:root" | chpasswd

# Bootloader
echo "Installing bootloader..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install essential packages
echo "Installing essential packages..."
pacman -S --noconfirm networkmanager sudo nano git base-devel fzf bluez bluez-utils \
    pipewire pipewire-pulse pipewire-alsa wireplumber wl-clipboard grimblast swaybg \
    mesa vulkan-radeon libva-mesa-driver lib32-mesa lib32-vulkan-radeon brightnessctl \
    power-profiles-daemon libgtop pacman-contrib docker zathura zathura-pdf-mupdf \
    thunar libreoffice-still gimp thunderbird btop emacs alacritty dunst wofi \
    noto-fonts noto-fonts-emoji ttf-liberation ttf-dejavu cups hplip system-config-printer \
    cpupower tlp ufw
systemctl enable NetworkManager bluetooth.service cups.service cpupower.service tlp.service ufw.service

# Swap Management
if [ "$SWAP_SIZE" != "0" ]; then
    echo "Creating swap file..."
    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
else
    echo "Skipping swap setup."
fi

# Hyprland Configuration
echo "Installing and configuring Hyprland..."
pacman -S --noconfirm hyprland hyprpanel hyprpaper hyprsunset hypridle hyprlock
yay -S --noconfirm waybar-dark-light

mkdir -p /home/$USERNAME/.config/hypr
cat <<HYPR > /home/$USERNAME/.config/hypr/hyprland.conf
# Hyprland Configuration
monitor=,preferred,auto,auto
layout=master
masterfactor=0.6
gaps_outer=10
gaps_inner=15
border_size=2
bind=SUPER,T,exec,alacritty
bind=SUPER,F,exec,firefox
bind=SUPER,L,exec,hyprlock
HYPR

# Dynamic Dotfiles Backup System with Git
echo "Setting up dynamic dotfiles backup system with Git..."

# Initialize dotfiles Git repository
mkdir -p /home/$USERNAME/dotfiles-repo
cd /home/$USERNAME/dotfiles-repo
git init
cat <<README > /home/$USERNAME/dotfiles-repo/README.md
# Dotfiles Repository

This repository contains all your dotfiles for easy management and versioning.
README

# Create backup script
cat <<'BACKUP_SCRIPT' > /usr/local/bin/backup-dotfiles.sh
#!/bin/bash

# Set variables
DOTFILES_REPO="/home/$USER/dotfiles-repo"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Copy all dotfiles to the repo
rsync -av --progress /home/$USER/.[!.]* /home/$USER/..?* "$DOTFILES_REPO" --exclude="$DOTFILES_REPO"

# Commit and push changes
cd "$DOTFILES_REPO"
git add .
git commit -m "Backup on $TIMESTAMP"
# Uncomment the following line after adding a remote
# git push origin main

echo "Dotfiles backup completed and committed to Git!"
BACKUP_SCRIPT

# Make the script executable
chmod +x /usr/local/bin/backup-dotfiles.sh

# Optional: Schedule daily backups via cron
echo "Setting up daily backup cron job..."
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/backup-dotfiles.sh") | crontab -

EOF

# Final steps
umount -R /mnt
echo "Installation complete! Rebooting now."
reboot
