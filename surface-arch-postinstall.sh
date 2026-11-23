#!/usr/bin/env bash
# Apply Surface Laptop 3 (Intel) preferences to a fresh Arch installation.
# Safe to run from the installed OS or with arch-chroot /mnt /root/... .
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n== %s ==\n' "$*"; }
[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/arch-release ]] || die "This does not look like an installed Arch system."
[[ -f /etc/pacman.conf && -f /etc/mkinitcpio.conf ]] || die "Required Arch configuration files are missing."

MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
CPU_VENDOR=$(awk -F: '/vendor_id/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
if [[ "$MODEL" != "Surface Laptop 3" || "$CPU_VENDOR" != "GenuineIntel" ]]; then
  printf 'Detected model: %s; CPU: %s\n' "${MODEL:-unknown}" "${CPU_VENDOR:-unknown}"
  read -r -p "Continue on this hardware? Type CONTINUE: " answer
  [[ "$answer" == CONTINUE ]] || exit 1
fi

cat <<'EOF'
This step will update Arch packages, add the signed linux-surface repository,
install the Surface kernel and touch support, then offer an app picker and
optional Gaze facial authentication. It will also configure UKIs and early
boot keyboard support. It will not repartition a disk, modify an ISO, enroll
Secure Boot keys, or enroll/wipe a LUKS keyslot.
EOF
read -r -p "Continue with Surface post-install setup? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled; no changes made."; exit 0; }

if ! id zahinprithi >/dev/null 2>&1; then
  echo "Creating the requested regular account: zahinprithi"
  useradd --create-home --groups wheel zahinprithi
  passwd zahinprithi
fi
install -d -m 0750 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

command -v pacman-key >/dev/null || die "pacman-key is required."
command -v pacman >/dev/null || die "pacman is required."
pacman -Syu --needed curl

SURFACE_KEY_ID=56C464BAAC421453
SURFACE_KEY_URL=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
tmp_key=$(mktemp)
trap 'rm -f "$tmp_key"' EXIT
curl --fail --location --silent --show-error "$SURFACE_KEY_URL" -o "$tmp_key"
pacman-key --add "$tmp_key"
fingerprint=$(pacman-key --finger "$SURFACE_KEY_ID" 2>&1 || true)
grep -Fq "$SURFACE_KEY_ID" <<<"$fingerprint" || die "linux-surface signing key fingerprint did not match the published key ID."
pacman-key --lsign-key "$SURFACE_KEY_ID"

if ! grep -q '^\[linux-surface\]$' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF
fi

note "Installing Surface packages and system tools"
pacman -Syu --needed linux-surface linux-surface-headers iptsd intel-ucode firefox xdg-utils sbctl systemd-ukify tpm2-tss cryptsetup mkinitcpio btrfs-progs networkmanager pipewire pipewire-alsa pipewire-pulse wireplumber bluez bluez-utils fwupd power-profiles-daemon zram-generator mesa vulkan-intel intel-media-driver

note "Optional application picker"
app_packages=()
cat <<'EOF'
Firefox is included and will be set as the default browser. Choose optional
applications by entering numbers separated by spaces. You can also type extra
official repository package names, separated by spaces, on the final prompt.
  1) LibreOffice  2) VLC  3) GIMP  4) Steam (enables multilib automatically)
  5) OBS Studio   6) Thunderbird  7) Discord
EOF
read -r -p "Optional apps [none]: " app_choices
for choice in $app_choices; do
  case "$choice" in
    1) app_packages+=(libreoffice-fresh) ;;
    2) app_packages+=(vlc) ;;
    3) app_packages+=(gimp) ;;
    4) app_packages+=(steam) ;;
    5) app_packages+=(obs-studio) ;;
    6) app_packages+=(thunderbird) ;;
    7) app_packages+=(discord) ;;
    *) echo "Ignoring unknown app choice: $choice" ;;
  esac
done
read -r -p "Extra official Arch package names [none]: " extra_packages
if [[ -n "$extra_packages" ]]; then
  read -r -a extra_array <<< "$extra_packages"
  app_packages+=("${extra_array[@]}")
fi
if ((${#app_packages[@]})); then
  if [[ " ${app_packages[*]} " == *" steam "* ]] && ! grep -q '^\[multilib\]$' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]$/,/^#Include = \/etc\/pacman.d\/mirrorlist$/s/^#//' /etc/pacman.conf
    pacman -Sy
  fi
  pacman -S --needed "${app_packages[@]}"
fi

note "Checking optional gamepad module package"
if pacman -Si kernel-surface-modules-extra >/dev/null 2>&1; then
  pacman -S --needed kernel-surface-modules-extra
else
  echo "kernel-surface-modules-extra is not published in the configured Arch repos (it is a Fedora package name)."
  echo "The Arch linux-surface kernel may already include xpad. After boot, check with: modinfo xpad"
fi

note "Optional Gaze facial authentication"
cat <<'EOF'
Gaze supports Arch, stores face data locally, and requires a usable TPM 2.0
for its default setup. It needs a working camera, PipeWire/GStreamer, and AVX2.
Install now? Gaze's official installer will add its own package source and
KDE Plasma integration; face enrollment is finished after reboot.
EOF
read -r -p "Install Gaze? [y/N] " install_gaze
if [[ "$install_gaze" =~ ^[Yy]$ ]]; then
  grep -qw avx2 /proc/cpuinfo || die "Gaze requires AVX2 on x86_64; it was not detected."
  command -v curl >/dev/null || pacman -S --needed curl
  curl -fsSL https://gaze.gundulabs.com/install.sh | sh

  # Gaze's camera options belong under [cameras]. Preserve the rest of its
  # packaged config while making the requested Surface IR defaults explicit.
  python3 - <<'PYCONFIG'
from pathlib import Path
import re

path = Path('/etc/gaze/config.toml')
lines = path.read_text().splitlines() if path.exists() else []
section = None
camera_start = None
camera_end = len(lines)
for index, line in enumerate(lines):
    match = re.match(r'^\s*\[([^]]+)\]\s*(?:#.*)?$', line)
    if match:
        if section == 'cameras' and camera_end == len(lines):
            camera_end = index
        section = match.group(1)
        if section == 'cameras':
            camera_start = index
            camera_end = len(lines)

if camera_start is None:
    if lines and lines[-1].strip():
        lines.append('')
    lines.extend(['[cameras]', 'ir = "/dev/video2"', 'parallel_capture = "auto"'])
else:
    section_lines = lines[camera_start + 1:camera_end]
    settings = {'ir': '"/dev/video2"', 'parallel_capture': '"auto"'}
    for key, value in settings.items():
        pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
        matches = [i for i, line in enumerate(section_lines) if pattern.match(line) and not line.lstrip().startswith('#')]
        if matches:
            first = matches[0]
            section_lines[first] = f'{key} = {value}'
            for duplicate in reversed(matches[1:]):
                del section_lines[duplicate]
        else:
            section_lines.append(f'{key} = {value}')
    lines[camera_start + 1:camera_end] = section_lines

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text('\n'.join(lines).rstrip() + '\n')
PYCONFIG
  chmod 0644 /etc/gaze/config.toml
  systemctl restart gazed.service || echo "Gaze config was written; restart gazed after correcting any service issue."
fi

note "Configuring UK locale and early-boot keyboard"
if [[ -f /etc/locale.gen ]]; then
  sed -i -E 's/^#[[:space:]]*(en_GB\.UTF-8 UTF-8)$/\1/' /etc/locale.gen
  locale-gen
fi
cat > /etc/locale.conf <<'EOF'
LANG=en_GB.UTF-8
EOF
localectl set-keymap uk
localectl set-x11-keymap gb

# Keep the existing mkinitcpio structure but ensure the systemd encrypted-root
# and UK keyboard hooks are present in the required order.
sed -i -E 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
grep -q '^HOOKS=' /etc/mkinitcpio.conf || die "Could not find HOOKS= in /etc/mkinitcpio.conf."

[[ -f /etc/kernel/cmdline ]] || die "Archinstall did not create /etc/kernel/cmdline. Re-run the base install with systemd-boot and UKIs enabled."
grep -Eq '(^|[[:space:]])rd\.luks\.name=' /etc/kernel/cmdline || die "Expected an rd.luks.name= parameter in /etc/kernel/cmdline. Do not rebuild initramfs until the encrypted-root command line is reviewed."
mkdir -p /etc/mkinitcpio.d /efi/EFI/Linux
cat > /etc/mkinitcpio.d/linux.preset <<'EOF'
# Surface profile: signed UKI for the standard Arch fallback kernel.
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="/etc/kernel/cmdline"
EOF
cat > /etc/mkinitcpio.d/linux-surface.preset <<'EOF'
# Surface profile: signed UKI for the linux-surface kernel.
ALL_kver="/boot/vmlinuz-linux-surface"
PRESETS=('default')
default_config="/etc/mkinitcpio-surface.conf"
default_uki="/efi/EFI/Linux/arch-linux-surface.efi"
default_options="/etc/kernel/cmdline"
EOF
cp /etc/mkinitcpio.conf /etc/mkinitcpio-surface.conf
sed -i -E 's/^MODULES=.*/MODULES=(i2c_hid_acpi i2c_hid intel_lpss intel_lpss_pci surface_aggregator surface_aggregator_registry surface_hid_core surface_hid hid_surface)/' /etc/mkinitcpio-surface.conf

note "Preparing signed UKIs"
ESP=/efi
mountpoint -q "$ESP" || die "The EFI system partition must be mounted at /efi. Re-run after correcting the Archinstall mount point."
mkdir -p "$ESP/EFI/Linux"
if [[ ! -d /var/lib/sbctl/keys ]] || ! find /var/lib/sbctl/keys -type f -print -quit 2>/dev/null | grep -q .; then
  sbctl create-keys
fi

bootctl --esp-path="$ESP" install
mkinitcpio -P

shopt -s nullglob
uki_files=("$ESP"/EFI/Linux/*.efi)
(( ${#uki_files[@]} > 0 )) || die "No UKIs were created under $ESP/EFI/Linux. Keep Secure Boot disabled and inspect mkinitcpio output."
for f in "${uki_files[@]}"; do sbctl sign --save "$f"; done
for f in "$ESP/EFI/systemd/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"; do
  [[ -f "$f" ]] && sbctl sign --save "$f"
done
shopt -u nullglob
bootctl --esp-path="$ESP" set-default arch-linux-surface.efi

systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service
desktop_user=${SUDO_USER:-}
if [[ -n "$desktop_user" && "$desktop_user" != root ]] && id "$desktop_user" >/dev/null 2>&1; then
  desktop_home=$(getent passwd "$desktop_user" | cut -d: -f6)
  if [[ -n "$desktop_home" ]]; then
    runuser -u "$desktop_user" -- env HOME="$desktop_home" xdg-settings set default-web-browser firefox.desktop || \
      echo "Firefox is installed; set it as default in GNOME Settings if this command could not reach the user's desktop session."
  fi
else
  gazehome=$(getent passwd zahinprithi | cut -d: -f6 || true)
  if [[ -n "$gazehome" ]]; then
    runuser -u zahinprithi -- env HOME="$gazehome" xdg-settings set default-web-browser firefox.desktop || true
  else
    echo "Could not find user zahinprithi; set Firefox as default in Plasma System Settings."
  fi
fi
if systemctl list-unit-files iptsd@.service >/dev/null 2>&1 && command -v iptsd-systemd >/dev/null; then
  iptsd-systemd -t touchscreen -- systemctl enable --now || echo "Touchscreen daemon was not auto-configured; inspect iptsd devices after reboot."
fi

cat <<'EOF'

Surface post-install setup is complete.

Secure Boot keys were created and UKIs were signed, but firmware keys have not
been enrolled. Keep Secure Boot disabled until keys are enrolled. If firmware
is not in Setup Mode, use its Secure Boot menu to clear keys/enter Setup Mode,
boot this installation, then run surface-arch-secureboot-enroll.sh.

After confirming Secure Boot is enabled and the installed system boots, run
surface-arch-tpm-enroll.sh to add TPM unlock and a recovery key. The LUKS
passphrase remains available as a fallback.

If Gaze was installed, reboot so KDE can load its Gaze integration, then sign in
as zahinprithi and run `gaze setup` (or `gaze add-face default`). Keep password
authentication available as a fallback.
EOF
