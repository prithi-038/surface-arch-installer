#!/usr/bin/env bash
# Enroll locally generated sbctl keys after the firmware is in Setup Mode.
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run with sudo."
[[ -f /etc/arch-release ]] || die "Run from the installed Arch system, not the live ISO."
command -v sbctl >/dev/null || die "sbctl is not installed; run surface-arch-postinstall.sh first."

status=$(sbctl status 2>&1 || true)
printf '%s\n' "$status"
grep -Eq 'Setup Mode:[[:space:]]+✓ Enabled|Setup Mode:[[:space:]]+Enabled' <<<"$status" || die "Firmware is not in Setup Mode. Use UEFI settings to clear Secure Boot keys, then boot Arch with Secure Boot disabled and retry."

cat <<'EOF'

This enrolls the locally generated sbctl keys and Microsoft certificates in
UEFI. It changes firmware trust settings. Secure Boot can remain disabled
until you enable it in UEFI after enrollment.
EOF
read -r -p "Type ENROLL SECURE BOOT KEYS to continue: " answer
[[ "$answer" == "ENROLL SECURE BOOT KEYS" ]] || { echo "Cancelled; firmware keys unchanged."; exit 0; }

sbctl enroll-keys --microsoft
sbctl status
cat <<'EOF'

Now enable Secure Boot in UEFI and boot the signed Surface UKI. After that
boot succeeds, run surface-arch-tpm-enroll.sh to add TPM unlock.
EOF
