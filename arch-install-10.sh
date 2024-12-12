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
pacstrap /mnt base linux linux-firmware

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

# Essential Packages
echo "Installing essential packages..."
pacman -S --noconfirm networkmanager gnome-bluetooth-3.0 pipewire pipewire-pulse pipewire-alsa wl-clipboard brightnessctl dart-sass bluez bluez-utils libgtop sudo nano git base-devel cups pacman-contrib btop swww gvfs power-profiles-daemon

# Enable Services
echo "Enabling services..."
systemctl enable NetworkManager bluetooth.service cups.service

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

# Set default target to graphical
systemctl set-default graphical.target
EOF

# Step 7: Post-Chroot Configurations
arch-chroot /mnt /bin/bash <<EOF
# Install yay
echo "Installing yay..."
git clone https://aur.archlinux.org/yay.git /home/$USERNAME/yay
chown -R $USERNAME: /home/$USERNAME/yay
sudo -u $USERNAME bash -c "cd /home/$USERNAME/yay && makepkg -si --noconfirm"

# Configure yay to use a custom build directory
sudo -u $USERNAME bash -c "
mkdir -p /home/$USERNAME/aur-builds
yay --save --builddir /home/$USERNAME/aur-builds
"

# Install AUR packages
echo "Installing AUR packages..."
sudo -u $USERNAME yay -S --noconfirm grimblast-git gpu-screen-recorder hyprpicker matugen-bin python-gpustat hyprsunset-git hypridle-git aylurs-gtk-shell

# Set up HyprPanel
echo "Installing and configuring HyprPanel..."
git clone https://github.com/Jas-SinghFSU/HyprPanel.git /home/$USERNAME/HyprPanel
chown -R $USERNAME: /home/$USERNAME/HyprPanel
sudo -u $USERNAME bash -c "
mv /home/$USERNAME/.config/ags /home/$USERNAME/.config/ags.bkup 2>/dev/null || true
ln -s /home/$USERNAME/HyprPanel /home/$USERNAME/.config/ags
cd /home/$USERNAME/HyprPanel
./install_fonts.sh
"

# Configure Hyprland to launch HyprPanel
echo "exec-once = agsv1" >> /home/$USERNAME/.config/hypr/hyprland.conf
chown $USERNAME: /home/$USERNAME/.config/hypr/hyprland.conf
EOF

# Final Steps
umount -R /mnt
echo "Installation complete! Rebooting now."
reboot
