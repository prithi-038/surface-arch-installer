# Surface Laptop 3 Arch installation guide

This guide uses the **vanilla Arch ISO already on the USB** plus the Surface installer bundle on its writable `ARCHISO_EFI` partition. It does not rebuild or write to the ISO partition. Archinstall remains interactive for disk selection, encryption, passwords, and the final erase confirmation.

## 1. Boot the USB and connect to Wi-Fi

Boot the USB in UEFI mode. At the live shell, set the UK console layout:

```bash
loadkeys uk
```

For Wi-Fi, open iwd:

```bash
iwctl
```

At the `iwctl` prompt, find your device and networks, then connect (replace `wlan0` and the SSID as needed):

```text
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YOUR_WIFI_NAME"
exit
```

Enter the Wi-Fi password if prompted. Test connectivity:

```bash
ping -c 3 archlinux.org
```

If the clock is wrong, sync time before package downloads:

```bash
timedatectl set-ntp true
```

## 2. Load the installer bundle and start Archinstall

Confirm the USB labels and devices before mounting:

```bash
lsblk -f
```

Mount the **small FAT partition labeled `ARCHISO_EFI`**, not the ISO9660 `ARCH_202611` partition:

```bash
mkdir -p /mnt/archiso-efi
mount /dev/disk/by-label/ARCHISO_EFI /mnt/archiso-efi
mkdir -p /root/surface-installer
tar -xzf /mnt/archiso-efi/surface-arch-usb-bundle.tar.gz -C /root/surface-installer
bash /root/surface-installer/surface-archiso-installer.sh
```

The launcher rechecks internet access, sets UK keymap, detects the Surface Laptop 3, and starts Archinstall with the Surface choices prefilled from `surface-archinstall-config.json`. If you start Archinstall directly, use the next section to enter those choices yourself.

## 3. Archinstall choices

The launcher preselects the following settings in Archinstall. Confirm them in its summary before installing:

- **Locale and keyboard:** `en_GB.UTF-8` and `uk`.
- **Desktop:** KDE Plasma with `plasma-meta` and Plasma Login Manager.
- **Boot:** systemd-boot with Unified Kernel Images (UKIs); standard `linux` kernel.
- **Network and audio:** NetworkManager and PipeWire.
- **Time zone:** `Asia/Dhaka`.
- **Additional packages:** `firefox sbctl cryptsetup mkinitcpio systemd-ukify tpm2-tss btrfs-progs intel-ucode sudo`.
- **Disk:** choose the internal NVMe by model and size. Do not select the USB. Inspect the partition/format summary before confirming; installation erases the selected disk.
- **Filesystem/encryption:** choose Btrfs with LUKS encryption for root. Set and keep a strong LUKS passphrase; TPM unlock will be added later as a second method.
- **EFI partition:** mount the EFI System Partition at `/efi`. Ensure it has room for the UKIs.
- **Account:** create user `zahinprithi`; choose a password you can recover. The post-install script creates it if you skip this here.

Complete the install, then reboot into the new Arch system. Leave Secure Boot disabled for the first boot if required. Keep the USB connected.

## 4. Run the Surface post-install setup

In the installed system, open Konsole. Mount the USB’s writable FAT partition, extract the scripts, and run the post-install step:

```bash
sudo mkdir -p /mnt/archiso-efi
sudo mount /dev/disk/by-label/ARCHISO_EFI /mnt/archiso-efi
mkdir -p "$HOME/surface-installer"
tar -xzf /mnt/archiso-efi/surface-arch-usb-bundle.tar.gz -C "$HOME/surface-installer"
sudo bash "$HOME/surface-installer/surface-arch-postinstall.sh"
```

The script updates packages, adds the signed Linux Surface repository, installs the Surface kernel and `iptsd`, configures UK locale and early-boot keyboard, prepares signed UKIs, and enables NetworkManager, Bluetooth, audio, firmware update, power profile, and zram services. It offers optional applications and optional Gaze installation. Firefox is installed as the default browser. Review each prompt and package list.

If installing Gaze, its config is written with these camera defaults:

```toml
[cameras]
ir = "/dev/video2"
parallel_capture = "auto"
```

Gaze’s official guide documents these options. Verify `/dev/video2` is actually the Surface IR camera before relying on face unlock; video node numbers can vary. Check devices with:

```bash
sudo pacman -S --needed v4l-utils
v4l2-ctl --list-devices
ls -l /dev/video*
```

After reboot, sign in as `zahinprithi` and complete enrollment:

```bash
gaze setup
```

Keep password authentication available as a fallback. Gaze is optional and requires a usable TPM, AVX2, and a working camera.

## 5. Enroll Secure Boot keys

First confirm that the Surface firmware is in **Setup Mode**. If necessary, use UEFI settings to clear existing Secure Boot keys / enter Setup Mode. Boot Arch with Secure Boot disabled. Then run:

```bash
sudo bash "$HOME/surface-installer/surface-arch-secureboot-enroll.sh"
```

Read the prompt and type the requested confirmation only when ready. The script enrolls the locally generated sbctl keys plus Microsoft certificates. Then enable Secure Boot in UEFI and boot the signed Surface UKI. Confirm that the system boots before proceeding.

## 6. Add TPM unlock and recovery key

With Secure Boot enabled and Arch booted successfully, run:

```bash
sudo bash "$HOME/surface-installer/surface-arch-tpm-enroll.sh"
```

This adds a printable recovery key and a TPM2 credential in empty LUKS slots. Record the recovery key somewhere separate from the laptop when prompted. It leaves the passphrase slot intact. Reboot once to verify TPM unlock; retain both the recovery key and passphrase.

## 7. Finish and troubleshoot

Unmount the USB when finished:

```bash
sudo umount /mnt/archiso-efi
```

- If touchscreen support is missing, inspect `systemctl status iptsd` and `journalctl -u iptsd --no-pager`.
- For a gamepad, check whether the running Surface kernel has the driver: `modinfo xpad`. `kernel-surface-modules-extra` is not available in the configured Arch repositories checked when this guide was written; that package name is used by Fedora packaging.
- If the Surface IR device is not `/dev/video2`, update `ir` in `/etc/gaze/config.toml` to the correct device and restart Gaze: `sudo systemctl restart gazed`.
- If a step fails, keep Secure Boot disabled until the signed UKI boots, and retain the LUKS passphrase as the unlock fallback.
