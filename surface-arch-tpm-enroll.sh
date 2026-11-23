#!/usr/bin/env bash
# Add TPM2 unlock plus a recovery key to an already booted, Secure-Boot system.
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run with sudo."
[[ -f /etc/arch-release ]] || die "Run from the installed Arch system, not the live ISO."
command -v bootctl >/dev/null && command -v systemd-cryptenroll >/dev/null && command -v cryptsetup >/dev/null || die "bootctl, systemd-cryptenroll, and cryptsetup are required."

boot_status=$(bootctl status --no-pager 2>&1 || true)
grep -qi 'Secure Boot: enabled' <<<"$boot_status" || die "Secure Boot must be enabled before binding TPM unlock to PCR 7."

root_source=$(findmnt -n -o SOURCE / | sed 's/\[.*$//')
[[ "$root_source" == /dev/mapper/* ]] || die "Root is not mounted from a LUKS mapper device."
mapper=${root_source##*/}
luks_device=$(cryptsetup status "$mapper" | awk '$1 == "device:" {print $2; exit}')
[[ -n "$luks_device" ]] || die "Could not find the physical LUKS device for $root_source."
cryptsetup isLuks --type luks2 "$luks_device" || die "$luks_device is not a LUKS2 device."

cat <<EOF
Target encrypted device: $luks_device
Secure Boot is enabled. This adds two new LUKS credentials using empty slots:
  1. A printable recovery key (save it somewhere separate from this laptop).
  2. A TPM2 unlock credential bound to PCR 7 (Secure Boot state).

It does not remove or replace your existing passphrase or keyslots.
EOF
read -r -p "Type ENROLL TPM to continue: " answer
[[ "$answer" == "ENROLL TPM" ]] || { echo "Cancelled; no keyslots changed."; exit 0; }

systemd-cryptenroll --recovery-key --wipe-slot=empty "$luks_device"
echo
read -r -p "Have you recorded the recovery key above? Type RECORDED to continue: " answer
[[ "$answer" == RECORDED ]] || die "Stop here and store the recovery key before proceeding."
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=empty "$luks_device"

cmdline=/etc/kernel/cmdline
[[ -f "$cmdline" ]] || die "$cmdline is missing; no TPM boot parameter was added."
[[ -f /etc/mkinitcpio.conf ]] || die "/etc/mkinitcpio.conf is missing."
grep -q 'sd-encrypt' /etc/mkinitcpio.conf || die "The initramfs does not include sd-encrypt; stop before enabling TPM auto-unlock."
luks_uuid=$(cryptsetup luksUUID "$luks_device")
if ! grep -Fq "rd.luks.options=$luks_uuid=tpm2-device=auto" "$cmdline"; then
  cp -a "$cmdline" "$cmdline.before-tpm"
  sed -i -E 's/[[:space:]]+$//' "$cmdline"
  printf ' rd.luks.options=%s=tpm2-device=auto,tpm2-measure-pcr=yes' "$luks_uuid" >> "$cmdline"
elif ! grep -Fq 'tpm2-measure-pcr=yes' "$cmdline"; then
  cp -a "$cmdline" "$cmdline.before-tpm"
  sed -i -E 's/[[:space:]]+$//' "$cmdline"
  sed -i "s/rd.luks.options=${luks_uuid}=tpm2-device=auto/rd.luks.options=${luks_uuid}=tpm2-device=auto,tpm2-measure-pcr=yes/" "$cmdline"
fi

mkinitcpio -P
if command -v sbctl >/dev/null; then
  shopt -s nullglob
  uki_files=(/efi/EFI/Linux/*.efi)
  (( ${#uki_files[@]} > 0 )) || die "No UKIs found at /efi/EFI/Linux; TPM enrollment succeeded, but the UKI rebuild/sign step needs repair."
  for f in "${uki_files[@]}"; do sbctl sign --save "$f"; done
  shopt -u nullglob
fi

cat <<'EOF'

TPM enrollment completed. Reboot once and confirm automatic unlock works.
Keep the recovery key and LUKS passphrase safe; firmware or Secure Boot
changes can make TPM unlock unavailable while the passphrase remains usable.
EOF
