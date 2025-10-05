#!/bin/bash
# Simple Arch Linux automated installer (UEFI + GRUB)
# Run as root from Arch ISO

set -e

HOSTNAME="archlinux"

echo "[+] Wiping disk and creating partitions..."
sgdisk -Z "$DISK"  # Zap all partitions
sgdisk -a2048 -o "$DISK"

# Create partitions:
# 1: EFI (512M)
# 2: Root (rest of disk)
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0    -t 2:8300 -c 2:"ROOT" "$DISK"

# Get partition names (NVMe devices use p1/p2 suffix)
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

echo "[+] Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "[+] Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir /mnt/boot
mount "$EFI_PART" /mnt/boot

echo "[+] Installing base system..."
pacstrap /mnt base linux linux-firmware vim networkmanager grub efibootmgr

echo "[+] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "[+] Chrooting into new system..."
arch-chroot /mnt /bin/bash <<EOF

echo "[+] Setting timezone..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "[+] Setting locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "[+] Setting hostname..."
echo "$HOSTNAME" > /etc/hostname
cat <<EOT >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOT

echo "[+] Setting root password..."
echo "root:$PASSWORD" | chpasswd

echo "[+] Creating user..."
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo "[+] Installing and configuring GRUB..."
mkdir -p /boot/efi
mount "$EFI_PART" /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

EOF

echo "[+] Installation complete!"
echo "You can now 'umount -R /mnt' and reboot."
