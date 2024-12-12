#!/bin/bash
# Exit on error
set -e
# Prompt for user configuration
read -p "Enter the hostname for your system: " HOSTNAME
read -p "Enter the username you want to create: " USERNAME
read -sp "Enter the password for $USERNAME: " USER_PASSWORD
echo
read -sp "Enter the root password: " ROOT_PASSWORD
echo
read -p "Enter the swap size (e.g., 4G or 0 for none): " SWAP_SIZE
EFI_PART="/dev/sda1"
ROOT_PART="/dev/sda2"
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
pacstrap /mnt base linux linux-firmware base-devel
# Step 5: Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
# Step 6: Configure System in Chroot
arch-chroot /mnt /bin/bash <<EOF
# Timezone and Clock
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/$(ls /usr/share/zoneinfo | fzf) /etc/localtime
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
echo "root:$ROOT_PASSWORD" | chpasswd
# Bootloader
echo "Installing bootloader..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
# Essential Packages (including NetworkManager and git)
echo "Installing essential packages..."
pacman -S --noconfirm networkmanager git sudo nano bluez bluez-utils \
    pipewire pipewire-pulse pipewire-alsa wireplumber wl-clipboard swaybg \
    mesa vulkan-radeon brightnessctl power-profiles-daemon tlp ufw cups hplip \
    system-config-printer cpupower greetd wayland xdg-desktop-portal-wlr xorg-xwayland \
    gvfs libgtop btop dart-sass swww python gnome-bluetooth-3.0 pacman-contrib
# Enable Services
echo "Enabling services..."
systemctl enable NetworkManager bluetooth.service cups.service cpupower.service tlp.service ufw.service greetd.service
# Set default target to graphical.target
systemctl set-default graphical.target
# Swap Management
if [ "$SWAP_SIZE" != "0" ]; then
    echo "Creating swap file..."
    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi
# Create User
echo "Creating user $USERNAME..."
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
# Configure greetd for Hyprland
echo "Configuring greetd for Hyprland..."
mkdir -p /etc/greetd
cat <<GREETD > /etc/greetd/config.toml
[terminal]
vt = 1
[default_session]
command = "Hyprland"
user = "$USERNAME"
[initial_session]
command = "Hyprland"
user = "$USERNAME"
GREETD
EOF
# Step 7: Post-Chroot Configurations
arch-chroot /mnt /bin/bash <<EOF
# Install yay
echo "Installing yay..."
git clone https://aur.archlinux.org/yay.git /opt/yay
chown -R $USERNAME: /opt/yay
cd /opt/yay
sudo -u $USERNAME makepkg -si --noconfirm
# Hyprland Configuration
echo "Installing and configuring Hyprland..."
pacman -S --noconfirm hyprland hyprpanel hyprpaper hyprsunset hypridle hyprlock
yay -S --noconfirm grimblast-git gpu-screen-recorder hyprpicker matugen-bin python-gpustat hyprsunset-git hypridle-git
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
exec-once = agsv1
HYPR
chown -R $USERNAME: /home/$USERNAME/.config/hypr
# Install Nerd Fonts for HyprPanel
echo "Installing Nerd Fonts (JetBrainsMono)..."
cd /home/$USERNAME
git clone https://github.com/ryanoasis/nerd-fonts.git
cd nerd-fonts
./install.sh JetBrainsMono
# Install HyprPanel
echo "Installing HyprPanel..."
mv /home/$USERNAME/.config/ags /home/$USERNAME/.config/ags.bkup || true
git clone https://github.com/Jas-SinghFSU/HyprPanel.git
ln -s /home/$USERNAME/HyprPanel /home/$USERNAME/.config/ags
# Set permissions
chown -R $USERNAME: /home/$USERNAME/.config/ags
EOF

# Final Checks
echo "Checking if greetd service is enabled and running..."
systemctl is-enabled greetd.service || (echo "greetd service is not enabled!"; exit 1)
systemctl status greetd.service || (echo "greetd service is not running!"; exit 1)

# Verify Hyprland installation
if ! command -v Hyprland &> /dev/null; then
    echo "Hyprland is not installed or not found in the PATH!"
    exit 1
else
    echo "Hyprland is installed."
fi

# Verify HyprPanel installation
if [ ! -d "/home/$USERNAME/.config/ags" ]; then
    echo "HyprPanel is not installed!"
    exit 1
else
    echo "HyprPanel is installed."
fi

# Final Steps
umount -R /mnt
echo "Installation complete! Rebooting now."
reboot
