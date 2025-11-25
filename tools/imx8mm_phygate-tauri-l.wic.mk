# ============================================================
#  i.MX8MM Image Creation Makefile for MACHINE=imx8mm_phygate-tauri-l
#  Author: T S Rameshkumar <rameshkumar.t@phytecembedded.in>
#  Purpose:
#    - Generate a .wic image containing:
#        - Bootloader (imx-boot)
#        - Boot partition (kernel, dtbs, overlays)
#        - Root filesystem (.tar/.tar.gz/.tar.xz/.tar.zst)
# ============================================================

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

# === Configuration ===
MACHINE ?= imx8mm_phygate-tauri-l
IMAGE_NAME := $(MACHINE).wic
IMAGE_SIZE_MB := 7373
BOOT_PART_START_MB := 4
BOOT_PART_SIZE_MB := 100

# === Paths ===
IMAGES_DIR := $(CURDIR)
WIC_IMAGE := $(IMAGES_DIR)/$(IMAGE_NAME)
BOOT_DIR := $(IMAGES_DIR)/boot_IMX_arm64_phytec/boot_partition_phygate-tauri-imx8mm
BOOTLOADER := $(IMAGES_DIR)/imx-boot
ROOTFS_TARBALL := $(shell ls -1t $(CURDIR)/rootfs_lsdk2506_debian_desktop_arm64_*.tar.zst 2>/dev/null | head -n1)

MOUNT_BOOT := /mnt/imx8boot
MOUNT_ROOT := /mnt/imx8root

# Ensure we show helpful errors when missing tools
REQUIRED_TOOLS := dd parted sfdisk losetup mkfs.fat mkfs.ext4 tar realpath stat

.PHONY: create_image
create_image:
	@echo "[INFO] Checking required tools..."
	for t in $(REQUIRED_TOOLS); do command -v $$t >/dev/null 2>&1 || { echo "[ERROR] Required tool '$$t' not found in PATH"; exit 1; }; done
	echo "[DEBUG] ROOTFS_TARBALL resolved to: $(ROOTFS_TARBALL)"
	if [ -z "$(ROOTFS_TARBALL)" ] || [ ! -f "$(ROOTFS_TARBALL)" ]; then
		echo -e "\033[1;31m[ERROR] Rootfs tarball not found in $(CURDIR)\033[0m"
		exit 1
	fi
	if [ ! -f "$(BOOTLOADER)" ]; then
		echo -e "\033[1;31m[ERROR] Bootloader not found: $(BOOTLOADER)\033[0m"
		exit 1
	fi
	if [ ! -d "$(BOOT_DIR)" ]; then
		echo -e "\033[1;31m[ERROR] Boot directory not found: $(BOOT_DIR)\033[0m"
		exit 1
	fi

	echo -e "\033[0;32m[INFO] Starting image generation for MACHINE=$(MACHINE)\033[0m"
	echo -e "\033[0;32m[INFO] Creating blank image: $(WIC_IMAGE) ($(IMAGE_SIZE_MB) MB)\033[0m"
	mkdir -p "$(IMAGES_DIR)"
	sudo dd if=/dev/zero of="$(WIC_IMAGE)" bs=1M count=$(IMAGE_SIZE_MB) status=progress

	echo -e "\033[0;32m[INFO] Partitioning image...\033[0m"
	sudo parted "$(WIC_IMAGE)" --script mklabel msdos
	sudo parted "$(WIC_IMAGE)" --script mkpart primary fat16 $$(($(BOOT_PART_START_MB)))MiB $$(($(BOOT_PART_START_MB) + $(BOOT_PART_SIZE_MB)))MiB
	sudo sfdisk --part-type "$(WIC_IMAGE)" 1 0x0E
	sudo sfdisk --part-attrs "$(WIC_IMAGE)" 1 0x20
	sudo sfdisk --activate "$(WIC_IMAGE)" 1
	sudo parted "$(WIC_IMAGE)" --script print
	echo -e "\033[0;32m[INFO] Partition flags after setting (expect: boot, lba)\033[0m"
	sudo fdisk -l "$(WIC_IMAGE)"
	sudo parted "$(WIC_IMAGE)" --script mkpart primary ext4 $$(($(BOOT_PART_START_MB) + $(BOOT_PART_SIZE_MB)))MiB 100%

	echo -e "\033[0;32m[INFO] Formatting partitions...\033[0m"

	# Setup cleanup on exit
	LOOPDEV=""
	cleanup() {
		local rc=$$?
		set +e
		   if mountpoint -q "$(MOUNT_BOOT)"; then sudo umount "$(MOUNT_BOOT)"; fi
		   if mountpoint -q "$(MOUNT_ROOT)"; then sudo umount "$(MOUNT_ROOT)"; fi
		   if [ -n "$$LOOPDEV" ]; then sudo losetup -d "$$LOOPDEV" >/dev/null 2>&1 || true; fi
		   # Detach any loop devices associated with the WIC image (safety cleanup)
		   LOOP_DEVS=$$(sudo losetup -a | grep "$(WIC_IMAGE)" | cut -d: -f1)
		   if [ -n "$$LOOP_DEVS" ]; then
			   echo "[INFO] Detaching loop devices for $(WIC_IMAGE)..."
			   for loopdev in $$LOOP_DEVS; do
				   MOUNTS=$$(mount | grep "$$loopdev" | awk '{print $$3}')
				   if [ -n "$$MOUNTS" ]; then
					   echo "[INFO] Unmounting partitions for $$loopdev..."
					   for mnt in $$MOUNTS; do
						   echo "   Unmounting $$mnt"
						   sudo umount -lf "$$mnt" || echo "Failed to unmount $$mnt"
					   done
				   else
					   echo "[INFO] No active mounts for $$loopdev."
				   fi
				   echo "[INFO] Detaching $$loopdev..."
				   sudo losetup -d "$$loopdev" || echo "Failed to detach $$loopdev"
			   done
			   echo "[INFO] All matching loop devices have been safely detached."
			   echo -e "\034[1;32m[SUCCESS] Detaching loop devices successful\033[0m"
		   fi
		   exit $$rc
	}
	trap cleanup EXIT

	# Attach and create filesystems
	LOOPDEV=$$(sudo losetup --show -fP "$(WIC_IMAGE)")
	if [ -z "$$LOOPDEV" ]; then
		echo -e "\033[1;31m[ERROR] Failed to set up loop device.\033[0m"
		exit 1
	fi

	BOOT_DEV="$${LOOPDEV}p1"
	ROOT_DEV="$${LOOPDEV}p2"

	# Some systems create partitions as ${LOOPDEV}pN, others as ${LOOPDEV} (with loopXp1). Check both.
	if [ ! -b "$$BOOT_DEV" ] && [ -b "$${LOOPDEV}p1" ]; then BOOT_DEV="$${LOOPDEV}p1"; fi
	if [ ! -b "$$ROOT_DEV" ] && [ -b "$${LOOPDEV}p2" ]; then ROOT_DEV="$${LOOPDEV}p2"; fi
	if [ ! -b "$$BOOT_DEV" ] || [ ! -b "$$ROOT_DEV" ]; then
		# fallback: use kpartx to create mappings if available
		if command -v kpartx >/dev/null 2>&1; then
			echo -e "[INFO] Using kpartx to create partition mappings..."
			sudo kpartx -av "$$LOOPDEV"
			# kpartx creates /dev/mapper/loopNp1 style devices; attempt to find them
			sleep 1
			BOOT_DEV=$$(ls /dev/mapper | grep "$$(basename $$LOOPDEV)" | grep -E 'p1|loop' | head -n1 || true)
			ROOT_DEV=$$(ls /dev/mapper | grep "$$(basename $$LOOPDEV)" | grep -E 'p2|loop' | head -n1 || true)
			if [ -n "$$BOOT_DEV" ] && [ -n "$$ROOT_DEV" ]; then
				BOOT_DEV="/dev/mapper/$$BOOT_DEV"
				ROOT_DEV="/dev/mapper/$$ROOT_DEV"
			fi
		fi
	fi

	if [ ! -b "$$BOOT_DEV" ] || [ ! -b "$$ROOT_DEV" ]; then
		echo -e "\033[1;31m[ERROR] Partition devices not found: $$BOOT_DEV $$ROOT_DEV\033[0m"
		exit 1
	fi

	echo -e "[INFO] Boot dev: $$BOOT_DEV   Root dev: $$ROOT_DEV"

	sudo mkfs.fat -F 16 -n boot "$$BOOT_DEV"
	sudo mkfs.ext4 -L root "$$ROOT_DEV"

	sudo mkdir -p "$(MOUNT_BOOT)" "$(MOUNT_ROOT)"
	echo -e "\033[0;32m[INFO] Mounting partitions...\033[0m"
	sudo mount "$$BOOT_DEV" "$(MOUNT_BOOT)"
	sudo mount "$$ROOT_DEV" "$(MOUNT_ROOT)"

	echo -e "\033[0;32m[INFO] Copying boot files...\033[0m"
	sudo cp -r "$(BOOT_DIR)"/* "$(MOUNT_BOOT)/"

	echo -e "\033[0;32m[INFO] Extracting rootfs from $(ROOTFS_TARBALL)...\033[0m"
	case "$(ROOTFS_TARBALL)" in
		*.tar) sudo tar -xpf "$(ROOTFS_TARBALL)" -C "$(MOUNT_ROOT)";;
		*.tar.gz|*.tgz) sudo tar -xpf "$(ROOTFS_TARBALL)" --gzip -C "$(MOUNT_ROOT)";;
		*.tar.xz|*.txz) sudo tar -xpf "$(ROOTFS_TARBALL)" --xz -C "$(MOUNT_ROOT)";;
		*.tar.zst|*.tzst)
			if command -v unzstd >/dev/null 2>&1; then
				sudo unzstd -c "$(ROOTFS_TARBALL)" | sudo tar -xpf - -C "$(MOUNT_ROOT)"
			else
				echo -e "\033[1;31m[ERROR] 'unzstd' not found. Please install zstd to handle .zst rootfs.\033[0m"
				exit 1
			fi;;
		*) echo -e "\033[1;31m[ERROR] Unsupported rootfs format: $(ROOTFS_TARBALL)\033[0m"; exit 1;;
	esac

	echo -e "\033[0;32m[INFO] Installing bootloader ($(BOOTLOADER))...\033[0m"
	# write imx-boot at proper offset (seek=33 * 1k blocks)
	sudo dd if="$(BOOTLOADER)" of="$$LOOPDEV" bs=1k seek=33 conv=notrunc status=none

	echo -e "\033[0;32m[INFO] Cleaning up and syncing...\033[0m"
	sync
	# explicitly unmount and detach before leaving (trap will handle, but unmount now)
	sudo umount "$(MOUNT_BOOT)" || true
	sudo umount "$(MOUNT_ROOT)" || true
	sudo losetup -d "$$LOOPDEV" || true
	LOOPDEV=""

	abswic=$$(realpath "$(WIC_IMAGE)")
	abperms=$$(stat -c '%A %U:%G' "$(WIC_IMAGE)")
	sudo chown -R $$(whoami):$$(whoami) "$(WIC_IMAGE)"
	echo -e "\033[1;32m[SUCCESS] WIC Image created successfully with permissions: $$abperms\033[0m"
	echo "$$abswic"

	# clear trap
	trap - EXIT
	# Always exit successfully if we reach here (ignore non-critical cleanup errors)
	true
