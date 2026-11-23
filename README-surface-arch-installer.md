# Surface Laptop 3 ArchISO installer

This toolkit runs from the stock Arch Linux ISO. It does not rebuild or modify
the ISO. The launcher opens Archinstall's TUI; the post-install scripts apply
Surface-specific packages and then enroll TPM unlock after Secure Boot is
enabled. The bundle is stored on the separate `ARCHISO_EFI` FAT partition of
the same boot USB.

## Full installation guide

For the complete step-by-step procedure and commands, see [SURFACE-ARCH-INSTALLATION-GUIDE.md](SURFACE-ARCH-INSTALLATION-GUIDE.md).

## Start from the live USB

The boot USB has an ISO9660 partition (`ARCH_202611`) and a separate FAT
partition (`ARCHISO_EFI`). No second USB is needed; the ISO9660 partition stays
untouched.

From the ArchISO live shell, identify and mount the FAT partition:

```bash
lsblk -f
mkdir -p /mnt/archiso-efi
mount /dev/disk/by-label/ARCHISO_EFI /mnt/archiso-efi
tar -xzf /mnt/archiso-efi/surface-arch-usb-bundle.tar.gz -C /root
bash /root/surface-archiso-installer.sh
```

The launcher sets the live console to UK, checks internet access, and offers
`iwctl` if Wi-Fi needs configuration. It opens the official Archinstall TUI.
Choose the KDE Plasma profile and `plasma-meta` flavor (Archinstall currently
marks it as recommended), with Plasma Login Manager. Create the regular account
`zahinprithi` there (the post-install step ensures it exists and asks for its
password). Follow the Surface profile checklist.
Archinstall handles disk selection, partitioning, formatting, encryption, and
the base installation; review its erase plan before confirming.

## Finish the installation

After first boot into the installed system, mount the `ARCHISO_EFI` partition
again if needed, extract the archive, and run:

```bash
sudo bash /path/to/surface-arch-postinstall.sh
```

This installs linux-surface alongside Arch's standard kernel, configures UK
locale/keymap and encrypted-root initramfs hooks, creates signed UKIs, and
enables NetworkManager, Bluetooth, audio, firmware updates, power profiles,
and zram. It asks which optional apps to install, accepts extra official Arch
package names, and offers Gaze facial authentication with KDE integration. KDE Plasma is the
default desktop profile with `plasma-meta`. Firefox is included as the default
browser. It does not enroll firmware keys or change LUKS slots.

`kernel-surface-modules-extra` is not currently published in the configured
Arch repositories; the script checks for it and reports that. It is a Fedora
package name. After installation, `modinfo xpad` can show whether the Surface
kernel provides the gamepad driver. Gaze facial authentication needs working
camera/TPM support and a separate post-reboot face enrollment; keep password
authentication enabled as a fallback. When Gaze is installed, the post-install
script sets `[cameras] ir = "/dev/video2"` and
`parallel_capture = "auto"` in `/etc/gaze/config.toml`, then restarts Gaze.
Confirm `/dev/video2` is the Surface IR camera on the installed system; video
node numbering can differ.

If firmware is not in Setup Mode, use its menu to enter Setup Mode. Then run:

```bash
sudo bash /path/to/surface-arch-secureboot-enroll.sh
```

This checks Setup Mode and asks before changing firmware keys. Keep Secure Boot
disabled until enrollment is complete; then enable it in UEFI and boot the
signed UKI.

After confirming Secure Boot is enabled and the installed system boots, add
TPM unlock and a recovery key:

```bash
sudo bash /path/to/surface-arch-tpm-enroll.sh
```

The TPM script uses empty LUKS slots, asks you to record the recovery key, and
leaves the passphrase slot intact.
