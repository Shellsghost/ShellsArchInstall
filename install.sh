#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# ⚙️ CONFIGURATION & TARGET INITIALIZATION
# ==========================================
TARGET_DISK="/dev/nvme1n1" 
WIFI_SSID="Eorzea"
WIFI_PASSWORD="#Barbi30scar"

SYSTEM_USER="anthony"
USER_PASS="#HappyMeal123!@#"
ROOT_PASS="^YHN6yhn&UJM7ujm"
LUKS_PASS="^YHN6yhn&UJM7ujm"

PROTON_USER="Shellsghost"
PROTON_PASS="ES^vGh7JN56)qx-"

echo "=== [1/7] Initializing Hardware, Drive Targets, and Wi-Fi Handshakes ==="

mkdir -p /tmp/net_config
cat <<EOF > /tmp/net_config/"${WIFI_SSID}.nmconnection"
[connection]
id=${WIFI_SSID}
type=wifi
interface-name=wlan0

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
EOF

iwctl station wlan0 connect "${WIFI_SSID}" --passphrase "${WIFI_PASSWORD}" || true

COUNT=0
until ping -c 1 1.1.1.1 > /dev/null 2>&1 || [ $COUNT -eq 15 ]; do
    echo "Waiting for network handshake..."
    sleep 2
    ((COUNT++))
done

echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
ping -c 3 archlinux.org > /dev/null && echo "✔ Network Verification Successful"

# ==========================================
# 🗺️ AUTOMATED STORAGE SLICING & LUKS ENCRYPTION
# ==========================================
echo "=== [2/7] Slicing Drive & Formatting LUKS Encrypted Volumes ==="
sgdisk -Z "${TARGET_DISK}"
sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:"SHARED_ESP"        "${TARGET_DISK}"
sgdisk -n 2:0:+500G -t 2:8300 -c 2:"ARCH_SWAY"         "${TARGET_DISK}"
sgdisk -n 3:0:+400G -t 3:8300 -c 3:"BLACKARCH_HARDENED" "${TARGET_DISK}"
sgdisk -n 4:0:+25G  -t 4:0700 -c 4:"SHARED_BACKUPS"    "${TARGET_DISK}"

# Format Unencrypted ESP Partition
mkfs.vfat -F 32 "${TARGET_DISK}p1"

# Encrypt Partitions with LUKS
echo -n "${LUKS_PASS}" | cryptsetup luksFormat "${TARGET_DISK}p2" -
echo -n "${LUKS_PASS}" | cryptsetup luksFormat "${TARGET_DISK}p3" -
echo -n "${LUKS_PASS}" | cryptsetup luksFormat "${TARGET_DISK}p4" -

# Open LUKS Containers
echo -n "${LUKS_PASS}" | cryptsetup open "${TARGET_DISK}p2" cryptarch -
echo -n "${LUKS_PASS}" | cryptsetup open "${TARGET_DISK}p3" cryptblack -
echo -n "${LUKS_PASS}" | cryptsetup open "${TARGET_DISK}p4" cryptshared -

# Format File Systems inside LUKS Mappers
mkfs.ext4 -F /dev/mapper/cryptarch
mkfs.ext4 -F /dev/mapper/cryptblack
mkfs.exfat /dev/mapper/cryptshared

# ==========================================
# 🍏 PARTITION A: BASELINE ARCH + SWAY / QUICKSHELL
# ==========================================
echo "=== [3/7] Bootstrapping Partition A: Arch Linux (Standard Kernel + AMD APU) ==="
mount /dev/mapper/cryptarch /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

pacstrap -K /mnt base linux linux-headers linux-firmware amd-ucode networkmanager exfatprogs \
    sudo mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver sway swaybg foot wofi waybar \
    pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack xorg-xwayland wl-clipboard \
    qt6-declarative qt6-5compat qt6-svg git base-devel expect efibootmgr bluez bluez-utils blueman cups cups-pdf \
    thunar gvfs tumbler unzip file-roller clamav rkhunter nano htop \
    openvpn nmap wireshark-cli tcpdump net-tools bind iproute2

genfstab -U /mnt >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

# Inject LUKS hooks into mkinitcpio
sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

arch-chroot /mnt /usr/bin/bash <<EOF
mkinitcpio -P
systemctl enable NetworkManager bluetooth cups systemd-timesyncd
echo "arch-study" > /etc/hostname

# Set Root Password
echo "root:${ROOT_PASS}" | chpasswd

# Create User and Set Password
useradd -m -G wheel,lp,scanner,video,audio,wireshark -s /bin/bash ${SYSTEM_USER}
echo "${SYSTEM_USER}:${USER_PASS}" | chpasswd
echo "${SYSTEM_USER} ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${SYSTEM_USER}
EOF
umount -R /mnt

# ==========================================
# 🛡️ PARTITION B: BLACKARCH HARDENED (Dedicated SOC Workstation)
# ==========================================
echo "=== [4/7] Bootstrapping Partition B: BlackArch (Hardened Kernel + NVIDIA Compute) ==="
mount /dev/mapper/cryptblack /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

pacstrap -K /mnt base linux-hardened linux-hardened-headers linux-firmware amd-ucode networkmanager exfatprogs \
    sudo mesa git base-devel expect nvidia-dkms nvidia-utils efibootmgr bluez bluez-utils blueman cups cups-pdf \
    pipewire wireplumber pipewire-pulse nano htop openvpn nmap wireshark-cli tcpdump

genfstab -U /mnt >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

arch-chroot /mnt /usr/bin/bash <<EOF
mkinitcpio -P
systemctl enable NetworkManager bluetooth cups systemd-timesyncd
echo "blackarch-soc" > /etc/hostname

# Set Root Password
echo "root:${ROOT_PASS}" | chpasswd

# Create User and Set Password
useradd -m -G wheel,lp,scanner,video,audio,wireshark -s /bin/bash ${SYSTEM_USER}
echo "${SYSTEM_USER}:${USER_PASS}" | chpasswd
echo "${SYSTEM_USER} ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${SYSTEM_USER}

curl -O https://blackarch.org/strap.sh
chmod +x strap.sh && ./strap.sh
EOF

# Copy BlackArch Hardened Kernel and Initramfs to EFI partition
cp /mnt/boot/vmlinuz-linux-hardened /mnt/efi/
cp /mnt/boot/initramfs-linux-hardened.img /mnt/efi/
umount -R /mnt

# ==========================================
# 📑 MULTI-BOOT MANAGER ARCHITECTURE
# ==========================================
echo "=== [5/7] Generating systemd-boot & Registering NVRAM Entries ==="
mount /dev/mapper/cryptarch /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi

# Copy Standard Kernel and Initramfs to EFI partition
cp /mnt/boot/vmlinuz-linux /mnt/efi/
cp /mnt/boot/initramfs-linux.img /mnt/efi/
cp /mnt/boot/amd-ucode.img /mnt/efi/

arch-chroot /mnt bootctl install --esp-path=/efi

# Fallback EFI binary for MSI B650 Board Detection
mkdir -p /mnt/efi/EFI/BOOT
cp /mnt/efi/EFI/systemd/systemd-bootx64.efi /mnt/efi/EFI/BOOT/BOOTX64.EFI

# Clean out residual GRUB binaries
rm -rf /mnt/efi/EFI/grub /mnt/efi/EFI/boot/grub* /mnt/efi/grub 2>/dev/null || true

# Configure systemd-boot Loader Defaults
mkdir -p /mnt/efi/loader/entries
cat <<EOF > /mnt/efi/loader/loader.conf
default 10-arch.conf
timeout 10
console-mode max
editor no
EOF

# Entry 1: Arch Linux (Standard Kernel + Sway on Radeon 780M)
cat <<EOF > /mnt/efi/loader/entries/10-arch.conf
title   Arch Linux (Study + Sway)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options cryptdevice=${TARGET_DISK}p2:cryptarch root=/dev/mapper/cryptarch rw amdgpu.ppfeaturemask=0xffffffff
EOF

# Entry 2: BlackArch Hardened SOC Workstation
cat <<EOF > /mnt/efi/loader/entries/20-blackarch.conf
title   BlackArch (Hardened SOC)
linux   /vmlinuz-linux-hardened
initrd  /amd-ucode.img
initrd  /initramfs-linux-hardened.img
options cryptdevice=${TARGET_DISK}p3:cryptblack root=/dev/mapper/cryptblack rw
EOF

# Copy Windows Boot Manager if present on Drive 0
mkdir -p /mnt/win_efi
if mount /dev/nvme0n1p1 /mnt/win_efi 2>/dev/null; then
    cp -r /mnt/win_efi/EFI/Microsoft /mnt/efi/EFI/ 2>/dev/null || true
    umount /mnt/win_efi
fi

umount -R /mnt

# ==========================================
# 🔄 AUTOMATED BACKGROUND SYSTEM UPDATES
# ==========================================
echo "=== [6/7] Injecting Automated Maintenance Upkeep Scripts ==="

write_auto_update() {
    cat <<EOF > "$1/etc/systemd/system/auto-update.service"
[Unit]
Description=Automated System Package Sync Lifecycle
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syu --noconfirm
EOF

    cat <<EOF > "$1/etc/systemd/system/auto-update.timer"
[Unit]
Description=Run automated system updates daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

mount /dev/mapper/cryptarch /mnt
write_auto_update /mnt
arch-chroot /mnt systemctl enable auto-update.timer
umount -R /mnt

mount /dev/mapper/cryptblack /mnt
write_auto_update /mnt
arch-chroot /mnt systemctl enable auto-update.timer
umount -R /mnt

# ==========================================
# 🌐 FIRST-BOOT CONFIGURATION & APPLICATION HOOKS
# ==========================================
echo "=== [7/7] Generating User Configurations, Waybar, and Desktop Deployers ==="

mount /dev/mapper/cryptarch /mnt

# Auto-start Sway on TTY1
cat <<'EOF' > /mnt/home/${SYSTEM_USER}/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec sway
fi
EOF

# Useful Aliases & Environmental Shortcuts
cat <<'EOF' > /mnt/home/${SYSTEM_USER}/.bashrc
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
alias vpnup='protonvpn connect -sc'
alias htb='sudo openvpn ~/htb.ovpn'
export LINUX_DRIVE="/dev/nvme1n1"
export WIN_DRIVE="/dev/nvme0n1"
alias drives='lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS -p | grep -E -v "loop|rom"'
EOF

# Production-ready Sway configuration
mkdir -p /mnt/home/${SYSTEM_USER}/.config/sway
cat <<'SWAYEOF' > /mnt/home/${SYSTEM_USER}/.config/sway/config
set $mod Mod4
set $term foot
set $menu wofi --show drun

output * bg #1e1e2e solid_color

# Keybindings
bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+q kill
bindsym $mod+Shift+e exit
bindsym $mod+Shift+c reload

# Navigation
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4

bar {
    swaybar_command waybar
}

include /etc/sway/config.d/*
SWAYEOF

# Waybar Configuration with Proton VPN and Metric Hooks
mkdir -p /mnt/home/${SYSTEM_USER}/.config/waybar
cat << 'EOF' > /mnt/home/${SYSTEM_USER}/.config/waybar/config
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["sway/workspaces", "sway/window"],
    "modules-right": ["custom/vpn", "custom/gpu", "cpu", "memory", "pulseaudio", "clock"],
    "cpu": {
        "format": "💻 CPU: {usage}%",
        "interval": 2
    },
    "memory": {
        "format": "🧠 RAM: {}%",
        "interval": 2
    },
    "custom/gpu": {
        "exec": "echo \"🎮 GPU: $(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n 1)%\"",
        "interval": 2
    },
    "custom/vpn": {
        "exec": "VPN=$(protonvpn status 2>/dev/null | grep -i 'connected to' | awk '{print $3}'); if [ -n \"$VPN\" ]; then echo \"🔒 $VPN\"; else echo \"🔓 Disconnected\"; fi",
        "interval": 5
    },
    "pulseaudio": {
        "format": "🔊 {volume}%",
        "format-muted": "🔇 Muted"
    },
    "clock": {
        "format": "🕒 {:%Y-%m-%d %H:%M}"
    }
}
EOF

# Waybar clean styling
cat << 'EOF' > /mnt/home/${SYSTEM_USER}/.config/waybar/style.css
* {
    font-family: "Noto Sans", "Noto Color Emoji", sans-serif;
    font-size: 11px;
    border: none;
    border-radius: 0;
}
window#waybar {
    background-color: #1e1e2e;
    color: #cdd6f4;
}
#workspaces button {
    padding: 0 8px;
    color: #cdd6f4;
}
#workspaces button.focused {
    background-color: #2BC3D4;
    color: #1e1e2e;
    font-weight: bold;
}
#custom-vpn, #custom-gpu, #cpu, #memory, #pulseaudio, #clock {
    padding: 0 6px;
    margin: 3px 2px;
    background-color: #313244;
    border-radius: 4px;
    color: #2BC3D4;
}
EOF

# Automated Proton VPN User Service Setup
mkdir -p /mnt/home/${SYSTEM_USER}/.config/systemd/user
cat << 'EOF' > /mnt/home/${SYSTEM_USER}/.config/systemd/user/protonvpn-boot.service
[Unit]
Description=ProtonVPN Secure Core Automated Startup Connection
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="HOME=/home/anthony"
ExecStart=/usr/bin/protonvpn connect -sc

[Install]
WantedBy=default.target
EOF

# Post-install desktop app build script (Yay, Zen Browser, ProtonVPN-CLI, QuickShell)
cat <<EOF > /mnt/home/${SYSTEM_USER}/desktop-apps-setup.sh
#!/usr/bin/env bash
set -e
echo "Building AUR infrastructure and application stack..."
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm

# Install browser, Proton VPN CLI, and QuickShell/Caelestia dependencies
yay -S --noconfirm zen-browser-bin proton-vpn-cli quickshell-git

# Enable user services
systemctl --user daemon-reload
systemctl --user enable --now protonvpn-boot.service

echo "✔ Desktop application setup completed."
EOF

chmod +x /mnt/home/${SYSTEM_USER}/desktop-apps-setup.sh
chown -R 1000:1000 /mnt/home/${SYSTEM_USER}/
umount -R /mnt

# Close LUKS containers
cryptsetup close cryptarch
cryptsetup close cryptblack
cryptsetup close cryptshared
echo "✔ Clean installation complete. System ready to reboot."
