#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# ⚙️ CONFIGURATION & TARGET INITIALIZATION
# ==========================================
TARGET_DISK="/dev/nvme1n1" 
WIFI_SSID="Eorzea"
WIFI_PASSWORD="#Barbi30scar"

echo "=== [1/8] Initializing Hardware, Drive Targets, and Wi-Fi Handshakes ==="

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
sleep 4
ping -c 3 archlinux.org > /dev/null && echo "✔ Local Network Verification Successful"

# ==========================================
# 🗺️ AUTOMATED STORAGE SLICING (With exFAT)
# ==========================================
echo "=== [2/8] Slicing Drive and Carving out Shared exFAT Storage ==="
sgdisk -Z "${TARGET_DISK}"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"SHARED_ESP" "${TARGET_DISK}"
# Allocating 50% for Arch, 35% for BlackArch, remaining ~15% for cross-OS shared storage
sgdisk -n 2:0:+50%FREE -t 2:8300 -c 2:"ARCH_SWAY" "${TARGET_DISK}"
sgdisk -n 3:0:+70%FREE -t 3:8300 -c 3:"BLACKARCH_HARDENED" "${TARGET_DISK}"
sgdisk -n 4:0:+100%FREE -t 4:0700 -c 4:"SHARED_BACKUPS" "${TARGET_DISK}"

mkfs.vfat -F 32 "${TARGET_DISK}p1"
mkfs.ext4 -F "${TARGET_DISK}p2"
mkfs.ext4 -F "${TARGET_DISK}p3"
mkfs.exfat "${TARGET_DISK}p4"

# ==========================================
# 🍏 PARTITION A: BASELINE ARCH + SWAY
# ==========================================
echo "=== [3/8] Bootstrapping Partition A: Arch Linux (Standard Kernel + Sway) ==="
mount "${TARGET_DISK}p2" /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

# Install core, wayland components, and filesystem drivers for exFAT mapping
pacstrap -K /mnt base linux linux-headers linux-firmware amd-ucode networkmanager exfatprogs sudo mesa sway git base-devel

# Save fstab mappings including the shared data disk
genfstab -U /mnt >> /mnt/etc/fstab
SHARED_UUID=$(blkid -s UUID -o value "${TARGET_DISK}p4")
echo "UUID=${SHARED_UUID} /mnt/SharedData exfat defaults,uid=1000,gid=1000,nofail 0 0" >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

arch-chroot /mnt /usr/bin/bash <<EOF
systemctl enable NetworkManager
echo "arch-sway" > /etc/hostname
useradd -m -G wheel -s /bin/bash starlight
echo "starlight ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/starlight
EOF
umount -R /mnt

# ==========================================
# 🛡️ PARTITION B: BLACKARCH HARDENED (No Sway)
# ==========================================
echo "=== [4/8] Bootstrapping Partition B: BlackArch (Hardened Kernel) ==="
mount "${TARGET_DISK}p3" /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

pacstrap -K /mnt base linux-hardened linux-hardened-headers linux-firmware amd-ucode networkmanager exfatprogs sudo mesa git base-devel

genfstab -U /mnt >> /mnt/etc/fstab
echo "UUID=${SHARED_UUID} /mnt/SharedData exfat defaults,uid=1000,gid=1000,nofail 0 0" >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

arch-chroot /mnt /usr/bin/bash <<EOF
systemctl enable NetworkManager
echo "blackarch-hardened" > /etc/hostname
useradd -m -G wheel -s /bin/bash starlight
echo "starlight ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/starlight
curl -O https://blackarch.org
chmod +x strap.sh && ./strap.sh
EOF
umount -R /mnt

# ==========================================
# 📑 MULTI-BOOT MANAGER ARCHITECTURE
# ==========================================
echo "=== [5/8] Generating Unbound systemd-boot Configurations ==="
mount "${TARGET_DISK}p2" /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi

arch-chroot /mnt bootctl install --esp-path=/efi

ARCH_UUID=$(blkid -s UUID -o value "${TARGET_DISK}p2")
BLACK_UUID=$(blkid -s UUID -o value "${TARGET_DISK}p3")

cat <<EOF > /mnt/efi/loader/entries/10-arch.conf
title   Arch Linux (Standard + Sway)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ARCH_UUID} rw nvidia_drm.modeset=1
EOF

cat <<EOF > /mnt/efi/loader/entries/20-blackarch.conf
title   BlackArch (Hardened Security Kernel)
linux   /vmlinuz-linux-hardened
initrd  /amd-ucode.img
initrd  /initramfs-linux-hardened.img
options root=UUID=${BLACK_UUID} rw nvidia_drm.modeset=1
EOF
umount -R /mnt

# ==========================================
# 🔄 AUTOMATED BACKGROUND SYSTEM UPDATES
# ==========================================
echo "=== [6/8] Injecting Automated Maintenance Upkeep Scripts ==="
for PART in "${TARGET_DISK}p2" "${TARGET_DISK}p3"; do
    mount "${PART}" /mnt
    cat <<EOF > /mnt/etc/systemd/system/auto-update.service
[Unit]
Description=Automated System Package Sync Lifecycle
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syu --noconfirm
EOF

    cat <<EOF > /mnt/etc/systemd/system/auto-update.timer
[Unit]
Description=Run automated system updates daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    arch-chroot /mnt systemctl enable auto-update.timer
    umount -R /mnt
done

# ==========================================
# 🌐 INITIAL FIRST-BOOT APPLICATION HOOKS
# ==========================================
echo "=== [7/8] Generating First-Boot Native Core Deployers with VPN Systemd Automation ==="

# --- Partition 2 Setup (Arch Sway) ---
mount "${TARGET_DISK}p2" /mnt
cat <<'EOF' > /mnt/home/starlight/desktop-apps-setup.sh
#!/usr/bin/env bash
set -e
echo "Building package infrastructure tools..."
cd /tmp
git clone https://archlinux.org && cd yay-bin && makepkg -si --noconfirm
yay -S zen-browser-bin proton-vpn-gnome-desktop --noconfirm

# Inject automation shell aliases
echo "alias vpnup='sudo protonvpn-cli c --sc'" >> /home/starlight/.bashrc

# Set up automated systemd startup profiles for ProtonVPN Secure Core
sudo tee /etc/systemd/system/protonvpn-boot.service > /dev/null <<SERVICEEOF
[Unit]
Description=ProtonVPN Secure Core Automated Startup Connection
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/protonvpn-cli c --sc
ExecStartPost=/usr/bin/protonvpn-cli ks --on

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl enable protonvpn-boot.service

echo "✔ Arch Desktop Apps & Secure Core Automation configured!"
echo "NOTE: Remember to run 'protonvpn-cli login <username>' first upon booting into your desktop."
EOF

# Inject basic Sway custom indicator wrapper config into User home directory
mkdir -p /mnt/home/starlight/.config/sway
cat <<'SWAYEOF' > /mnt/home/starlight/.config/sway/config
# Mapped auto-launch rules for Zen Browser
assign [app_id="zen"] workspace number 1
exec zen-browser

# Custom baseline keybinds
modifier Mod4
bindsym $modifier+Return exec foot
bindsym $modifier+q kill
bindsym $modifier+d exec menu

# Status Bar mapping displaying active VPN routing states
bar {
    position top
    status_command while true; do echo "VPN Status: $(protonvpn-cli s | grep 'Status:' | awk '{print $2}') | $(date +'%Y-%m-%d %H:%M')"; sleep 5; done
}
SWAYEOF

chmod +x /mnt/home/starlight/desktop-apps-setup.sh
chown -R 1000:1000 /mnt/home/starlight/
umount -R /mnt

# --- Partition 3 Setup (BlackArch Hardened CLI) ---
mount "${TARGET_DISK}p3" /mnt
cat <<'EOF' > /mnt/home/starlight/hardened-apps-setup.sh
#!/usr/bin/env bash
set -e
echo "Building environment hooks..."
cd /tmp
git clone https://archlinux.org && cd yay-bin && makepkg -si --noconfirm
sudo pacman -S --noconfirm proton-vpn-cli
yay -S zen-browser-bin --noconfirm

echo "alias vpnup='sudo protonvpn-cli c --sc'" >> /home/starlight/.bashrc

sudo tee /etc/systemd/system/protonvpn-boot.service > /dev/null <<SERVICEEOF
[Unit]
Description=ProtonVPN Secure Core Hardened Boot Connection
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/protonvpn-cli c --sc
ExecStartPost=/usr/bin/protonvpn-cli ks --on

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl enable protonvpn-boot.service

echo "✔ Hardened Security Environment Setup Completed Successfully!"
echo "NOTE: Remember to run 'sudo protonvpn-cli login <username>' first upon booting."
EOF

chmod +x /mnt/home/starlight/hardened-apps-setup.sh
chown -R 1000:1000 /mnt/home/starlight/
umount -R /mnt

# ==========================================
# 🧼 HARDWARE CLEANUP & REPURPOSING
# ==========================================
echo "=== [8/8] Erasing and Formatting Live Installation USB ==="
USB_DEV=$(lsblk -dno NAME,TYPE | awk '$2=="disk" && $1!~/nvme/ {print "/dev/"$1}')
if [ -n "${USB_DEV}" ]; then
    umount "${USB_DEV}"* 2>/dev/null || true
    sgdisk -Z "${USB_DEV}"
    sgdisk -n 1:0:0 -t 1:0700 -c 1:"USB_STORAGE" "${USB_DEV}"
    mkfs.vfat -F 32 "${USB_DEV}1"
    echo "✔ Installation USB formatted to clean FAT32 storage"
fi

echo "🎉 DEPLOYMENT COMPLETE! REBOOT YOUR COMPUTER NOW."
