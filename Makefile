# Makefile for RISC-V toolchain; run 'make help' for usage. set XLEN here to 32 or 64.

XLEN     := 64
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

TOOLCHAIN_PREFIX := $(RISCV)/bin/riscv$(XLEN)-unknown-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy
MKIMAGE     := u-boot/tools/mkimage

NR_CORES := $(shell nproc)

# SBI options
PLATFORM := generic
FW_FDT_PATH ?=


# specific flags and rules for 32 / 64 version
ifeq ($(XLEN), 32)
isa-sim-co            = --prefix=$(RISCV) --with-isa=RV32IMA --with-priv=MSU
else
isa-sim-co            = --prefix=$(RISCV)
endif

# default make flags
isa-sim-mk              = -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)
buildroot-mk       		= -j$(NR_CORES)

# linux image
buildroot_defconfig = configs/buildroot$(XLEN)_defconfig
linux_defconfig = configs/linux$(XLEN)_defconfig
busybox_defconfig = configs/busybox$(XLEN).config

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

# benchmark for the cache subsystem
rootfs/cachetest.elf: $(CC)
	cd ./cachetest/ && $(CC) cachetest.c -o cachetest.elf
	cp ./cachetest/cachetest.elf $@

# cool command-line tetris
rootfs/tetris: $(CC)
	cd ./vitetris/ && make clean && ./configure CC=$(CC) && make
	cp ./vitetris/tetris $@

Image: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig) $(CC) rootfs/cachetest.elf rootfs/tetris
	mkdir -p $(RISCV)
	make -C buildroot $(buildroot-mk)
	cp buildroot/output/images/Image Image

Image.gz: Image
	gzip -9 -k --force $< > $@

# U-Boot-compatible Linux image
uImage: Image.gz
	u-boot/tools/mkimage -A riscv -O linux -T kernel -C gzip -a 84000000 -e 84000000 -n "linux" -d $< $@

# U-Boot image with OpenSBI as payload
u-boot/u-boot.itb u-boot/u-boot.bin: fw_dynamic.bin
	make -C u-boot pulp-platform_occamy_defconfig OPENSBI=../fw_dynamic.bin
	make -C u-boot CROSS_COMPILE=$(RISCV)/bin/riscv64-unknown-linux-gnu- OPENSBI=../fw_dynamic.bin

# OpenSBI without payload
fw_dynamic.elf fw_dynamic.bin:
	make -C opensbi PLATFORM=$(PLATFORM) CROSS_COMPILE=$(RISCV)/bin/riscv64-unknown-linux-gnu- $(if $(FW_FDT_PATH),FW_FDT_PATH=$(FW_FDT_PATH),)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_dynamic.elf fw_dynamic.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_dynamic.bin fw_dynamic.bin

clean:
	rm -rf $(RISCV)/vmlinux cachetest/*.elf rootfs/tetris rootfs/cachetest.elf
	rm -rf $(RISCV)/fw_payload.bin $(RISCV)/uImage $(RISCV)/Image.gz
	make -C u-boot clean
	make -C opensbi distclean

clean-all: clean
	rm -rf $(RISCV) riscv-isa-sim/build riscv-tests/build
	make -C buildroot clean

.PHONY: gcc vmlinux images help fw_payload.bin uImage

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc isa-sim tests"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|uImage|fw_payload.bin]"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
