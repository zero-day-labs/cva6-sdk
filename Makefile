# Makefile for RISC-V toolchain; run 'make help' for usage. set XLEN here to 32 or 64.

XLEN     := 64
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    := $(ROOT)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

NR_CORES := $(shell nproc)

# Paths to folders
BENCHMARK_DIR := $(ROOT)/benchmarks
SPLASH3_DIR := $(BENCHMARK_DIR)/Splash-3
CACHETEST_DIR := $(BENCHMARK_DIR)/cachetest

TOOLS_DIR := $(ROOT)/tools
BUILDROOT_DIR := $(TOOLS_DIR)/buildroot

SWSTACK_DIR := $(ROOT)/stack
OPENSBI_DIR := $(SWSTACK_DIR)/opensbi
LINUX_DIR := $(SWSTACK_DIR)/linux
ROOTFS_DIR := $(LINUX_DIR)/rootfs


CONFIGS_DIR := $(ROOT)/configs

TOOLCHAIN_PREFIX := $(BUILDROOT_DIR)/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy

# SBI options
PLATFORM := fpga/alsaqr
FW_FDT_PATH ?=
sbi-mk = PLATFORM=$(PLATFORM) CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(if $(FW_FDT_PATH),FW_FDT_PATH=$(FW_FDT_PATH),)
ifeq ($(XLEN), 32)
sbi-mk += PLATFORM_RISCV_ISA=rv32ima PLATFORM_RISCV_XLEN=32
else
sbi-mk += PLATFORM_RISCV_ISA=rv64imafdc PLATFORM_RISCV_XLEN=64
endif

# default make flags
buildroot-mk       		= -j$(NR_CORES)

# linux image
buildroot_defconfig = $(CONFIGS_DIR)/buildroot$(XLEN)_defconfig
linux_defconfig = $(CONFIGS_DIR)/linux$(XLEN)_defconfig
busybox_defconfig = $(CONFIGS_DIR)/busybox$(XLEN).config

install-dir:
	mkdir -p $(RISCV)

build-buildroot-defconfig:
	rm -rf $(buildroot_defconfig) 
	cp $(buildroot_defconfig)_base $(buildroot_defconfig)
	@echo "BR2_ROOTFS_OVERLAY=\"$(ROOTFS_DIR)\"" >> $(buildroot_defconfig) 
	@echo "BR2_PACKAGE_BUSYBOX_CONFIG=\"$(busybox_defconfig)\"" >> $(buildroot_defconfig) 
	@echo "BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=\"$(linux_defconfig)\"" >> $(buildroot_defconfig) 

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C $(BUILDROOT_DIR) defconfig BR2_DEFCONFIG=$(buildroot_defconfig)
	make -C $(BUILDROOT_DIR) host-gcc-final $(buildroot-mk)

all: $(CC)

# benchmark for the cache subsystem
$(ROOTFS_DIR)/cachetest.elf: $(CC)
	cd $(CACHETEST_DIR)/ && $(CC) cachetest.c -o cachetest.elf
	cp $(CACHETEST_DIR)/cachetest.elf $@

$(ROOTFS_DIR)/perf: $(CC)
	make -C $(SPLASH3_DIR)/codes all
	mkdir -p $@
	cp -r $(SPLASH3_DIR)/codes/splash3 $@/splash3
	cp -r $(SPLASH3_DIR)/codes/kernels $@/splash3/codes

$(RISCV)/vmlinux: build-buildroot-defconfig $(CC) $(ROOTFS_DIR)/cachetest.elf $(ROOTFS_DIR)/perf
	mkdir -p $(RISCV)
	make -C $(BUILDROOT_DIR) $(buildroot-mk)
	cp $(BUILDROOT_DIR)/output/images/vmlinux $@

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

$(RISCV)/Image.gz: $(RISCV)/Image
	gzip -9 -k --force $< > $@

$(RISCV)/fw_payload.bin: $(RISCV)/Image
	make -C $(OPENSBI_DIR) FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

$(RISCV)/test_fw_payload.bin:
	make -C $(OPENSBI_DIR) $(sbi-mk)
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

# need to run flash-sdcard with sudo -E, be careful to set the correct SDDEVICE
# Number of sector required for FWPAYLOAD partition (each sector is 512B)
FWPAYLOAD_SECTORSTART := 2048
FWPAYLOAD_SECTORSIZE = $(shell ls -l --block-size=512 $(RISCV)/fw_payload.bin | cut -d " " -f5 )
FWPAYLOAD_SECTOREND = $(shell echo $(FWPAYLOAD_SECTORSTART)+$(FWPAYLOAD_SECTORSIZE) | bc)
SDDEVICE_PART1 = $(shell lsblk $(SDDEVICE) -no PATH | head -2 | tail -1)
SDDEVICE_PART2 = $(shell lsblk $(SDDEVICE) -no PATH | head -3 | tail -1)
# Always flash uImage at 512M, easier for u-boot boot command
UIMAGE_SECTORSTART := 512M
flash-sdcard: format-sd
	dd if=$(RISCV)/fw_payload.bin of=$(SDDEVICE_PART1) status=progress oflag=sync bs=1M
	dd if=$(RISCV)/uImage         of=$(SDDEVICE_PART2) status=progress oflag=sync bs=1M

format-sd: $(SDDEVICE)
	@test -n "$(SDDEVICE)" || (echo 'SDDEVICE must be set, Ex: make flash-sdcard SDDEVICE=/dev/sdc' && exit 1)
	sgdisk --clear -g --new=1:$(FWPAYLOAD_SECTORSTART):$(FWPAYLOAD_SECTOREND) --new=2:$(UIMAGE_SECTORSTART):0 --typecode=1:3000 --typecode=2:8300 $(SDDEVICE)

# specific recipes
gcc: $(CC)
vmlinux: $(RISCV)/vmlinux
fw_payload.bin: $(RISCV)/fw_payload.bin
test_fw_payload.bin: $(RISCV)/test_fw_payload.bin

images: $(CC) $(RISCV)/fw_payload.bin

alsaqr.dtb:
	make -C $(OPENSBI_DIR) $(sbi-mk) alsaqr.dts
	dtc -I dts $(OPENSBI_DIR)/platform/$(PLATFORM)/fdt_gen/alsaqr.dts -O dtb -o $@

clean:
	rm -rf $(RISCV)/vmlinux
	rm -rf $(CACHETEST_DIR)/*.elf $(ROOTFS_DIR)/cachetest.elf
	make -C $(SPLASH3_DIR)/codes clean
	rm -rf $(ROOTFS_DIR)/perf/*
	rm -rf $(buildroot_defconfig)
	rm -rf $(RISCV)/fw_payload.bin $(RISCV)/Image.gz
	make -C $(OPENSBI_DIR) distclean

lqemu:
	qemu-system-riscv64 -M virt -m 256M -nographic     -bios $(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin       -kernel install64/Image         -append "root=/dev/vda rw console=ttyS0"

clean-all: clean
	rm -rf $(RISCV)
	make -C $(BUILDROOT_DIR) clean

.PHONY: gcc vmlinux images help fw_payload.bin alsaqr.dtb test_fw_payload.bin

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|fw_payload.bin]"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
