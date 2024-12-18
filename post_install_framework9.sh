#!/bin/bash

# Framework 13 Post-Installation Script for Arch Linux
# Hyprland Desktop Environment
# By: ChatGPT

set -e

# --- Function for Error Handling ---
function error_exit() {
    echo "Error on line $1"
    exit 1
}
trap 'error_exit $LINENO' ERR

# --- Update System & Install Base Dependencies ---
echo "[INFO] Updating the system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm base-devel git wget curl zsh unzip tar

# --- Install yay (AUR Helper) ---
if ! command -v yay &>/dev/null; then
    echo "[INFO] Installing yay..."
    git clone https://aur.archlinux.org/yay.git ~/yay
    cd ~/yay
    makepkg -si --noconfirm
    cd ~
    rm -rf ~/yay
fi

# --- Install Packages ---
echo "[INFO] Installing essential packages..."
yay -S --noconfirm hyprland waybar alacritty rofi zsh neofetch \
    thunar gimp libreoffice-fresh evince gparted spotify-launcher ttf-jetbrains-mono-nerd \
    docker docker-compose dropbox-edge-bin firefox microsoft-edge-stable-bin parsec-bin \
    thunderbird zulip discord btop hyprlock tlp python python-pip miniconda \
    gcc clang cmake make ninja gdb valgrind sddm-sugar-dark cups system-config-printer mako \
    adwaita-qt6 adwaita-qt5 qt5ct qt6ct noto-fonts noto-fonts-cjk noto-fonts-emoji

# --- Fixing Fonts for Waybar ---
echo "[INFO] Installing fonts for Waybar and other icons..."
yay -S --noconfirm ttf-font-awesome nerd-fonts-complete noto-fonts-emoji

# --- Configure Battery Optimization with TLP ---
echo "[INFO] Configuring TLP for battery optimization..."
sudo systemctl enable --now tlp
sudo tlp start
echo "[INFO] TLP has been enabled."

# --- Printing Support ---
echo "[INFO] Configuring printing support..."
sudo systemctl enable --now cups.socket
sudo usermod -aG sys,lp "$(whoami)"

# --- Fix hyprland-session.service Path Issue ---
echo "[INFO] Fixing hyprland-session.service path..."
sudo sed -i 's#ExecStart=/usr//usr/bin/Hyprland#ExecStart=/usr/bin/Hyprland#' /usr/lib/systemd/user/hyprland-session.service
systemctl --user daemon-reload

# --- Configure Hyprland ---
echo "[INFO] Configuring Hyprland..."
mkdir -p ~/.config/hypr
cat <<EOF > ~/.config/hypr/hyprland.conf
# Monitor Configuration
monitor=*,preferred,auto,1

# Autostart Applications
exec-once = waybar &
exec-once = mako &
exec-once = nm-applet &
exec-once = blueman-applet &

# General Options
vfr = 1
sensitivity = 1.0

# Workspace Rules
workspace = 1
workspace = 2
bind = SUPER+1, workspace, 1
bind = SUPER+2, workspace, 2

# Window Management
focus = mouse
EOF

# --- Configure Waybar ---
echo "[INFO] Configuring Waybar..."
mkdir -p ~/.config/waybar
cat <<EOF > ~/.config/waybar/config.json
{
  "layer": "top",
  "position": "top",
  "modules-left": ["hyprland/workspaces", "hyprland/window"],
  "modules-center": ["clock"],
  "modules-right": ["battery", "cpu", "memory", "network", "pulseaudio", "tray"],
  "clock": {
    "format": "{:%Y-%m-%d %H:%M:%S}"
  }
}
EOF

cat <<EOF > ~/.config/waybar/style.css
* {
    font-family: "JetBrains Mono Nerd Font", sans-serif;
    font-size: 14px;
}
#waybar {
    background: #282c34;
    color: #ffffff;
}
#clock, #cpu, #memory, #battery, #network, #tray {
    margin: 0 10px;
    padding: 0 5px;
}
EOF

# --- Configure Hyprlock ---
echo "[INFO] Configuring Hyprlock..."
mkdir -p ~/.config/hypr/hyprlock
cat <<EOF > ~/.config/hypr/hyprlock.conf
general {
    hide_cursor = true
    grace = 5
}

background {
    monitor = eDP-1
    path = /usr/share/backgrounds/archlinux/archlinux-simplyblue.png
    color = 0x282c34
}

input-field {
    monitor = eDP-1
    size = 300, 50
    outline_thickness = 2
    dots_size = 0.2
    fade_on_empty = true
    placeholder_text = "Enter password..."
    color = 0xffffff
}
EOF

# --- Rofi Theme Configuration ---
echo "[INFO] Configuring Rofi with a theme..."
mkdir -p ~/.config/rofi
cat <<EOF > ~/.config/rofi/config.rasi
configuration {
    font: "JetBrains Mono Nerd Font 12";
    show-icons: true;
}
EOF

# --- Install & Configure Zsh with Oh-My-Zsh ---
echo "[INFO] Installing and configuring Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
fi

cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc

# --- GTK and Qt Themes ---
echo "[INFO] Configuring Adwaita theme for GTK and Qt..."
gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
echo "export QT_QPA_PLATFORMTHEME=\"qt5ct\"" >> ~/.zshrc
echo "export QT_QPA_PLATFORMTHEME=\"qt6ct\"" >> ~/.zshrc

# --- Notifications (Mako) ---
echo "[INFO] Configuring Mako notification daemon..."
mkdir -p ~/.config/mako
cat <<EOF > ~/.config/mako/config
[general]
background-color=#282c34
text-color=#ffffff
border-color=#5e81ac
border-radius=5
EOF
systemctl --user enable mako.service

# --- Set Zsh as Default Shell ---
echo "[INFO] Setting Zsh as the default shell..."
chsh -s $(which zsh) "$(whoami)"

# --- Final Clean-Up ---
echo "[INFO] Finalizing installation..."
yay -Scc --noconfirm
echo "[INFO] Installation complete! Reboot your system for all changes to take effect."
