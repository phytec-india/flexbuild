# PHYTEC Phygate Tauri-L IMX8M Mini: Flexbuild Complete Guide

> **Generate U-Boot, Kernel Image, DTBs, Overlays, Debian Desktop Rootfs, and WIC using Flexbuild for PHYTEC's Phygate Tauri-L IMX8M Mini**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Clone Flexbuild Repository](#clone-flexbuild-repository)
3. [Host Setup](#host-setup)
4. [U-Boot Build](#uboot-build)
5. [Linux Kernel Build](#linux-kernel-build)
6. [Firmware](#firmware)
7. [Boot Partition](#boot-partition)
8. [Root Filesystem (Rootfs)](#root-filesystem-rootfs)
9. [Pack the Rootfs](#pack-the-rootfs)
10. [Generate WIC Image](#generate-wic-image)
11. [Full Build Command Sequence](#full-build-command-sequence)
12. [Conclusion](#conclusion)

---

## Introduction

This guide walks you through generating all essential images (**U-Boot, Kernel, DTBs, Overlays, Debian Desktop Rootfs, and WIC**) for the **PHYTEC's Phygate Tauri-L IMX8M Mini** board using the [Flexbuild](https://github.com/phytec-india/flexbuild) build system.  
The build system is specially customized for PHYTEC, ensuring no conflicts with other boards.

---

## Clone Flexbuild Repository

```bash
cd ~/
git clone https://github.com/phytec-india/flexbuild.git
cd ~/flexbuild
git checkout Tauri-L-main
```

---

## Host Setup

1. **Requirements:**  
   - Ubuntu 22.04  
   - Docker (Debian 12 docker tested with `bld docker`)

2. **Source Flexbuild Environment:**
    ```bash
    source setup.env
    ```

    - Sets up all paths, variables, symlinks, and safe directories.
    - Ensures all tools (bld, python, etc.) work seamlessly for Flexbuild.

    > **‼ Always run or source `setup.env` before starting any build!**

3. **Start Docker Environment:**
    ```bash
    bld docker
    ```
    - Ensures build isolation and repeatability.

4. **Inside Docker:**  
    ```bash
    source setup.env
    ```  

---

## U-Boot Build

```bash
bld uboot -m imx8mm_phygate-tauri-l
```
- Fetches PHYTEC's U-Boot source and builds for the Tauri-L board.

**Sources:**
- Repo: `git://git.phytec.de/u-boot-imx`
- Tag: `v2022.04_2.2.2-phy5`

**Key Paths:**
- Sources: `components_lsdk2506/bsp/uboot-phytec`
- Build: `build_lsdk2506/bsp/uboot-phytec/imx8mm_phygate-tauri-l/output/phycore-imx8mm_defconfig`
- Final Binary: `build_lsdk2506/images/imx-boot`

---

## Linux Kernel Build

```bash
bld linux -m imx8mm_phygate-tauri-l
```
- Fetches and builds custom Linux kernel for Tauri-L.

**Sources:**
- Repo: `git://git.phytec.de/linux-imx`
- Tag: `v5.15.71_2.2.2-phy3`

**Key Paths:**
- Sources: `components_lsdk2506/linux/linux-phytec/`
- Build: `build_lsdk2506/linux/linux-phytec/arm64/IMX/output/v5.15.71_2.2.2-phy3`
- Final Images: `build_lsdk2506/linux/linux-phytec/arm64/IMX/`
    - Includes: `Image`, DTBs (`oftree`), overlays (`*.dtbo`), kernel modules, etc.

---

## Firmware

```bash
bld imx_firmware -m imx8mm_phygate-tauri-l
```
- Installs common NXP firmware files.

**Key Paths:**
- Source: `components_lsdk2506/bsp/imx_firmware`
- Output: `build_lsdk2506/bsp/imx_firmware/lib/firmware`

---

## Boot Partition

```bash
bld boot -m imx8mm_phygate-tauri-l
```
- Creates boot partition with kernel, DTBs, overlays, modules, firmware.

**Key Paths:**
- Partition: `build_lsdk2506/images/boot_IMX_arm64_phytec/boot_partition_phygate-tauri-imx8mm/`
    - Files: `Image`, `oftree`, U-Boot (`imx-boot`), many overlays (`*.dtbo`)
    - Kernel modules and firmware included

**Example Tree:**
```
boot_partition_phygate-tauri-imx8mm/
├── Image
├── ... dtbo overlays ...
├── imx-boot
└── oftree
```

---

## Root Filesystem (Rootfs)

```bash
bld rfs -m imx8mm_phygate-tauri-l -r debian:desktop
```
- Builds Debian desktop root filesystem.

**Components Path:**  
- `components_lsdk2506/bookworm_desktop_arm64/`  
    - Files: `config.yaml`, `manifest`, `rootfs`

**Build Output:**  
- `build_lsdk2506/rfs/rootfs_lsdk2506_debian_desktop_arm64/`  
    - Standard Linux directories: `bin`, `boot`, `dev`, `etc`, etc.

---

## Pack the Rootfs

```bash
bld packrfs -m imx8mm_phygate-tauri-l
```
- Compresses rootfs folder to tarball (`.tar.zst`) for deployment.

**Output Path:**  
- `build_lsdk2506/images/rootfs_lsdk2506_debian_desktop_arm64_YYYYMMDDHHMM.tar.zst`  
- Symlink: `rootfs_lsdk2506_debian_desktop_arm64.tar.zst`

---

## 💽 Generate WIC Image (Whole Disk Image)

```bash
bld do_wic -m imx8mm_phygate-tauri-l
```
- Packs boot and rootfs into WIC image, ready for flashing.

**Output Path:**  
- `build_lsdk2506/images/imx8mm_phygate-tauri-l.wic`

---

## Full Build Command Sequence

> **📝 You MUST run commands in this order for a successful build!**

```bash
cd ~/
git clone https://github.com/phytec-india/flexbuild.git
cd ~/flexbuild
git checkout Tauri-L-main
source setup.env
bld docker
# Inside Docker also run:
source setup.env
bld uboot -m imx8mm_phygate-tauri-l
bld linux -m imx8mm_phygate-tauri-l
bld imx_firmware -m imx8mm_phygate-tauri-l
bld boot -m imx8mm_phygate-tauri-l
bld rfs -m imx8mm_phygate-tauri-l -r debian:desktop
bld packrfs -m imx8mm_phygate-tauri-l
bld do_wic -m imx8mm_phygate-tauri-l
```

---

## 🏁 Conclusion

**Congratulations!**  
You have successfully built all the essential images (*U-Boot, Kernel, DTBs, overlays, rootfs, and WIC*) using Flexbuild for the PHYTEC Phygate Tauri-L IMX8M Mini board.

- For troubleshooting or reference, visit: [PHYTEC Flexbuild GitHub](https://github.com/phytec-india/flexbuild)
- Always stick to the above order for a smooth build process.
- Enjoy deploying your custom images!

---

**⭐️ _PHYTEC Flexbuild makes embedded Linux easy and reliable for your hardware!_ ⭐️**
