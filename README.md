# Surface Laptop 3 Arch Linux installer

Installer scripts and a step-by-step guide for installing Arch Linux on an Intel Surface Laptop 3. The workflow uses the official vanilla Arch ISO and does not rebuild or patch it.

## Download the USB bundle

From the Arch ISO live shell with internet access:

```bash
curl -fL https://github.com/prithi-038/surface-arch-installer/raw/refs/heads/main/surface-arch-usb-bundle.tar.gz -o /tmp/surface-arch-usb-bundle.tar.gz
mkdir -p /root/surface-installer
tar -xzf /tmp/surface-arch-usb-bundle.tar.gz -C /root/surface-installer
bash /root/surface-installer/surface-archiso-installer.sh
```

Review the disk and erase plan in Archinstall before confirming. The post-install, Secure Boot, and TPM enrollment steps are separate scripts and are described in the guide.

## Files

- [Full installation guide](SURFACE-ARCH-INSTALLATION-GUIDE.md)
- [Archinstall prefilled profile](surface-archinstall-config.json)
- [Surface post-install script](surface-arch-postinstall.sh)
- [Secure Boot enrollment](surface-arch-secureboot-enroll.sh)
- [TPM unlock enrollment](surface-arch-tpm-enroll.sh)
- [USB bundle](surface-arch-usb-bundle.tar.gz)
