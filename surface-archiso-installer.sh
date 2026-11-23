#!/usr/bin/env bash
# Surface Laptop 3 live-ISO launcher. It preloads the Surface profile into
# Archinstall's TUI; it does not change or rebuild the ISO. Device configuration
# is applied afterward by surface-arch-postinstall.sh.
set -Eeuo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Surface Laptop 3 ArchISO installer launcher

Run this from the stock Arch Linux ISO on the Surface Laptop 3. It sets the
live console to UK, preloads the Surface-specific Archinstall choices, and
opens Archinstall's guided TUI. Disk layout, encryption, and passwords remain
interactive. After Archinstall completes and you boot the new installation,
run surface-arch-postinstall.sh from this USB.

This launcher does not write to the ISO or install the OS itself. Archinstall
will partition/format the disk only after you select the device and confirm its
erase plan in its TUI.
EOF
  exit 0
fi

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n%s\n' "$*"; }

(( EUID == 0 )) || die "Run as root from the Arch ISO live shell."
[[ -f /etc/arch-release && -d /run/archiso ]] || die "This must run from the stock Arch ISO live environment."
[[ -d /sys/firmware/efi ]] || die "Boot the USB in UEFI mode."
command -v archinstall >/dev/null || die "archinstall is not present. Boot the current official Arch ISO."
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/surface-archinstall-config.json"
[[ -r "$CONFIG_FILE" ]] || die "Missing Archinstall profile: $CONFIG_FILE. Extract the complete USB bundle and rerun this launcher."

MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
CPU_VENDOR=$(awk -F: '/vendor_id/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' /proc/cpuinfo)
[[ "$MODEL" == "Surface Laptop 3" && "$CPU_VENDOR" == "GenuineIntel" ]] || {
  printf 'Detected model: %s; CPU: %s\n' "${MODEL:-unknown}" "${CPU_VENDOR:-unknown}"
  read -r -p "This is not the expected Intel Surface Laptop 3. Continue anyway? Type CONTINUE: " answer
  [[ "$answer" == CONTINUE ]] || exit 1
}

if command -v loadkeys >/dev/null; then
  loadkeys uk || note "Could not load UK keymap in the live environment; use an external keyboard if needed."
fi

ensure_internet() {
  if curl -fsS --connect-timeout 5 https://archlinux.org/ -o /dev/null; then
    note "Internet connection is available."
    return 0
  fi
  cat <<'EOF'
No internet connection detected. Connect Ethernet, or use the wireless
interactive setup below. On ArchISO, enter: station <device> scan, then
station <device> get-networks, then station <device> connect <SSID>.
EOF
  if command -v iwctl >/dev/null; then
    systemctl start iwd.service 2>/dev/null || true
    iwctl || true
  else
    note "iwctl is unavailable. Connect networking manually, then retry this script."
  fi
  curl -fsS --connect-timeout 8 https://archlinux.org/ -o /dev/null || die "Still offline. Connect to the internet and rerun this script; Archinstall needs network access."
  note "Internet connection verified."
}
ensure_internet

note "Surface Laptop 3 installation profile"
echo "Detected storage devices (select carefully in Archinstall):"
lsblk -e7 -d -o PATH,SIZE,MODEL,SERIAL,TRAN,TYPE
cat <<'EOF'

These settings will be prefilled in Archinstall's TUI:

  • Locale: en_GB.UTF-8; keyboard layout: uk.
  • Desktop: KDE Plasma with plasma-meta; Plasma Login Manager.
  • Boot: systemd-boot with Unified Kernel Images; linux fallback kernel.
  • Network: NetworkManager; audio: PipeWire; time zone: Asia/Dhaka.
  • Packages: firefox, sbctl, cryptsetup, mkinitcpio, systemd-ukify,
    tpm2-tss, btrfs-progs, intel-ucode, and sudo.

You must still select the internal drive, choose Btrfs and LUKS, set the EFI
mount point to /efi, and create the regular user zahinprithi in Archinstall.
Review all selected settings and the erase plan before confirming.

Keep your LUKS passphrase. The TPM step adds an unlock method; it does not
replace the passphrase. Secure Boot key enrollment and TPM enrollment happen
after the base install and require separate confirmation.

The stock ISO is not modified. All partition and format actions are performed
by Archinstall on the disk you choose, after its erase confirmation.
EOF

read -r -p "Open Archinstall's guided TUI now? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled; no disk changes made."; exit 0; }

archinstall --config "$CONFIG_FILE" || {
  status=$?
  die "Archinstall exited with status $status. Check /var/log/archinstall/install.log."
}

cat <<'EOF'

Archinstall has finished. Boot the installed system once with Secure Boot
disabled if necessary, then run surface-arch-postinstall.sh from this USB.
That step installs the Surface kernel, configures the UK initramfs keyboard
and encrypted-root hooks, and prepares signed UKIs. It will not enroll
firmware keys or a TPM keyslot without a separate explicit prompt.
EOF
