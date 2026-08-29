Here is the fully updated `install.sh` script. It incorporates **LUKS encryption** across all root partitions (`p2` and `p3`) and the exFAT shared storage (`p4`), provisions **Bluetooth (`bluez`, `bluez-utils`)** and **Printing services (`cups`, `cups-pdf`)**, and maps your exact username (`anthony`) and passwords across both environments.

### Updates Included

* **Full Drive LUKS Encryption:** Partitions `p2`, `p3`, and `p4` are formatted with `cryptsetup luksFormat` using your root passphrase (`^YHN6yhn&UJM7ujm`) and unlocked into mapper targets (`cryptarch`, `cryptblack`, `cryptshared`).


* **System Credentials:**
* **Username:** `anthony`

* **User Password:** `#HappyMeal123!@#`

* **Root / Encrypted Sudo Password:** `^YHN6yhn&UJM7ujm`



* **Bluetooth & Printing Stack:** Added `bluez`, `bluez-utils`, `blueman`, `cups`, and `cups-pdf` packages into `pacstrap` and enabled `bluetooth.service` and `cups.service` automatically on both OS builds.


* **Bootloader Encryption Hooks:** Updated `mkinitcpio.conf` to load `encrypt` in the ramdisk hooks and configured `systemd-boot` entries (`10-arch.conf` & `20-blackarch.conf`) with `cryptdevice` parameters.



```bash
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
# 🗺️ AUTOMATED STORAGE SLICING & LUKS ENCRYPTION
# ==========================================
echo "=== [2/8] Slicing Drive & Formatting LUKS Encrypted Volumes ==="
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
# 🍏 PARTITION A: BASELINE ARCH + SWAY (Pure AMD Stack + BT/Printing)
# ==========================================
echo "=== [3/8] Bootstrapping Partition A: Arch Linux (Standard Kernel + Pure AMD + LUKS) ==="
mount /dev/mapper/cryptarch /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

pacstrap -K /mnt base linux linux-headers linux-firmware amd-ucode networkmanager exfatprogs sudo mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver sway git base-devel expect efibootmgr bluez bluez-utils blueman cups cups-pdf

genfstab -U /mnt >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

# Inject LUKS hooks into mkinitcpio
sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

arch-chroot /mnt /usr/bin/bash <<EOF
mkinitcpio -P
systemctl enable NetworkManager bluetooth cups
echo "arch-sway" > /etc/hostname

# Set Root Password
echo "root:${ROOT_PASS}" | chpasswd

# Create User and Set Password
useradd -m -G wheel,lp,scanner -s /bin/bash ${SYSTEM_USER}
echo "${SYSTEM_USER}:${USER_PASS}" | chpasswd
echo "${SYSTEM_USER} ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${SYSTEM_USER}
EOF
umount -R /mnt

# ==========================================
# 🛡️ PARTITION B: BLACKARCH HARDENED (Dedicated NVIDIA Stack + BT/Printing)
# ==========================================
echo "=== [4/8] Bootstrapping Partition B: BlackArch (Hardened Kernel + NVIDIA + LUKS) ==="
mount /dev/mapper/cryptblack /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi
mkdir -p /mnt/mnt/SharedData

pacstrap -K /mnt base linux-hardened linux-hardened-headers linux-firmware amd-ucode networkmanager exfatprogs sudo mesa git base-devel expect nvidia-dkms nvidia-utils efibootmgr bluez bluez-utils blueman cups cups-pdf

genfstab -U /mnt >> /mnt/etc/fstab

mkdir -p /mnt/etc/NetworkManager/system-connections/
cp /tmp/net_config/"${WIFI_SSID}.nmconnection" /mnt/etc/NetworkManager/system-connections/
chmod 600 /mnt/etc/NetworkManager/system-connections/"${WIFI_SSID}.nmconnection"

# Inject LUKS hooks into mkinitcpio
sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /mnt/etc/mkinitcpio.conf

arch-chroot /mnt /usr/bin/bash <<EOF
mkinitcpio -P
systemctl enable NetworkManager bluetooth cups
echo "blackarch-hardened" > /etc/hostname

# Set Root Password
echo "root:${ROOT_PASS}" | chpasswd

# Create User and Set Password
useradd -m -G wheel,lp,scanner -s /bin/bash ${SYSTEM_USER}
echo "${SYSTEM_USER}:${USER_PASS}" | chpasswd
echo "${SYSTEM_USER} ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${SYSTEM_USER}

curl -O https://blackarch.org
chmod +x strap.sh && ./strap.sh
EOF
umount -R /mnt

# ==========================================
# 📑 MULTI-BOOT MANAGER ARCHITECTURE
# ==========================================
echo "=== [5/8] Generating systemd-boot & Registering NVRAM Entries ==="
mount /dev/mapper/cryptarch /mnt
mkdir -p /mnt/efi && mount "${TARGET_DISK}p1" /mnt/efi

arch-chroot /mnt bootctl install --esp-path=/efi
arch-chroot /mnt efibootmgr --create --disk "${TARGET_DISK}" --part 1 --label "Linux Boot Manager" --loader "\EFI\systemd\systemd-bootx64.efi" || true

# Config for Partition A (Arch Linux)
cat <<EOF > /mnt/efi/loader/entries/10-arch.conf
title   Arch Linux (Standard + Sway)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options cryptdevice=${TARGET_DISK}p2:cryptarch root=/dev/mapper/cryptarch rw amdgpu.ppfeaturemask=0xffffffff
EOF

# Config for Partition B (BlackArch)
cat <<EOF > /mnt/efi/loader/entries/20-blackarch.conf
title   BlackArch (Hardened Security Kernel)
linux   /vmlinuz-linux-hardened
initrd  /amd-ucode.img
initrd  /initramfs-linux-hardened.img
options cryptdevice=${TARGET_DISK}p3:cryptblack root=/dev/mapper/cryptblack rw nvidia_drm.modeset=1
EOF
umount -R /mnt

# ==========================================
# 🔄 AUTOMATED BACKGROUND SYSTEM UPDATES
# ==========================================
echo "=== [6/8] Injecting Automated Maintenance Upkeep Scripts ==="
mount /dev/mapper/cryptarch /mnt
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

mount /dev/mapper/cryptblack /mnt
cp /mnt/etc/systemd/system/auto-update.* /mnt/etc/systemd/system/ 2>/dev/null || true
arch-chroot /mnt systemctl enable auto-update.timer
umount -R /mnt

# ==========================================
# 🌐 INITIAL FIRST-BOOT APPLICATION HOOKS
# ==========================================
echo "=== [7/8] Generating First-Boot Native Core Deployers ==="

# --- Partition 2 Setup (Arch Sway Environment) ---
mount /dev/mapper/cryptarch /mnt
cat <<EOF > /mnt/home/${SYSTEM_USER}/desktop-apps-setup.sh
#!/usr/bin/env bash
set -e
echo "Building package infrastructure tools..."
cd /tmp
git clone https://archlinux.org && cd yay-bin && makepkg -si --noconfirm
yay -S zen-browser-bin proton-vpn-gnome-desktop --noconfirm

expect -c '
spawn protonvpn-cli login "${PROTON_USER}"
expect "Enter your Proton VPN password:"
send "${PROTON_PASS}\r"
expect eof
'

echo "alias vpnup='sudo protonvpn-cli c --sc'" >> /home/${SYSTEM_USER}/.bashrc

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
echo "✔ Arch Desktop & Secure Core automation successfully linked!"
EOF

mkdir -p /mnt/home/${SYSTEM_USER}/.config/sway
cat <<'SWAYEOF' > /mnt/home/${SYSTEM_USER}/.config/sway/config
assign [app_id="zen"] workspace number 1
exec zen-browser

modifier Mod4
bindsym $modifier+Return exec foot
bindsym $modifier+q kill
bindsym $modifier+d exec menu

bar {
    position top
    status_command while true; do echo "VPN: $(protonvpn-cli s | grep 'Status:' | awk '{print $2}') | $(date +'%H:%M')"; sleep 5; done
}
SWAYEOF

chmod +x /mnt/home/${SYSTEM_USER}/desktop-apps-setup.sh
chown -R 1000:1000 /mnt/home/${SYSTEM_USER}/
umount -R /mnt

# --- Partition 3 Setup (BlackArch Hardened Environment) ---
mount /dev/mapper/cryptblack /mnt
cat <<EOF > /mnt/home/${SYSTEM_USER}/hardened-apps-setup.sh
#!/usr/bin/env bash
set -e
echo "Building environment hooks..."
cd /tmp
git clone https://archlinux.org && cd yay-bin && makepkg -si --noconfirm
sudo pacman -S --noconfirm proton-vpn-cli
yay -S zen-browser-bin --noconfirm

expect -c '
spawn sudo protonvpn-cli login "${PROTON_USER}"
expect "Enter your Proton VPN password:"
send "${PROTON_PASS}\r"
expect eof
'

echo "alias vpnup='sudo protonvpn-cli c --sc'" >> /home/${SYSTEM_USER}/.bashrc

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
echo "✔ BlackArch Hardened environment successfully locked and configured!"
EOF

chmod +x /mnt/home/${SYSTEM_USER}/hardened-apps-setup.sh
chown -R 1000:1000 /mnt/home/${SYSTEM_USER}/
umount -R /mnt

# Close LUKS containers
cryptsetup close cryptarch
cryptsetup close cryptblack
cryptsetup close cryptshared

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

```
